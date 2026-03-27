# =============================================================================
# Emby — Media Server
# =============================================================================
# Migrated from LXC 109. Serves media to clients over the network.
# Longhorn PVC for config/metadata, NFS PVC for media library.
#
# Uses a custom image variable to support building from a fork.
# =============================================================================

# Variables
variable "emby_enabled" {
  description = "Enable Emby deployment"
  type        = bool
  default     = true
}

variable "emby_config_storage_size" {
  description = "Storage size for Emby config/metadata"
  type        = string
  default     = "10Gi"
}

variable "emby_memory_request" {
  description = "Memory request for Emby container"
  type        = string
  default     = "512Mi"
}

variable "emby_memory_limit" {
  description = "Memory limit for Emby container"
  type        = string
  default     = "2Gi"
}

variable "emby_cpu_request" {
  description = "CPU request for Emby container"
  type        = string
  default     = "250m"
}

variable "emby_cpu_limit" {
  description = "CPU limit for Emby container"
  type        = string
  default     = "2000m"
}

variable "emby_image" {
  description = "Emby container image (override for custom fork builds)"
  type        = string
  default     = "emby/embyserver"
}

variable "emby_image_tag" {
  description = "Emby container image tag"
  type        = string
  default     = "latest"
}

variable "emby_gpu_enabled" {
  description = "Request GPU resource for Emby hardware transcoding (requires NVIDIA device plugin)"
  type        = bool
  default     = false
}

# Namespace
resource "kubernetes_namespace" "emby" {
  count = var.emby_enabled ? 1 : 0

  metadata {
    name = "emby"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "emby"
    })
  }
}

# Persistent Volume Claim — Config/Metadata (Longhorn)
resource "kubernetes_persistent_volume_claim" "emby_config" {
  count = var.emby_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "emby-config"
    namespace = kubernetes_namespace.emby[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.emby_config_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Media (static PV)
resource "kubernetes_persistent_volume" "emby_media" {
  count = var.emby_enabled ? 1 : 0

  metadata {
    name   = "emby-media-pv"
    labels = var.common_labels
  }

  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"

    persistent_volume_source {
      nfs {
        server    = var.nfs_server
        path      = var.nfs_media_share
        read_only = true
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "emby_media" {
  count = var.emby_enabled ? 1 : 0

  metadata {
    name      = "emby-media"
    namespace = kubernetes_namespace.emby[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadOnlyMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.emby_media[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "emby" {
  count = var.emby_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.emby_config,
    kubernetes_persistent_volume_claim.emby_media,
    helm_release.longhorn
  ]

  metadata {
    name      = "emby"
    namespace = kubernetes_namespace.emby[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "emby"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "emby"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "emby"
        })
      }

      spec {
        container {
          name  = "emby"
          image = "${var.emby_image}:${var.emby_image_tag}"

          port {
            container_port = 8096
            name           = "http"
          }

          port {
            container_port = 8920
            name           = "https"
          }

          env {
            name  = "UID"
            value = "1000"
          }

          env {
            name  = "GID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "emby-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "media"
            mount_path = "/media"
            read_only  = true
          }

          resources {
            requests = {
              memory = var.emby_memory_request
              cpu    = var.emby_cpu_request
            }
            limits = merge(
              {
                memory = var.emby_memory_limit
                cpu    = var.emby_cpu_limit
              },
              var.emby_gpu_enabled ? { "nvidia.com/gpu" = "1" } : {}
            )
          }

          liveness_probe {
            http_get {
              path = "/emby/System/Ping"
              port = 8096
            }
            initial_delay_seconds = 60
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/emby/System/Ping"
              port = 8096
            }
            initial_delay_seconds = 15
            period_seconds        = 5
          }
        }

        volume {
          name = "emby-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.emby_config[0].metadata[0].name
          }
        }

        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.emby_media[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "emby" {
  count = var.emby_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.emby
  ]

  metadata {
    name      = "emby-service"
    namespace = kubernetes_namespace.emby[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "emby"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "emby"
    }

    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = 8096
    }
  }
}

# Outputs
output "emby_info" {
  description = "Emby media server information"
  value = var.emby_enabled ? {
    namespace    = kubernetes_namespace.emby[0].metadata[0].name
    service_name = kubernetes_service.emby[0].metadata[0].name
    config_size  = var.emby_config_storage_size
    image        = "${var.emby_image}:${var.emby_image_tag}"
    gpu_enabled  = var.emby_gpu_enabled

    access = {
      web_ui = "https://emby.${var.traefik_domain}"
    }

    nfs_mounts = {
      media = "${var.nfs_server}:${var.nfs_media_share}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.emby[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.emby[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.emby[0].metadata[0].name} -l app=emby -f"
    }
  } : null

  sensitive = true
}
