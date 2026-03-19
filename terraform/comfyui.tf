# =============================================================================
# ComfyUI — Stable Diffusion Image Generation
# =============================================================================
# Node-based Stable Diffusion workflow builder with GPU acceleration.
# Longhorn PVC for config, NFS mount for models and generated outputs
# under /volume2/media/ai-models/comfyui/.
# =============================================================================

# Variables
variable "comfyui_enabled" {
  description = "Enable ComfyUI deployment"
  type        = bool
  default     = true
}

variable "comfyui_config_storage_size" {
  description = "Storage size for ComfyUI config"
  type        = string
  default     = "1Gi"
}

variable "comfyui_memory_request" {
  description = "Memory request for ComfyUI container"
  type        = string
  default     = "512Mi"
}

variable "comfyui_memory_limit" {
  description = "Memory limit for ComfyUI container"
  type        = string
  default     = "2Gi"
}

variable "comfyui_cpu_request" {
  description = "CPU request for ComfyUI container"
  type        = string
  default     = "500m"
}

variable "comfyui_cpu_limit" {
  description = "CPU limit for ComfyUI container"
  type        = string
  default     = "4000m"
}

variable "comfyui_image_tag" {
  description = "ComfyUI container image tag"
  type        = string
  default     = "latest"
}

variable "comfyui_gpu_enabled" {
  description = "Request GPU resource for ComfyUI (requires NVIDIA device plugin)"
  type        = bool
  default     = false
}

# Namespace
resource "kubernetes_namespace" "comfyui" {
  count = var.comfyui_enabled ? 1 : 0

  metadata {
    name = "comfyui"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "comfyui"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "comfyui_config" {
  count = var.comfyui_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "comfyui-config"
    namespace = kubernetes_namespace.comfyui[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.comfyui_config_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Models (static PV, subpath of media share)
resource "kubernetes_persistent_volume" "comfyui_models" {
  count = var.comfyui_enabled ? 1 : 0

  metadata {
    name   = "comfyui-models-pv"
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
        path   = "${var.nfs_media_share}/ai-models/comfyui"
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "comfyui_models" {
  count = var.comfyui_enabled ? 1 : 0

  metadata {
    name      = "comfyui-models"
    namespace = kubernetes_namespace.comfyui[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.comfyui_models[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "comfyui" {
  count = var.comfyui_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.comfyui_config,
    kubernetes_persistent_volume_claim.comfyui_models,
    helm_release.longhorn
  ]

  metadata {
    name      = "comfyui"
    namespace = kubernetes_namespace.comfyui[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "comfyui"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "comfyui"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "comfyui"
        })
      }

      spec {
        container {
          name  = "comfyui"
          image = "yanwk/comfyui-boot:${var.comfyui_image_tag}"

          port {
            container_port = 8188
            name           = "http"
          }

          volume_mount {
            name       = "comfyui-config"
            mount_path = "/home/runner"
          }

          volume_mount {
            name       = "models"
            sub_path   = "models"
            mount_path = "/home/runner/ComfyUI/models"
          }

          volume_mount {
            name       = "models"
            sub_path   = "output"
            mount_path = "/home/runner/ComfyUI/output"
          }

          resources {
            requests = {
              memory = var.comfyui_memory_request
              cpu    = var.comfyui_cpu_request
            }
            limits = merge(
              {
                memory = var.comfyui_memory_limit
                cpu    = var.comfyui_cpu_limit
              },
              var.comfyui_gpu_enabled ? { "nvidia.com/gpu" = "1" } : {}
            )
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 8188
            }
            initial_delay_seconds = 120
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 8188
            }
            initial_delay_seconds = 60
            period_seconds        = 10
          }
        }

        volume {
          name = "comfyui-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.comfyui_config[0].metadata[0].name
          }
        }

        volume {
          name = "models"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.comfyui_models[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "comfyui" {
  count = var.comfyui_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.comfyui
  ]

  metadata {
    name      = "comfyui-service"
    namespace = kubernetes_namespace.comfyui[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "comfyui"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "comfyui"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8188
    }
  }
}

# Outputs
output "comfyui_info" {
  description = "ComfyUI image generation information"
  value = var.comfyui_enabled ? {
    namespace    = kubernetes_namespace.comfyui[0].metadata[0].name
    service_name = kubernetes_service.comfyui[0].metadata[0].name
    config_size  = var.comfyui_config_storage_size
    gpu_enabled  = var.comfyui_gpu_enabled

    access = {
      web_ui = "https://comfyui.${var.traefik_domain}"
    }

    nfs_mounts = {
      models = "${var.nfs_server}:${var.nfs_media_share}/ai-models/comfyui"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.comfyui[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.comfyui[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.comfyui[0].metadata[0].name} -l app=comfyui -f"
    }
  } : null

  sensitive = true
}
