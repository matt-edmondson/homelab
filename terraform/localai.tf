# =============================================================================
# LocalAI — Full-Stack Local AI Inference
# =============================================================================
# OpenAI-compatible API for LLM, embeddings, image generation, and audio.
# go-skynet/local-ai Helm chart with chart persistence disabled.
# Two NFS mounts: /models (weights + YAML configs) and /tmp/generated (output).
# =============================================================================

# Variables
variable "localai_enabled" {
  description = "Enable LocalAI deployment"
  type        = bool
  default     = true
}

variable "localai_image_tag" {
  description = "LocalAI container image tag (e.g. master-cublas-cuda12-ffmpeg for GPU+audio, master-cpu for CPU-only)"
  type        = string
  default     = "master-cublas-cuda12-ffmpeg"
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
  default     = false
}

variable "localai_gpu_min_vram_gb" {
  description = "Minimum GPU VRAM in GB required for LocalAI (0 = no VRAM constraint)"
  type        = number
  default     = 12
}

variable "localai_chart_version" {
  description = "go-skynet/local-ai Helm chart version (empty = latest)"
  type        = string
  default     = ""
}

locals {
  localai_resource_limits = merge(
    {
      memory = var.localai_memory_limit
      cpu    = var.localai_cpu_limit
    },
    var.localai_gpu_enabled ? { "nvidia.com/gpu" = "1" } : {}
  )
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

# Persistent Volume — NFS Models (weights + YAML model configs)
resource "kubernetes_persistent_volume" "localai_models" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name   = "localai-models-pv"
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
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Persistent Volume — NFS Output (generated images, audio, etc.)
resource "kubernetes_persistent_volume" "localai_output" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name   = "localai-output-pv"
    labels = var.common_labels
  }

  spec {
    capacity = {
      storage = "100Gi"
    }
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
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
}

# Helm Release — LocalAI
resource "helm_release" "localai" {
  count = var.localai_enabled ? 1 : 0

  name       = "localai"
  repository = "https://go-skynet.github.io/helm-charts/"
  chart      = "local-ai"
  version    = var.localai_chart_version != "" ? var.localai_chart_version : null
  namespace  = kubernetes_namespace.localai[0].metadata[0].name

  timeout = 600
  wait    = true

  values = [
    yamlencode({
      fullnameOverride = "localai"
      replicaCount     = 1

      image = {
        tag = var.localai_image_tag
      }

      # Disable chart-managed persistence; NFS PVCs injected via extraVolumes
      persistence = {
        models = { enabled = false }
        output = { enabled = false }
      }

      resources = {
        requests = {
          memory = var.localai_memory_request
          cpu    = var.localai_cpu_request
        }
        limits = local.localai_resource_limits
      }

      nodeSelector = var.localai_gpu_enabled ? merge(
        { "nvidia.com/gpu.present" = "true" },
        var.localai_gpu_min_vram_gb > 0 ? { "gpu-vram-${var.localai_gpu_min_vram_gb}gb" = "true" } : {}
      ) : {}

      extraVolumes = [
        {
          name = "localai-models"
          persistentVolumeClaim = {
            claimName = kubernetes_persistent_volume_claim.localai_models[0].metadata[0].name
          }
        },
        {
          name = "localai-output"
          persistentVolumeClaim = {
            claimName = kubernetes_persistent_volume_claim.localai_output[0].metadata[0].name
          }
        },
      ]

      extraVolumeMounts = [
        {
          name      = "localai-models"
          mountPath = "/models"
        },
        {
          name      = "localai-output"
          mountPath = "/tmp/generated"
        },
      ]
    })
  ]

  depends_on = [
    kubernetes_namespace.localai,
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_output,
  ]
}

# Output
output "localai_info" {
  description = "LocalAI inference information"
  value = var.localai_enabled ? {
    namespace   = kubernetes_namespace.localai[0].metadata[0].name
    chart       = "go-skynet/local-ai"
    gpu_enabled = var.localai_gpu_enabled

    access = {
      web_ui      = "https://localai.${var.traefik_domain}"
      local_ui    = "https://localai.local.${var.traefik_domain}"
      cluster_api = "localai.${kubernetes_namespace.localai[0].metadata[0].name}.svc.cluster.local:80"
    }

    nfs_mounts = {
      models = "${var.nfs_server}:${var.nfs_media_share}/ai-models/localai/models"
      output = "${var.nfs_server}:${var.nfs_media_share}/ai-models/localai/output"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.localai[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.localai[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.localai[0].metadata[0].name} -l app.kubernetes.io/name=localai -f"
      api_models = "kubectl exec -n ${kubernetes_namespace.localai[0].metadata[0].name} deploy/localai -- curl -s http://localhost:8080/v1/models"
    }
  } : null

  sensitive = true
}
