# =============================================================================
# Jackett — Additional Indexer Support
# =============================================================================
# Provides additional indexer/tracker support for Prowlarr.
# Longhorn PVC for config, no NFS mounts needed.
# =============================================================================

# Variables
variable "jackett_enabled" {
  description = "Enable Jackett deployment"
  type        = bool
  default     = true
}

variable "jackett_storage_size" {
  description = "Storage size for Jackett config"
  type        = string
  default     = "1Gi"
}

variable "jackett_memory_request" {
  description = "Memory request for Jackett container"
  type        = string
  default     = "128Mi"
}

variable "jackett_memory_limit" {
  description = "Memory limit for Jackett container"
  type        = string
  default     = "256Mi"
}

variable "jackett_cpu_request" {
  description = "CPU request for Jackett container"
  type        = string
  default     = "50m"
}

variable "jackett_cpu_limit" {
  description = "CPU limit for Jackett container"
  type        = string
  default     = "500m"
}

variable "jackett_image_tag" {
  description = "Jackett container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "jackett" {
  count = var.jackett_enabled ? 1 : 0

  metadata {
    name = "jackett"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "jackett"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "jackett_config" {
  count = var.jackett_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "jackett-config"
    namespace = kubernetes_namespace.jackett[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.jackett_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "jackett" {
  count = var.jackett_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.jackett_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "jackett"
    namespace = kubernetes_namespace.jackett[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "jackett"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "jackett"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "jackett"
        })
      }

      spec {
        container {
          name  = "jackett"
          image = "linuxserver/jackett:${var.jackett_image_tag}"

          port {
            container_port = 9117
          }

          env {
            name  = "PUID"
            value = "1000"
          }

          env {
            name  = "PGID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "jackett-config"
            mount_path = "/config"
          }

          resources {
            requests = {
              memory = var.jackett_memory_request
              cpu    = var.jackett_cpu_request
            }
            limits = {
              memory = var.jackett_memory_limit
              cpu    = var.jackett_cpu_limit
            }
          }

          liveness_probe {
            tcp_socket {
              port = 9117
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 5
          }

          readiness_probe {
            tcp_socket {
              port = 9117
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }

        volume {
          name = "jackett-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.jackett_config[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "jackett" {
  count = var.jackett_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.jackett
  ]

  metadata {
    name      = "jackett-service"
    namespace = kubernetes_namespace.jackett[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "jackett"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "jackett"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 9117
    }
  }
}

# Outputs
output "jackett_info" {
  description = "Jackett indexer information"
  value = var.jackett_enabled ? {
    namespace    = kubernetes_namespace.jackett[0].metadata[0].name
    service_name = kubernetes_service.jackett[0].metadata[0].name
    storage_size = var.jackett_storage_size

    access = {
      web_ui = "https://jackett.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.jackett[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.jackett[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.jackett[0].metadata[0].name} -l app=jackett -f"
    }
  } : null

  sensitive = true
}
