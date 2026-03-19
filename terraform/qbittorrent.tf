# =============================================================================
# qBittorrent — BitTorrent Client with VPN Sidecar
# =============================================================================
# Migrated from VM 113. Runs all traffic through a gluetun VPN sidecar
# (PIA WireGuard). Web UI accessible via Traefik. Downloads go to NFS.
#
# Note: The plan mentions potential NFS performance issues with qBittorrent.
# A local Longhorn scratch PVC is included for active downloads, with
# completed files moved to NFS by qBittorrent's category/post-processing.
# =============================================================================

# Variables
variable "qbittorrent_enabled" {
  description = "Enable qBittorrent deployment"
  type        = bool
  default     = true
}

variable "qbittorrent_config_storage_size" {
  description = "Storage size for qBittorrent config"
  type        = string
  default     = "1Gi"
}

variable "qbittorrent_scratch_storage_size" {
  description = "Storage size for local scratch disk (active downloads)"
  type        = string
  default     = "100Gi"
}

variable "qbittorrent_memory_request" {
  description = "Memory request for qBittorrent container"
  type        = string
  default     = "512Mi"
}

variable "qbittorrent_memory_limit" {
  description = "Memory limit for qBittorrent container"
  type        = string
  default     = "2Gi"
}

variable "qbittorrent_cpu_request" {
  description = "CPU request for qBittorrent container"
  type        = string
  default     = "250m"
}

variable "qbittorrent_cpu_limit" {
  description = "CPU limit for qBittorrent container"
  type        = string
  default     = "2000m"
}

variable "qbittorrent_image_tag" {
  description = "qBittorrent container image tag"
  type        = string
  default     = "latest"
}

variable "gluetun_vpn_service_provider" {
  description = "VPN service provider for gluetun (e.g. private internet access)"
  type        = string
  default     = "private internet access"
}

variable "gluetun_vpn_type" {
  description = "VPN type: wireguard or openvpn"
  type        = string
  default     = "wireguard"
}

variable "gluetun_vpn_username" {
  description = "VPN username (for OpenVPN providers)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "gluetun_vpn_password" {
  description = "VPN password (for OpenVPN providers)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "gluetun_wireguard_private_key" {
  description = "WireGuard private key (for WireGuard providers)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "gluetun_server_regions" {
  description = "Comma-separated list of VPN server regions"
  type        = string
  default     = "AU Melbourne"
}

variable "gluetun_memory_request" {
  description = "Memory request for gluetun VPN sidecar"
  type        = string
  default     = "64Mi"
}

variable "gluetun_memory_limit" {
  description = "Memory limit for gluetun VPN sidecar"
  type        = string
  default     = "256Mi"
}

# Namespace
resource "kubernetes_namespace" "qbittorrent" {
  count = var.qbittorrent_enabled ? 1 : 0

  metadata {
    name = "qbittorrent"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qbittorrent"
    })
  }
}

# Secret — VPN credentials
resource "kubernetes_secret" "gluetun_vpn" {
  count = var.qbittorrent_enabled ? 1 : 0

  metadata {
    name      = "gluetun-vpn"
    namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    VPN_SERVICE_PROVIDER  = var.gluetun_vpn_service_provider
    VPN_TYPE              = var.gluetun_vpn_type
    OPENVPN_USER          = var.gluetun_vpn_username
    OPENVPN_PASSWORD      = var.gluetun_vpn_password
    WIREGUARD_PRIVATE_KEY = var.gluetun_wireguard_private_key
    SERVER_REGIONS        = var.gluetun_server_regions
  }

  type = "Opaque"
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "qbittorrent_config" {
  count = var.qbittorrent_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "qbittorrent-config"
    namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.qbittorrent_config_storage_size
      }
    }
  }
}

