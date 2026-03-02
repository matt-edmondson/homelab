# =============================================================================
# Notifiarr — Rich Notifications for Arr Stack
# =============================================================================
# Migrated from LXC 101. Receives webhooks from arr services and sends
# rich notifications to Discord/Telegram/etc.
# Config file from LXC stored as a Kubernetes Secret.
# =============================================================================

# Variables
variable "notifiarr_storage_size" {
  description = "Storage size for Notifiarr config"
  type        = string
  default     = "1Gi"
}

variable "notifiarr_memory_request" {
  description = "Memory request for Notifiarr container"
  type        = string
  default     = "64Mi"
}

variable "notifiarr_memory_limit" {
  description = "Memory limit for Notifiarr container"
  type        = string
  default     = "128Mi"
}

variable "notifiarr_cpu_request" {
  description = "CPU request for Notifiarr container"
  type        = string
  default     = "25m"
}

variable "notifiarr_cpu_limit" {
  description = "CPU limit for Notifiarr container"
  type        = string
  default     = "200m"
}

variable "notifiarr_image_tag" {
  description = "Notifiarr container image tag"
  type        = string
  default     = "latest"
}

variable "notifiarr_config" {
  description = "Contents of the notifiarr.conf configuration file (migrated from LXC 101)"
  type        = string
  sensitive   = true
  default     = ""
}

# Namespace
resource "kubernetes_namespace" "notifiarr" {
  metadata {
    name = "notifiarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "notifiarr"
    })
  }
}

# Secret — Config file (from LXC 101 migration)
resource "kubernetes_secret" "notifiarr_config" {
  count = var.notifiarr_config != "" ? 1 : 0

  metadata {
    name      = "notifiarr-config"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "notifiarr.conf" = var.notifiarr_config
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "notifiarr_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "notifiarr-config"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.notifiarr_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "notifiarr" {
  depends_on = [
    kubernetes_persistent_volume_claim.notifiarr_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "notifiarr"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "notifiarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "notifiarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "notifiarr"
        })
      }

      spec {
        container {
          name  = "notifiarr"
          image = "golift/notifiarr:${var.notifiarr_image_tag}"

          port {
            container_port = 5454
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "notifiarr-config"
            mount_path = "/config"
          }

          dynamic "volume_mount" {
            for_each = var.notifiarr_config != "" ? [1] : []
            content {
              name       = "notifiarr-secret-config"
              mount_path = "/config/notifiarr.conf"
              sub_path   = "notifiarr.conf"
            }
          }

          resources {
            requests = {
              memory = var.notifiarr_memory_request
              cpu    = var.notifiarr_cpu_request
            }
            limits = {
              memory = var.notifiarr_memory_limit
              cpu    = var.notifiarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 5454
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 5454
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "notifiarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.notifiarr_config.metadata[0].name
          }
        }

        dynamic "volume" {
          for_each = var.notifiarr_config != "" ? [1] : []
          content {
            name = "notifiarr-secret-config"
            secret {
              secret_name = kubernetes_secret.notifiarr_config[0].metadata[0].name
            }
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "notifiarr" {
  depends_on = [
    kubernetes_deployment.notifiarr
  ]

  metadata {
    name      = "notifiarr-service"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "notifiarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "notifiarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5454
    }
  }
}

# Outputs
output "notifiarr_info" {
  description = "Notifiarr notification service information"
  value = {
    namespace          = kubernetes_namespace.notifiarr.metadata[0].name
    service_name       = kubernetes_service.notifiarr.metadata[0].name
    storage_size       = var.notifiarr_storage_size
    config_from_secret = var.notifiarr_config != ""

    access = {
      web_ui = "https://notifiarr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.notifiarr.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.notifiarr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.notifiarr.metadata[0].name} -l app=notifiarr -f"
    }
  }

  sensitive = true
}
