# =============================================================================
# Prowlarr — Indexer Aggregation
# =============================================================================
# Migrated from LXC 110. Centralized indexer manager for Sonarr/Radarr.
# Longhorn PVC for config/DB, exposed via Traefik IngressRoute.
# =============================================================================

# Variables
variable "prowlarr_storage_size" {
  description = "Storage size for Prowlarr config/database"
  type        = string
  default     = "2Gi"
}

variable "prowlarr_memory_request" {
  description = "Memory request for Prowlarr container"
  type        = string
  default     = "128Mi"
}

variable "prowlarr_memory_limit" {
  description = "Memory limit for Prowlarr container"
  type        = string
  default     = "512Mi"
}

variable "prowlarr_cpu_request" {
  description = "CPU request for Prowlarr container"
  type        = string
  default     = "100m"
}

variable "prowlarr_cpu_limit" {
  description = "CPU limit for Prowlarr container"
  type        = string
  default     = "500m"
}

variable "prowlarr_image_tag" {
  description = "Prowlarr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "prowlarr" {
  metadata {
    name = "prowlarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "prowlarr"
    })
  }
}

# Persistent Volume Claim (Longhorn — config/DB)
resource "kubernetes_persistent_volume_claim" "prowlarr_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "prowlarr-config"
    namespace = kubernetes_namespace.prowlarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.prowlarr_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "prowlarr" {
  depends_on = [
    kubernetes_persistent_volume_claim.prowlarr_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "prowlarr"
    namespace = kubernetes_namespace.prowlarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "prowlarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "prowlarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "prowlarr"
        })
      }

      spec {
        container {
          name  = "prowlarr"
          image = "linuxserver/prowlarr:${var.prowlarr_image_tag}"

          port {
            container_port = 9696
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
            name       = "prowlarr-config"
            mount_path = "/config"
          }

          resources {
            requests = {
              memory = var.prowlarr_memory_request
              cpu    = var.prowlarr_cpu_request
            }
            limits = {
              memory = var.prowlarr_memory_limit
              cpu    = var.prowlarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = 9696
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 9696
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "prowlarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prowlarr_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "prowlarr" {
  depends_on = [
    kubernetes_deployment.prowlarr
  ]

  metadata {
    name      = "prowlarr-service"
    namespace = kubernetes_namespace.prowlarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "prowlarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "prowlarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 9696
    }
  }
}

# Outputs
output "prowlarr_info" {
  description = "Prowlarr indexer aggregation information"
  value = {
    namespace    = kubernetes_namespace.prowlarr.metadata[0].name
    service_name = kubernetes_service.prowlarr.metadata[0].name
    storage_size = var.prowlarr_storage_size

    access = {
      web_ui = "https://prowlarr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.prowlarr.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.prowlarr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.prowlarr.metadata[0].name} -l app=prowlarr -f"
    }
  }

  sensitive = true
}
