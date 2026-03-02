# =============================================================================
# Cleanuparr — Library Cleanup Automation
# =============================================================================
# Automates library cleanup via Sonarr/Radarr APIs.
# Stateless — no persistent storage needed.
# =============================================================================

# Variables
variable "cleanuparr_memory_request" {
  description = "Memory request for Cleanuparr container"
  type        = string
  default     = "64Mi"
}

variable "cleanuparr_memory_limit" {
  description = "Memory limit for Cleanuparr container"
  type        = string
  default     = "128Mi"
}

variable "cleanuparr_cpu_request" {
  description = "CPU request for Cleanuparr container"
  type        = string
  default     = "25m"
}

variable "cleanuparr_cpu_limit" {
  description = "CPU limit for Cleanuparr container"
  type        = string
  default     = "200m"
}

variable "cleanuparr_image_tag" {
  description = "Cleanuparr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "cleanuparr" {
  metadata {
    name = "cleanuparr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cleanuparr"
    })
  }
}

# Deployment
resource "kubernetes_deployment" "cleanuparr" {
  metadata {
    name      = "cleanuparr"
    namespace = kubernetes_namespace.cleanuparr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cleanuparr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "cleanuparr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "cleanuparr"
        })
      }

      spec {
        container {
          name  = "cleanuparr"
          image = "flmedicmento/cleanuparr:${var.cleanuparr_image_tag}"

          port {
            container_port = 80
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          resources {
            requests = {
              memory = var.cleanuparr_memory_request
              cpu    = var.cleanuparr_cpu_request
            }
            limits = {
              memory = var.cleanuparr_memory_limit
              cpu    = var.cleanuparr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "cleanuparr" {
  depends_on = [
    kubernetes_deployment.cleanuparr
  ]

  metadata {
    name      = "cleanuparr-service"
    namespace = kubernetes_namespace.cleanuparr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cleanuparr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "cleanuparr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }
}

# Outputs
output "cleanuparr_info" {
  description = "Cleanuparr library cleanup information"
  value = {
    namespace    = kubernetes_namespace.cleanuparr.metadata[0].name
    service_name = kubernetes_service.cleanuparr.metadata[0].name

    access = {
      web_ui = "https://cleanuparr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.cleanuparr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.cleanuparr.metadata[0].name} -l app=cleanuparr -f"
    }
  }

  sensitive = true
}
