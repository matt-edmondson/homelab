# =============================================================================
# Ollama — Local LLM Inference
# =============================================================================
# Runs large language models locally with GPU acceleration. API endpoint
# accessible by other services (n8n, custom apps) via cluster DNS.
# Longhorn PVC for config, NFS mount for model storage under /volume2/media.
# =============================================================================

# Variables
variable "ollama_enabled" {
  description = "Enable Ollama deployment"
  type        = bool
  default     = true
}

variable "ollama_config_storage_size" {
  description = "Storage size for Ollama config"
  type        = string
  default     = "1Gi"
}

variable "ollama_memory_request" {
  description = "Memory request for Ollama container"
  type        = string
  default     = "512Mi"
}

variable "ollama_memory_limit" {
  description = "Memory limit for Ollama container"
  type        = string
  default     = "2Gi"
}

variable "ollama_cpu_request" {
  description = "CPU request for Ollama container"
  type        = string
  default     = "500m"
}

variable "ollama_cpu_limit" {
  description = "CPU limit for Ollama container"
  type        = string
  default     = "4000m"
}

variable "ollama_image_tag" {
  description = "Ollama container image tag"
  type        = string
  default     = "latest"
}

variable "ollama_gpu_enabled" {
  description = "Request GPU resource for Ollama (requires NVIDIA device plugin)"
  type        = bool
  default     = false
}

variable "ollama_gpu_min_vram_gb" {
  description = "Minimum GPU VRAM in GB required for Ollama (0 = no VRAM constraint)"
  type        = number
  default     = 12
}

# Namespace
resource "kubernetes_namespace" "ollama" {
  count = var.ollama_enabled ? 1 : 0

  metadata {
    name = "ollama"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "ollama"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "ollama_config" {
  count = var.ollama_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "ollama-config"
    namespace = kubernetes_namespace.ollama[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.ollama_config_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Models (static PV, subpath of media share)
resource "kubernetes_persistent_volume" "ollama_models" {
  count = var.ollama_enabled ? 1 : 0

  metadata {
    name   = "ollama-models-pv"
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
        path   = "${var.nfs_media_share}/ai-models/ollama"
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "ollama_models" {
  count = var.ollama_enabled ? 1 : 0

  metadata {
    name      = "ollama-models"
    namespace = kubernetes_namespace.ollama[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.ollama_models[0].metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "ollama" {
  count = var.ollama_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.ollama_config,
    kubernetes_persistent_volume_claim.ollama_models,
    helm_release.longhorn
  ]

  metadata {
    name      = "ollama"
    namespace = kubernetes_namespace.ollama[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "ollama"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "ollama"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "ollama"
        })
      }

      spec {
        container {
          name  = "ollama"
          image = "ollama/ollama:${var.ollama_image_tag}"

          port {
            container_port = 11434
            name           = "http"
          }

          env {
            name  = "OLLAMA_HOST"
            value = "0.0.0.0"
          }

          volume_mount {
            name       = "ollama-config"
            mount_path = "/root/.ollama"
          }

          volume_mount {
            name       = "models"
            mount_path = "/root/.ollama/models"
          }

          resources {
            requests = {
              memory = var.ollama_memory_request
              cpu    = var.ollama_cpu_request
            }
            limits = merge(
              {
                memory = var.ollama_memory_limit
                cpu    = var.ollama_cpu_limit
              },
              var.ollama_gpu_enabled ? { "nvidia.com/gpu" = "1" } : {}
            )
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 11434
            }
            initial_delay_seconds = 30
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 11434
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }

        node_selector = var.ollama_gpu_enabled ? merge(
          { "nvidia.com/gpu.present" = "true" },
          var.ollama_gpu_min_vram_gb > 0 ? { "gpu-vram-${var.ollama_gpu_min_vram_gb}gb" = "true" } : {}
        ) : {}

        volume {
          name = "ollama-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_config[0].metadata[0].name
          }
        }

        volume {
          name = "models"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_models[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "ollama" {
  count = var.ollama_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.ollama
  ]

  metadata {
    name      = "ollama-service"
    namespace = kubernetes_namespace.ollama[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "ollama"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "ollama"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 11434
    }
  }
}

# Outputs
output "ollama_info" {
  description = "Ollama LLM inference information"
  value = var.ollama_enabled ? {
    namespace    = kubernetes_namespace.ollama[0].metadata[0].name
    service_name = kubernetes_service.ollama[0].metadata[0].name
    config_size  = var.ollama_config_storage_size
    gpu_enabled  = var.ollama_gpu_enabled

    access = {
      web_ui      = "https://ollama.${var.traefik_domain}"
      cluster_api = "ollama-service.${kubernetes_namespace.ollama[0].metadata[0].name}.svc.cluster.local:80"
    }

    nfs_mounts = {
      models = "${var.nfs_server}:${var.nfs_media_share}/ai-models/ollama"
    }

    commands = {
      check_pods  = "kubectl get pods -n ${kubernetes_namespace.ollama[0].metadata[0].name}"
      check_pvc   = "kubectl get pvc -n ${kubernetes_namespace.ollama[0].metadata[0].name}"
      logs        = "kubectl logs -n ${kubernetes_namespace.ollama[0].metadata[0].name} -l app=ollama -f"
      pull_model  = "kubectl exec -n ${kubernetes_namespace.ollama[0].metadata[0].name} deploy/ollama -- ollama pull llama3.2"
      list_models = "kubectl exec -n ${kubernetes_namespace.ollama[0].metadata[0].name} deploy/ollama -- ollama list"
    }
  } : null

  sensitive = true
}
