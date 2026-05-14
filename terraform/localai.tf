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

variable "localai_image_version" {
  description = "LocalAI version tag (e.g. v4.2.4). Frontend and agent-worker use the plain tag (CPU build); workers append -gpu-nvidia-cuda-13. Note: -aio-cpu variants were dropped after v3.12.1, and -gpu-nvidia-cuda-13 variants skipped v4.2.1-3."
  type        = string
  default     = "v4.2.4"
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
  description = "Request GPU resource for LocalAI worker DaemonSet (requires NVIDIA device plugin)"
  type        = bool
  default     = true
}

variable "localai_gpu_min_vram_gb" {
  description = "Minimum GPU VRAM in GB required for LocalAI workers (0 = no VRAM constraint)"
  type        = number
  default     = 12
}

variable "localai_registration_token" {
  description = "Shared registration token: workers and agent-worker present this to the frontend at startup. Generate with: openssl rand -hex 32"
  type        = string
  sensitive   = true
  default     = ""
}

variable "localai_postgres_password" {
  description = "Password for the bundled LocalAI Postgres (used by the frontend for auth + agent-pool vector tables)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "localai_postgres_storage_size" {
  description = "Longhorn PVC size for the bundled LocalAI Postgres"
  type        = string
  default     = "20Gi"
}

variable "localai_nats_storage_size" {
  description = "Longhorn PVC size for NATS JetStream data"
  type        = string
  default     = "5Gi"
}

variable "localai_agent_pool_embedding_model" {
  description = "Embedding model name advertised via LOCALAI_AGENT_POOL_EMBEDDING_MODEL"
  type        = string
  default     = "granite-embedding-107m-multilingual"
}

# Migration: rename of the registration secret resource.
# The Kubernetes object name itself also changes (localai-p2p -> localai-registration),
# which terraform handles as destroy/create. The token value (the string) is identical.
moved {
  from = kubernetes_secret.localai_p2p
  to   = kubernetes_secret.localai_registration
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

# Registration token: workers and agent-worker present this to the frontend at startup.
resource "kubernetes_secret" "localai_registration" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-registration"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    token = var.localai_registration_token
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
    kubernetes_secret.localai_registration,
    kubernetes_secret.localai_postgres,
    kubernetes_deployment.localai_postgres,
    kubernetes_deployment.localai_nats,
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
          image = "localai/localai:${var.localai_image_version}"

          port {
            container_port = 8080
            name           = "http"
          }

          env {
            name  = "LOCALAI_DISTRIBUTED"
            value = "true"
          }

          env {
            name  = "LOCALAI_NATS_URL"
            value = "nats://localai-nats.localai.svc:4222"
          }

          env {
            name = "LOCALAI_REGISTRATION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_registration[0].metadata[0].name
                key  = "token"
              }
            }
          }

          env {
            name  = "LOCALAI_AGENT_POOL_EMBEDDING_MODEL"
            value = var.localai_agent_pool_embedding_model
          }

          env {
            name  = "LOCALAI_AGENT_POOL_VECTOR_ENGINE"
            value = "postgres"
          }

          env {
            name = "LOCALAI_AGENT_POOL_DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_postgres[0].metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          env {
            name  = "LOCALAI_AUTH"
            value = "true"
          }

          env {
            name = "LOCALAI_AUTH_DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_postgres[0].metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          env {
            name  = "GODEBUG"
            value = "netdns=go"
          }

          env {
            name  = "MODELS_PATH"
            value = "/models"
          }

          resources {
            requests = {
              memory = var.localai_memory_request
              cpu    = var.localai_cpu_request
            }
            limits = {
              memory = var.localai_memory_limit
              cpu    = var.localai_cpu_limit
            }
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

          volume_mount {
            name       = "ollama-blobs"
            mount_path = "/ollama-blobs"
            read_only  = true
          }

          volume_mount {
            name       = "comfyui-models"
            mount_path = "/comfyui-models"
            read_only  = true
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

        node_selector = {}

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

        volume {
          name = "ollama-blobs"
          nfs {
            server    = var.nfs_server
            path      = "${var.nfs_media_share}/ai-models/ollama/blobs"
            read_only = true
          }
        }

        volume {
          name = "comfyui-models"
          nfs {
            server    = var.nfs_server
            path      = "${var.nfs_media_share}/ai-models/comfyui/models"
            read_only = true
          }
        }
      }
    }
  }
}

locals {
  localai_worker_gpu_tiers = toset([
    for node in keys(var.gpu_nodes) : tostring(lookup(var.gpu_counts, node, 1))
  ])
}

# =============================================================================
# Worker DaemonSet — one GPU worker per GPU-count tier
# =============================================================================
# One DaemonSet per unique GPU count value (e.g. "1", "2"). Each DaemonSet
# targets nodes labelled gpu-count-exact-N and requests N GPUs, letting
# llama.cpp use all GPUs on the node for large-model inference.