# Persistent Volume Claim — Scratch (Longhorn — active downloads)
resource "kubernetes_persistent_volume_claim" "qbittorrent_scratch" {
  count = var.qbittorrent_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "qbittorrent-scratch"
    namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.qbittorrent_scratch_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Downloads (static PV)
resource "kubernetes_persistent_volume" "qbittorrent_downloads" {
  count = var.qbittorrent_enabled ? 1 : 0

  metadata {
    name   = "qbittorrent-downloads-pv"
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

resource "kubernetes_persistent_volume_claim" "qbittorrent_downloads" {
  count = var.qbittorrent_enabled ? 1 : 0

  metadata {
    name      = "qbittorrent-downloads"
    namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-downloads"
    volume_name        = kubernetes_persistent_volume.qbittorrent_downloads[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment (qBittorrent + gluetun VPN sidecar)
resource "kubernetes_deployment" "qbittorrent" {
  count = var.qbittorrent_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.qbittorrent_config,
    kubernetes_persistent_volume_claim.qbittorrent_scratch,
    kubernetes_persistent_volume_claim.qbittorrent_downloads,
    kubernetes_secret.gluetun_vpn,
    helm_release.longhorn
  ]

  metadata {
    name      = "qbittorrent"
    namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qbittorrent"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "qbittorrent"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "qbittorrent"
        })
      }

      spec {
        # gluetun VPN sidecar — establishes the VPN tunnel
        # All containers in this pod share the network namespace
        container {
          name  = "gluetun"
          image = "qmcgaw/gluetun:latest"

          env_from {
            secret_ref {
              name = kubernetes_secret.gluetun_vpn[0].metadata[0].name
            }
          }

          # gluetun needs NET_ADMIN to create the VPN tunnel
          security_context {
            capabilities {
              add = ["NET_ADMIN"]
            }
          }

          # Expose qBittorrent web UI port through gluetun
          port {
            container_port = 8080
            name           = "webui"
          }

          resources {
            requests = {
              memory = var.gluetun_memory_request
              cpu    = "50m"
            }
            limits = {
              memory = var.gluetun_memory_limit
              cpu    = "500m"
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 9999 # gluetun health check port
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }
        }

        # qBittorrent — uses gluetun's network namespace
        container {
          name  = "qbittorrent"
          image = "linuxserver/qbittorrent:${var.qbittorrent_image_tag}"

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

          env {
            name  = "WEBUI_PORT"
            value = "8080"
          }

          volume_mount {
            name       = "qbittorrent-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "scratch"
            mount_path = "/scratch"
          }

          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }

          resources {
            requests = {
              memory = var.qbittorrent_memory_request
              cpu    = var.qbittorrent_cpu_request
            }
            limits = {
              memory = var.qbittorrent_memory_limit
              cpu    = var.qbittorrent_cpu_limit
            }
          }
        }

        volume {
          name = "qbittorrent-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.qbittorrent_config[0].metadata[0].name
          }
        }

        volume {
          name = "scratch"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.qbittorrent_scratch[0].metadata[0].name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.qbittorrent_downloads[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service (points to gluetun's exposed port since it owns the network namespace)
resource "kubernetes_service" "qbittorrent" {
  count = var.qbittorrent_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.qbittorrent
  ]

  metadata {
    name      = "qbittorrent-service"
    namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qbittorrent"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "qbittorrent"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
  }
}

# Outputs
output "qbittorrent_info" {
  description = "qBittorrent torrent client information"
  value = var.qbittorrent_enabled ? {
    namespace    = kubernetes_namespace.qbittorrent[0].metadata[0].name
    service_name = kubernetes_service.qbittorrent[0].metadata[0].name
    config_size  = var.qbittorrent_config_storage_size
    scratch_size = var.qbittorrent_scratch_storage_size
    vpn_provider = var.gluetun_vpn_service_provider
    vpn_type     = var.gluetun_vpn_type
    vpn_regions  = var.gluetun_server_regions

    access = {
      web_ui = "https://qbit.${var.traefik_domain}"
    }

    nfs_mounts = {
      downloads = "${var.nfs_server}:${var.nfs_downloads_share}"
    }

    commands = {
      check_pods   = "kubectl get pods -n ${kubernetes_namespace.qbittorrent[0].metadata[0].name}"
      check_pvc    = "kubectl get pvc -n ${kubernetes_namespace.qbittorrent[0].metadata[0].name}"
      logs_qbit    = "kubectl logs -n ${kubernetes_namespace.qbittorrent[0].metadata[0].name} -l app=qbittorrent -c qbittorrent -f"
      logs_vpn     = "kubectl logs -n ${kubernetes_namespace.qbittorrent[0].metadata[0].name} -l app=qbittorrent -c gluetun -f"
      check_vpn_ip = "kubectl exec -n ${kubernetes_namespace.qbittorrent[0].metadata[0].name} deploy/qbittorrent -c gluetun -- wget -qO- ifconfig.me"
    }
  } : null

  sensitive = true
}
