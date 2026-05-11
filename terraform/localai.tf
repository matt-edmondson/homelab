# =============================================================================
# LocalAI — Full-Stack Local AI Inference
# =============================================================================
# OpenAI-compatible API for LLM, embeddings, image generation, and audio.
# Raw Kubernetes deployment (no Helm) with five NFS mounts:
#   /models         — model weights + YAML configs
#   /backends       — LocalAI backend binaries
#   /configuration  — runtime settings
#   /data           — assets, collections, skills
#   /tmp/generated  — generated output (images, audio)
# =============================================================================

# Variables
variable "localai_enabled" {
  description = "Enable LocalAI deployment"
  type        = bool
  default     = true
}

variable "localai_image_tag" {
  description = "LocalAI container image tag (e.g. latest-gpu-nvidia-cuda-13 for GPU, latest-cpu for CPU-only)"
  type        = string
  default     = "latest-gpu-nvidia-cuda-13"
}

variable "localai_memory_request" {
  description = "Memory request for LocalAI container"
  type        = string
  default     = "4Gi"
}

variable "localai_memory_limit" {
  description = "Memory limit for LocalAI container"
  type        = string
  default     = "24Gi"
}

variable "localai_cpu_request" {
  description = "CPU request for LocalAI container"
  type        = string
  default     = "1000m"
}

variable "localai_cpu_limit" {
  description = "CPU limit for LocalAI container"
  type        = string
  default     = "4000m"
}

variable "localai_gpu_enabled" {
  description = "Request GPU resource for LocalAI (requires NVIDIA device plugin)"
  type        = bool
  default     = true
}

variable "localai_gpu_min_vram_gb" {
  description = "Minimum GPU VRAM in GB required for LocalAI (0 = no VRAM constraint)"
  type        = number
  default     = 12
}

variable "localai_p2p_token" {
  description = "Shared P2P token for LocalAI swarm (controller + workers)"
  type        = string
  sensitive   = true
}

# Namespace
resource "kubernetes_namespace" "localai" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name = "localai"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai"
    })
  }
}

# P2P Swarm Secret
resource "kubernetes_secret" "localai_p2p" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-p2p"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    token = var.localai_p2p_token
  }

  type = "Opaque"
}

# =============================================================================
# NFS Persistent Volumes
# =============================================================================

resource "kubernetes_persistent_volume" "localai_models" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name   = "localai-models-pv"
    labels = var.common_labels
  }

  spec {
    capacity                         = { storage = "1Ti" }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"
    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = "${var.nfs_media_share}/ai-models/localai/models"
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "localai_models" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-models"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.localai_models[0].metadata[0].name
    resources { requests = { storage = "1Ti" } }
  }
}

resource "kubernetes_persistent_volume" "localai_backends" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name   = "localai-backends-pv"
    labels = var.common_labels
  }

  spec {
    capacity                         = { storage = "50Gi" }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"
    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = "${var.nfs_media_share}/ai-models/localai/backends"
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "localai_backends" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-backends"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.localai_backends[0].metadata[0].name
    resources { requests = { storage = "50Gi" } }
  }
}

resource "kubernetes_persistent_volume" "localai_configuration" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name   = "localai-configuration-pv"
    labels = var.common_labels
  }

  spec {
    capacity                         = { storage = "1Gi" }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"
    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = "${var.nfs_media_share}/ai-models/localai/configuration"
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "localai_configuration" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-configuration"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.localai_configuration[0].metadata[0].name
    resources { requests = { storage = "1Gi" } }
  }
}

resource "kubernetes_persistent_volume" "localai_data" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name   = "localai-data-pv"
    labels = var.common_labels
  }

  spec {
    capacity                         = { storage = "10Gi" }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"
    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = "${var.nfs_media_share}/ai-models/localai/data"
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "localai_data" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-data"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.localai_data[0].metadata[0].name
    resources { requests = { storage = "10Gi" } }
  }
}

