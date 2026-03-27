# =============================================================================
# Cleanuparr — Library Cleanup Automation
# =============================================================================
# Automates library cleanup via Sonarr/Radarr APIs.
# Uses Longhorn PVC for config/database persistence.
# =============================================================================

# Variables
variable "cleanuparr_enabled" {
  description = "Enable Cleanuparr deployment"
  type        = bool
  default     = true
}

variable "cleanuparr_memory_request" {
  description = "Memory request for Cleanuparr container"
  type        = string
  default     = "128Mi"
}

variable "cleanuparr_memory_limit" {
  description = "Memory limit for Cleanuparr container"
  type        = string
  default     = "256Mi"
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

variable "cleanuparr_storage_size" {
  description = "Storage size for Cleanuparr config PVC"
  type        = string
  default     = "512Mi"
}

variable "cleanuparr_image_tag" {
  description = "Cleanuparr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "cleanuparr" {
  count = var.cleanuparr_enabled ? 1 : 0

  metadata {
    name = "cleanuparr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cleanuparr"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "cleanuparr_config" {
  count = var.cleanuparr_enabled ? 1 : 0

  metadata {
    name      = "cleanuparr-config"
    namespace = kubernetes_namespace.cleanuparr[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.cleanuparr_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "cleanuparr" {
  count = var.cleanuparr_enabled ? 1 : 0

  metadata {
    name      = "cleanuparr"
    namespace = kubernetes_namespace.cleanuparr[0].metadata[0].name
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
          image = "ghcr.io/cleanuparr/cleanuparr:${var.cleanuparr_image_tag}"

          port {
            container_port = 11011
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
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
            tcp_socket {
              port = 11011
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = 11011
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.cleanuparr_config[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "cleanuparr" {
  count = var.cleanuparr_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.cleanuparr
  ]

  metadata {
    name      = "cleanuparr-service"
    namespace = kubernetes_namespace.cleanuparr[0].metadata[0].name
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
      target_port = 11011
    }
  }
}

# Outputs
output "cleanuparr_info" {
  description = "Cleanuparr library cleanup information"
  value = var.cleanuparr_enabled ? {
    namespace    = kubernetes_namespace.cleanuparr[0].metadata[0].name
    service_name = kubernetes_service.cleanuparr[0].metadata[0].name

    access = {
      web_ui = "https://cleanuparr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.cleanuparr[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.cleanuparr[0].metadata[0].name} -l app=cleanuparr -f"
    }
  } : null

  sensitive = true
}
