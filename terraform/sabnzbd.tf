# =============================================================================
# SABnzbd — Usenet Download Client
# =============================================================================
# Usenet downloader used by Sonarr/Radarr as a download client.
# Longhorn PVC for config, NFS PVC for downloads.
# Configure Usenet servers via the web UI after deployment.
# =============================================================================

# Variables
variable "sabnzbd_enabled" {
  description = "Enable SABnzbd deployment"
  type        = bool
  default     = true
}

variable "sabnzbd_storage_size" {
  description = "Storage size for SABnzbd config"
  type        = string
  default     = "1Gi"
}

variable "sabnzbd_memory_request" {
  description = "Memory request for SABnzbd container"
  type        = string
  default     = "256Mi"
}

variable "sabnzbd_memory_limit" {
  description = "Memory limit for SABnzbd container"
  type        = string
  default     = "512Mi"
}

variable "sabnzbd_cpu_request" {
  description = "CPU request for SABnzbd container"
  type        = string
  default     = "100m"
}

variable "sabnzbd_cpu_limit" {
  description = "CPU limit for SABnzbd container"
  type        = string
  default     = "1000m"
}

variable "sabnzbd_image_tag" {
  description = "SABnzbd container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "sabnzbd" {
  count = var.sabnzbd_enabled ? 1 : 0

  metadata {
    name = "sabnzbd"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sabnzbd"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "sabnzbd_config" {
  count = var.sabnzbd_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "sabnzbd-config"
    namespace = kubernetes_namespace.sabnzbd[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.sabnzbd_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Downloads (static PV)
resource "kubernetes_persistent_volume" "sabnzbd_downloads" {
  count = var.sabnzbd_enabled ? 1 : 0

  metadata {
    name   = "sabnzbd-downloads-pv"
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

resource "kubernetes_persistent_volume_claim" "sabnzbd_downloads" {
  count = var.sabnzbd_enabled ? 1 : 0

  metadata {
    name      = "sabnzbd-downloads"
    namespace = kubernetes_namespace.sabnzbd[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-downloads"
    volume_name        = kubernetes_persistent_volume.sabnzbd_downloads[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "sabnzbd" {
  count = var.sabnzbd_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.sabnzbd_config,
    kubernetes_persistent_volume_claim.sabnzbd_downloads,
    helm_release.longhorn
  ]

  metadata {
    name      = "sabnzbd"
    namespace = kubernetes_namespace.sabnzbd[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sabnzbd"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "sabnzbd"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "sabnzbd"
        })
      }

      spec {
        container {
          name  = "sabnzbd"
          image = "linuxserver/sabnzbd:${var.sabnzbd_image_tag}"

          port {
            container_port = 8080
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
            name       = "sabnzbd-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }

          resources {
            requests = {
              memory = var.sabnzbd_memory_request
              cpu    = var.sabnzbd_cpu_request
            }
            limits = {
              memory = var.sabnzbd_memory_limit
              cpu    = var.sabnzbd_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/api?mode=version"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/api?mode=version"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "sabnzbd-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sabnzbd_config[0].metadata[0].name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sabnzbd_downloads[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "sabnzbd" {
  count = var.sabnzbd_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.sabnzbd
  ]

  metadata {
    name      = "sabnzbd-service"
    namespace = kubernetes_namespace.sabnzbd[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sabnzbd"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "sabnzbd"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
  }
}

# Outputs
output "sabnzbd_info" {
  description = "SABnzbd Usenet download client information"
  value = var.sabnzbd_enabled ? {
    namespace    = kubernetes_namespace.sabnzbd[0].metadata[0].name
    service_name = kubernetes_service.sabnzbd[0].metadata[0].name
    config_size  = var.sabnzbd_storage_size

    access = {
      web_ui = "https://sabnzbd.${var.traefik_domain}"
    }

    nfs_mounts = {
      downloads = "${var.nfs_server}:${var.nfs_downloads_share}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.sabnzbd[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.sabnzbd[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.sabnzbd[0].metadata[0].name} -l app=sabnzbd -f"
    }
  } : null

  sensitive = true
}
