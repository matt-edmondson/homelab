# =============================================================================
# Sonarr — TV Show Management
# =============================================================================
# Migrated from LXC 112. Automatic TV show downloading and organization.
# Longhorn PVC for config/DB, NFS PVCs for media and downloads.
# =============================================================================

# Variables
variable "sonarr_config_storage_size" {
  description = "Storage size for Sonarr config/database"
  type        = string
  default     = "2Gi"
}

variable "sonarr_memory_request" {
  description = "Memory request for Sonarr container"
  type        = string
  default     = "256Mi"
}

variable "sonarr_memory_limit" {
  description = "Memory limit for Sonarr container"
  type        = string
  default     = "1Gi"
}

variable "sonarr_cpu_request" {
  description = "CPU request for Sonarr container"
  type        = string
  default     = "100m"
}

variable "sonarr_cpu_limit" {
  description = "CPU limit for Sonarr container"
  type        = string
  default     = "1000m"
}

variable "sonarr_image_tag" {
  description = "Sonarr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "sonarr" {
  metadata {
    name = "sonarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sonarr"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "sonarr_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "sonarr-config"
    namespace = kubernetes_namespace.sonarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.sonarr_config_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Media (static PV, not dynamically provisioned)
resource "kubernetes_persistent_volume" "sonarr_media" {
  metadata {
    name   = "sonarr-media-pv"
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

resource "kubernetes_persistent_volume_claim" "sonarr_media" {
  metadata {
    name      = "sonarr-media"
    namespace = kubernetes_namespace.sonarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.sonarr_media.metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Persistent Volume — NFS Downloads (static PV)
resource "kubernetes_persistent_volume" "sonarr_downloads" {
  metadata {
    name   = "sonarr-downloads-pv"
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

resource "kubernetes_persistent_volume_claim" "sonarr_downloads" {
  metadata {
    name      = "sonarr-downloads"
    namespace = kubernetes_namespace.sonarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-downloads"
    volume_name        = kubernetes_persistent_volume.sonarr_downloads.metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "sonarr" {
  depends_on = [
    kubernetes_persistent_volume_claim.sonarr_config,
    kubernetes_persistent_volume_claim.sonarr_media,
    kubernetes_persistent_volume_claim.sonarr_downloads,
    helm_release.longhorn
  ]

  metadata {
    name      = "sonarr"
    namespace = kubernetes_namespace.sonarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sonarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "sonarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "sonarr"
        })
      }

      spec {
        container {
          name  = "sonarr"
          image = "linuxserver/sonarr:${var.sonarr_image_tag}"

          port {
            container_port = 8989
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
            name       = "sonarr-config"
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
              memory = var.sonarr_memory_request
              cpu    = var.sonarr_cpu_request
            }
            limits = {
              memory = var.sonarr_memory_limit
              cpu    = var.sonarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = 8989
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 8989
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "sonarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sonarr_config.metadata[0].name
          }
        }

        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sonarr_media.metadata[0].name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sonarr_downloads.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "sonarr" {
  depends_on = [
    kubernetes_deployment.sonarr
  ]

  metadata {
    name      = "sonarr-service"
    namespace = kubernetes_namespace.sonarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sonarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "sonarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8989
    }
  }
}

# Outputs
output "sonarr_info" {
  description = "Sonarr TV show management information"
  value = {
    namespace    = kubernetes_namespace.sonarr.metadata[0].name
    service_name = kubernetes_service.sonarr.metadata[0].name
    config_size  = var.sonarr_config_storage_size

    access = {
      web_ui = "https://sonarr.${var.traefik_domain}"
    }

    nfs_mounts = {
      media     = "${var.nfs_server}:${var.nfs_media_share}"
      downloads = "${var.nfs_server}:${var.nfs_downloads_share}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.sonarr.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.sonarr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.sonarr.metadata[0].name} -l app=sonarr -f"
    }
  }

  sensitive = true
}
