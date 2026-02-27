# =============================================================================
# n8n — Workflow Automation Platform
# =============================================================================
# Self-hosted workflow automation tool. Runs in SQLite mode with Longhorn
# persistent storage. Exposed via Traefik IngressRoute (see ingress.tf).
# =============================================================================

# Variables
variable "n8n_storage_size" {
  description = "Storage size for n8n data (SQLite DB, credentials, workflows)"
  type        = string
  default     = "5Gi"
}

variable "n8n_memory_request" {
  description = "Memory request for n8n container"
  type        = string
  default     = "128Mi"
}

variable "n8n_memory_limit" {
  description = "Memory limit for n8n container"
  type        = string
  default     = "512Mi"
}

variable "n8n_cpu_request" {
  description = "CPU request for n8n container"
  type        = string
  default     = "100m"
}

variable "n8n_cpu_limit" {
  description = "CPU limit for n8n container"
  type        = string
  default     = "500m"
}

variable "n8n_image_tag" {
  description = "n8n container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "n8n" {
  metadata {
    name = "n8n"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "n8n"
    })
  }
}

# Persistent Volume Claim (Longhorn)
resource "kubernetes_persistent_volume_claim" "n8n_data" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "n8n-data"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.n8n_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "n8n" {
  depends_on = [
    kubernetes_persistent_volume_claim.n8n_data,
    helm_release.longhorn
  ]

  metadata {
    name      = "n8n"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "n8n"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "n8n"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "n8n"
        })
      }

      spec {
        container {
          name  = "n8n"
          image = "n8nio/n8n:${var.n8n_image_tag}"

          port {
            container_port = 5678
          }

          env {
            name  = "N8N_PORT"
            value = "5678"
          }

          env {
            name  = "N8N_PROTOCOL"
            value = "https"
          }

          env {
            name  = "N8N_HOST"
            value = "n8n.${var.traefik_domain}"
          }

          env {
            name  = "WEBHOOK_URL"
            value = "https://n8n.${var.traefik_domain}/"
          }

          env {
            name  = "GENERIC_TIMEZONE"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "n8n-data"
            mount_path = "/home/node/.n8n"
          }

          resources {
            requests = {
              memory = var.n8n_memory_request
              cpu    = var.n8n_cpu_request
            }
            limits = {
              memory = var.n8n_memory_limit
              cpu    = var.n8n_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 5678
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "n8n-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.n8n_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "n8n" {
  depends_on = [
    kubernetes_deployment.n8n
  ]

  metadata {
    name      = "n8n-service"
    namespace = kubernetes_namespace.n8n.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "n8n"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "n8n"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5678
    }
  }
}

# Outputs
output "n8n_info" {
  description = "n8n workflow automation information"
  value = {
    namespace    = kubernetes_namespace.n8n.metadata[0].name
    service_name = kubernetes_service.n8n.metadata[0].name
    storage_size = var.n8n_storage_size

    access = {
      web_ui = "https://n8n.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.n8n.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.n8n.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.n8n.metadata[0].name} -l app=n8n -f"
    }
  }

  sensitive = true
}
