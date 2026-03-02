# =============================================================================
# Huntarr — Missing Media Hunter
# =============================================================================
# Monitors Sonarr and Radarr for missing media and triggers searches.
# Longhorn PVC for config, no NFS mounts needed.
# =============================================================================

# Variables
variable "huntarr_storage_size" {
  description = "Storage size for Huntarr config"
  type        = string
  default     = "512Mi"
}

variable "huntarr_memory_request" {
  description = "Memory request for Huntarr container"
  type        = string
  default     = "64Mi"
}

variable "huntarr_memory_limit" {
  description = "Memory limit for Huntarr container"
  type        = string
  default     = "128Mi"
}

variable "huntarr_cpu_request" {
  description = "CPU request for Huntarr container"
  type        = string
  default     = "25m"
}

variable "huntarr_cpu_limit" {
  description = "CPU limit for Huntarr container"
  type        = string
  default     = "200m"
}

variable "huntarr_image_tag" {
  description = "Huntarr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "huntarr" {
  metadata {
    name = "huntarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "huntarr"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "huntarr_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "huntarr-config"
    namespace = kubernetes_namespace.huntarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.huntarr_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "huntarr" {
  depends_on = [
    kubernetes_persistent_volume_claim.huntarr_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "huntarr"
    namespace = kubernetes_namespace.huntarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "huntarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "huntarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "huntarr"
        })
      }

      spec {
        container {
          name  = "huntarr"
          image = "huntarr/huntarr:${var.huntarr_image_tag}"

          port {
            container_port = 9705
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "huntarr-config"
            mount_path = "/config"
          }

          resources {
            requests = {
              memory = var.huntarr_memory_request
              cpu    = var.huntarr_cpu_request
            }
            limits = {
              memory = var.huntarr_memory_limit
              cpu    = var.huntarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 9705
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 9705
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "huntarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.huntarr_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "huntarr" {
  depends_on = [
    kubernetes_deployment.huntarr
  ]

  metadata {
    name      = "huntarr-service"
    namespace = kubernetes_namespace.huntarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "huntarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "huntarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 9705
    }
  }
}

# Outputs
output "huntarr_info" {
  description = "Huntarr missing media hunter information"
  value = {
    namespace    = kubernetes_namespace.huntarr.metadata[0].name
    service_name = kubernetes_service.huntarr.metadata[0].name
    storage_size = var.huntarr_storage_size

    access = {
      web_ui = "https://huntarr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.huntarr.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.huntarr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.huntarr.metadata[0].name} -l app=huntarr -f"
    }
  }

  sensitive = true
}