resource "kubernetes_daemonset" "localai_worker" {
  for_each = var.localai_enabled && var.localai_gpu_enabled ? local.localai_worker_gpu_tiers : toset([])

  depends_on = [
    kubernetes_secret.localai_registration,
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    helm_release.longhorn,
    kubernetes_deployment.localai,
    kubernetes_deployment.localai_nats,
  ]

  metadata {
    name      = "localai-worker-${each.key}gpu"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-worker"
    })
  }

  spec {
    selector {
      match_labels = { app = "localai-worker-${each.key}gpu" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app  = "localai-worker-${each.key}gpu"
          role = "localai-worker"
        })
      }

      spec {
        container {
          name  = "localai-worker"
          image = "localai/localai:${var.localai_image_version}-gpu-nvidia-cuda-13"
          args  = ["worker"]

          # Downward API: node identity for advertise addrs
          env {
            name = "NODE_IP"
            value_from {
              field_ref {
                field_path = "status.hostIP"
              }
            }
          }

          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          # Registration with the LocalAI frontend.
          # The localai Service exposes port 80 -> targetPort 8080, so we hit :80 here.
          env {
            name  = "LOCALAI_REGISTER_TO"
            value = "http://localai.localai.svc:80"
          }

          env {
            name = "LOCALAI_REGISTRATION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_registration[0].metadata[0].name
                key  = "token"
              }
            }
          }

          env {
            name  = "LOCALAI_NATS_URL"
            value = "nats://localai-nats.localai.svc:4222"
          }

          # Worker serves gRPC backend on 50051 and HTTP file-transfer on 50050.
          env {
            name  = "LOCALAI_SERVE_ADDR"
            value = "0.0.0.0:50051"
          }

          env {
            name  = "LOCALAI_ADVERTISE_ADDR"
            value = "$(NODE_IP):50051"
          }

          env {
            name  = "LOCALAI_ADVERTISE_HTTP_ADDR"
            value = "$(NODE_IP):50050"
          }

          env {
            name  = "LOCALAI_NODE_NAME"
            value = "$(NODE_NAME)-${each.key}gpu"
          }

          env {
            name  = "LOCALAI_HEARTBEAT_INTERVAL"
            value = "10s"
          }

          # Image-baked HEALTHCHECK targets :8080/readyz which the worker
          # doesn't serve. Override to the file-transfer endpoint on 50050.
          env {
            name  = "HEALTHCHECK_ENDPOINT"
            value = "http://localhost:50050/readyz"
          }

          env {
            name  = "GODEBUG"
            value = "netdns=go"
          }

          env {
            name  = "MODELS_PATH"
            value = "/models"
          }

          resources {
            requests = {
              memory = var.localai_memory_request
              cpu    = var.localai_cpu_request
            }
            limits = {
              memory           = var.localai_memory_limit
              cpu              = var.localai_cpu_limit
              "nvidia.com/gpu" = each.key
            }
          }

          port {
            container_port = 50050
            host_port      = 50050
            protocol       = "TCP"
            name           = "http"
          }

          port {
            container_port = 50051
            host_port      = 50051
            protocol       = "TCP"
            name           = "grpc"
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 50050
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 6
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
            name       = "ollama-blobs"
            mount_path = "/ollama-blobs"
            read_only  = true
          }

          volume_mount {
            name       = "comfyui-models"
            mount_path = "/comfyui-models"
            read_only  = true
          }
        }

        node_selector = merge(
          { "gpu-count-exact-${each.key}" = "true" },
          var.localai_gpu_min_vram_gb > 0 ? { "gpu-vram-${var.localai_gpu_min_vram_gb}gb" = "true" } : {}
        )

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
          name = "ollama-blobs"
          nfs {
            server    = var.nfs_server
            path      = "${var.nfs_media_share}/ai-models/ollama/blobs"
            read_only = true
          }
        }

        volume {
          name = "comfyui-models"
          nfs {
            server    = var.nfs_server
            path      = "${var.nfs_media_share}/ai-models/comfyui/models"
            read_only = true
          }
        }
      }
    }
  }
}

# =============================================================================
# Agent Worker — NATS-driven agent chat / MCP / skills executor
# =============================================================================
# Stateless CPU worker that receives agent jobs from NATS, runs LLM calls
# back through the LocalAI API, and publishes results via NATS for SSE
# delivery. No HTTP server, no probes, no GPU, no Docker socket (HTTP/SSE
# MCPs only).

resource "kubernetes_deployment" "localai_agent_worker" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_secret.localai_registration,
    kubernetes_deployment.localai,
    kubernetes_deployment.localai_nats,
  ]

  metadata {
    name      = "localai-agent-worker"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-agent-worker"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "localai-agent-worker" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai-agent-worker" })
      }

      spec {
        container {
          name  = "localai-agent-worker"
          image = "localai/localai:${var.localai_image_version}"
          args  = ["agent-worker"]

          env {
            name  = "LOCALAI_NATS_URL"
            value = "nats://localai-nats.localai.svc:4222"
          }

          # The localai Service exposes port 80 -> targetPort 8080, so we hit :80 here.
          env {
            name  = "LOCALAI_REGISTER_TO"
            value = "http://localai.localai.svc:80"
          }

          env {
            name = "LOCALAI_REGISTRATION_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_registration[0].metadata[0].name
                key  = "token"
              }
            }
          }

          env {
            name  = "LOCALAI_NODE_NAME"
            value = "agent-worker"
          }

          env {
            name  = "GODEBUG"
            value = "netdns=go"
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
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
      check_pods  = "kubectl get pods -n ${kubernetes_namespace.localai[0].metadata[0].name}"
      check_pvc   = "kubectl get pvc -n ${kubernetes_namespace.localai[0].metadata[0].name}"
      logs        = "kubectl logs -n ${kubernetes_namespace.localai[0].metadata[0].name} -l app=localai -f"
      worker_logs = "kubectl logs -n ${kubernetes_namespace.localai[0].metadata[0].name} -l role=localai-worker -f"
      api_models  = "kubectl exec -n ${kubernetes_namespace.localai[0].metadata[0].name} deploy/localai -- curl -s http://localhost:8080/v1/models"
    }
  } : null

  sensitive = true
}
