# =============================================================================
# Radarr — Movie Management
# =============================================================================
# Migrated from LXC 111. Automatic movie downloading and organization.
# Longhorn PVC for config/DB, NFS PVCs for media and downloads.
# =============================================================================

# Variables
variable "radarr_enabled" {
  description = "Enable Radarr deployment"
  type        = bool
  default     = true
}

variable "radarr_config_storage_size" {
  description = "Storage size for Radarr config/database"
  type        = string
  default     = "10Gi"
}

variable "radarr_memory_request" {
  description = "Memory request for Radarr container"
  type        = string
  default     = "512Mi"
}

variable "radarr_memory_limit" {
  description = "Memory limit for Radarr container"
  type        = string
  default     = "2Gi"
}

variable "radarr_cpu_request" {
  description = "CPU request for Radarr container"
  type        = string
  default     = "100m"
}

variable "radarr_cpu_limit" {
  description = "CPU limit for Radarr container"
  type        = string
  default     = "1000m"
}

variable "radarr_image_tag" {
  description = "Radarr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "radarr" {
  count = var.radarr_enabled ? 1 : 0

  metadata {
    name = "radarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "radarr"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "radarr_config" {
  count = var.radarr_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "radarr-config"
    namespace = kubernetes_namespace.radarr[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.radarr_config_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Media (static PV)
resource "kubernetes_persistent_volume" "radarr_media" {
  count = var.radarr_enabled ? 1 : 0

  metadata {
    name   = "radarr-media-pv"
    labels = var.common_labels
  }

  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"

    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = var.nfs_media_share
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "radarr_media" {
  count = var.radarr_enabled ? 1 : 0

  metadata {
    name      = "radarr-media"
    namespace = kubernetes_namespace.radarr[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.radarr_media[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Persistent Volume — NFS Downloads (static PV)
resource "kubernetes_persistent_volume" "radarr_downloads" {
  count = var.radarr_enabled ? 1 : 0

  metadata {
    name   = "radarr-downloads-pv"
    labels = var.common_labels
  }

  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-downloads"

    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = var.nfs_downloads_share
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_downloads]
}

resource "kubernetes_persistent_volume_claim" "radarr_downloads" {
  count = var.radarr_enabled ? 1 : 0

  metadata {
    name      = "radarr-downloads"
    namespace = kubernetes_namespace.radarr[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-downloads"
    volume_name        = kubernetes_persistent_volume.radarr_downloads[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "radarr" {
  count = var.radarr_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.radarr_config,
    kubernetes_persistent_volume_claim.radarr_media,
    kubernetes_persistent_volume_claim.radarr_downloads,
    helm_release.longhorn
  ]

  metadata {
    name      = "radarr"
    namespace = kubernetes_namespace.radarr[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "radarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "radarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "radarr"
        })
      }

      spec {
        container {
          name  = "radarr"
          image = "linuxserver/radarr:${var.radarr_image_tag}"

          port {
            container_port = 7878
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
            name       = "radarr-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "media"
            mount_path = "/media"
          }

          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }

          resources {
            requests = {
              memory = var.radarr_memory_request
              cpu    = var.radarr_cpu_request
            }
            limits = {
              memory = var.radarr_memory_limit
              cpu    = var.radarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = 7878
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 10
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 7878
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 10
            failure_threshold     = 5
          }
        }

        volume {
          name = "radarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.radarr_config[0].metadata[0].name
          }
        }

        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.radarr_media[0].metadata[0].name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.radarr_downloads[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "radarr" {
  count = var.radarr_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.radarr
  ]

  metadata {
    name      = "radarr-service"
    namespace = kubernetes_namespace.radarr[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "radarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "radarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 7878
    }
  }
}

# Outputs
output "radarr_info" {
  description = "Radarr movie management information"
  value = var.radarr_enabled ? {
    namespace    = kubernetes_namespace.radarr[0].metadata[0].name
    service_name = kubernetes_service.radarr[0].metadata[0].name
    config_size  = var.radarr_config_storage_size

    access = {
      web_ui = "https://radarr.${var.traefik_domain}"
    }

    nfs_mounts = {
      media     = "${var.nfs_server}:${var.nfs_media_share}"
      downloads = "${var.nfs_server}:${var.nfs_downloads_share}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.radarr[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.radarr[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.radarr[0].metadata[0].name} -l app=radarr -f"
    }
  } : null

  sensitive = true
}