resource "kubernetes_persistent_volume" "localai_output" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name   = "localai-output-pv"
    labels = var.common_labels
  }

  spec {
    capacity                         = { storage = "100Gi" }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"
    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = "${var.nfs_media_share}/ai-models/localai/output"
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "localai_output" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-output"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.localai_output[0].metadata[0].name
    resources { requests = { storage = "100Gi" } }
  }
}

# =============================================================================
# Deployment
# =============================================================================

resource "kubernetes_deployment" "localai" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    kubernetes_persistent_volume_claim.localai_data,
    kubernetes_persistent_volume_claim.localai_output,
    helm_release.longhorn,
  ]

  metadata {
    name      = "localai"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "localai" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai" })
      }

      spec {
        container {
          name  = "localai"
          image = "localai/localai:${var.localai_image_tag}"

          port {
            container_port = 8080
            name           = "http"
          }

          resources {
            requests = {
              memory = var.localai_memory_request
              cpu    = var.localai_cpu_request
            }
            limits = merge(
              {
                memory = var.localai_memory_limit
                cpu    = var.localai_cpu_limit
              },
              var.localai_gpu_enabled ? { "nvidia.com/gpu" = "1" } : {}
            )
          }

          volume_mount {
            name       = "models"
            mount_path = "/models"
          }

          volume_mount {
            name       = "backends"
            mount_path = "/backends"
          }

          volume_mount {
            name       = "configuration"
            mount_path = "/configuration"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          volume_mount {
            name       = "output"
            mount_path = "/tmp/generated"
          }

          liveness_probe {
            http_get {
              path = "/readyz"
              port = 8080
            }
            initial_delay_seconds = 60
            period_seconds        = 15
            failure_threshold     = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
        }

        node_selector = var.localai_gpu_enabled ? merge(
          { "nvidia.com/gpu.present" = "true" },
          var.localai_gpu_min_vram_gb > 0 ? { "gpu-vram-${var.localai_gpu_min_vram_gb}gb" = "true" } : {}
        ) : {}

        volume {
          name = "models"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_models[0].metadata[0].name
          }
        }

        volume {
          name = "backends"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_backends[0].metadata[0].name
          }
        }

        volume {
          name = "configuration"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_configuration[0].metadata[0].name
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_data[0].metadata[0].name
          }
        }

        volume {
          name = "output"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_output[0].metadata[0].name
          }
        }
      }
    }
  }
}

# =============================================================================
# Service
# =============================================================================

resource "kubernetes_service" "localai" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.localai]

  metadata {
    name      = "localai"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai"
    })
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "localai" }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
  }
}

# =============================================================================
# Output
# =============================================================================

output "localai_info" {
  description = "LocalAI inference information"
  value = var.localai_enabled ? {
    namespace   = kubernetes_namespace.localai[0].metadata[0].name
    gpu_enabled = var.localai_gpu_enabled

    access = {
      web_ui      = "https://localai.${var.traefik_domain}"
      local_ui    = "https://localai.local.${var.traefik_domain}"
      cluster_api = "localai.${kubernetes_namespace.localai[0].metadata[0].name}.svc.cluster.local:80"
    }

    nfs_mounts = {
      models        = "${var.nfs_server}:${var.nfs_media_share}/ai-models/localai/models"
      backends      = "${var.nfs_server}:${var.nfs_media_share}/ai-models/localai/backends"
      configuration = "${var.nfs_server}:${var.nfs_media_share}/ai-models/localai/configuration"
      data          = "${var.nfs_server}:${var.nfs_media_share}/ai-models/localai/data"
      output        = "${var.nfs_server}:${var.nfs_media_share}/ai-models/localai/output"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.localai[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.localai[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.localai[0].metadata[0].name} -l app=localai -f"
      api_models = "kubectl exec -n ${kubernetes_namespace.localai[0].metadata[0].name} deploy/localai -- curl -s http://localhost:8080/v1/models"
    }
  } : null

  sensitive = true
}
