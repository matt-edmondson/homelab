# =============================================================================
# Bazarr — Subtitle Management
# =============================================================================
# Integrates with Sonarr and Radarr to download and manage subtitles.
# Longhorn PVC for config/DB, NFS PVC for media (writes .srt files alongside
# video files on the NAS).
# =============================================================================

# Variables
variable "bazarr_enabled" {
  description = "Enable Bazarr deployment"
  type        = bool
  default     = true
}

variable "bazarr_storage_size" {
  description = "Storage size for Bazarr config/database"
  type        = string
  default     = "1Gi"
}

variable "bazarr_memory_request" {
  description = "Memory request for Bazarr container"
  type        = string
  default     = "128Mi"
}

variable "bazarr_memory_limit" {
  description = "Memory limit for Bazarr container"
  type        = string
  default     = "1Gi"
}

variable "bazarr_cpu_request" {
  description = "CPU request for Bazarr container"
  type        = string
  default     = "50m"
}

variable "bazarr_cpu_limit" {
  description = "CPU limit for Bazarr container"
  type        = string
  default     = "500m"
}

variable "bazarr_image_tag" {
  description = "Bazarr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "bazarr" {
  count = var.bazarr_enabled ? 1 : 0

  metadata {
    name = "bazarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "bazarr"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "bazarr_config" {
  count = var.bazarr_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "bazarr-config"
    namespace = kubernetes_namespace.bazarr[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.bazarr_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Media (static PV, read-write for subtitle files)
resource "kubernetes_persistent_volume" "bazarr_media" {
  count = var.bazarr_enabled ? 1 : 0

  metadata {
    name   = "bazarr-media-pv"
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

resource "kubernetes_persistent_volume_claim" "bazarr_media" {
  count = var.bazarr_enabled ? 1 : 0

  metadata {
    name      = "bazarr-media"
    namespace = kubernetes_namespace.bazarr[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.bazarr_media[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "bazarr" {
  count = var.bazarr_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.bazarr_config,
    kubernetes_persistent_volume_claim.bazarr_media,
    helm_release.longhorn
  ]

  metadata {
    name      = "bazarr"
    namespace = kubernetes_namespace.bazarr[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "bazarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "bazarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "bazarr"
        })
      }

      spec {
        container {
          name  = "bazarr"
          image = "linuxserver/bazarr:${var.bazarr_image_tag}"

          port {
            container_port = 6767
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
            name       = "bazarr-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "media"
            mount_path = "/media"
          }

          resources {
            requests = {
              memory = var.bazarr_memory_request
              cpu    = var.bazarr_cpu_request
            }
            limits = {
              memory = var.bazarr_memory_limit
              cpu    = var.bazarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = 6767
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 6767
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "bazarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.bazarr_config[0].metadata[0].name
          }
        }

        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.bazarr_media[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "bazarr" {
  count = var.bazarr_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.bazarr
  ]

  metadata {
    name      = "bazarr-service"
    namespace = kubernetes_namespace.bazarr[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "bazarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "bazarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 6767
    }
  }
}

# Outputs
output "bazarr_info" {
  description = "Bazarr subtitle management information"
  value = var.bazarr_enabled ? {
    namespace    = kubernetes_namespace.bazarr[0].metadata[0].name
    service_name = kubernetes_service.bazarr[0].metadata[0].name
    storage_size = var.bazarr_storage_size

    access = {
      web_ui = "https://bazarr.${var.traefik_domain}"
    }

    nfs_mounts = {
      media = "${var.nfs_server}:${var.nfs_media_share}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.bazarr[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.bazarr[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.bazarr[0].metadata[0].name} -l app=bazarr -f"
    }
  } : null

  sensitive = true
}
