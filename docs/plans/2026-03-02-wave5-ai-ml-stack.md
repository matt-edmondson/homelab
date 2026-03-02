# Wave 5: AI/ML Stack Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy NVIDIA device plugin, Ollama (LLM inference), Qdrant (vector DB), ChromaDB (vector DB), and ComfyUI (image generation) with GPU passthrough support.

**Architecture:** Each service follows the established one-file-per-service Terraform pattern. GPU services (Ollama, ComfyUI) use `nodeSelector` to schedule on the GPU node. NVIDIA device plugin runs as a DaemonSet via Helm to expose `nvidia.com/gpu` resources. Ollama and ComfyUI mount NFS for model storage under `/volume2/media/ai-models/`. All 4 user-facing services get Traefik IngressRoutes with OAuth + CrowdSec + rate-limit middleware.

**Tech Stack:** Terraform (Kubernetes provider), Longhorn StorageClass, NFS media mount, Traefik IngressRoute CRDs, Azure DNS, NVIDIA device plugin Helm chart

---

## Task 1: Create `terraform/nvidia.tf` — NVIDIA Device Plugin

**Files:**
- Create: `terraform/nvidia.tf`

**Step 1: Write the NVIDIA device plugin Terraform file**

Reference `terraform/nfs.tf` for the Helm chart pattern and `terraform/common.tf` for provider/variable conventions.

```hcl
# =============================================================================
# NVIDIA Device Plugin — GPU Resource Scheduling
# =============================================================================
# Deploys the NVIDIA device plugin as a DaemonSet via Helm. This detects GPUs
# on K8s nodes and exposes them as schedulable `nvidia.com/gpu` resources.
#
# Prerequisites (manual, not Terraform-managed):
#   1. Enable IOMMU on Proxmox host: intel_iommu=on iommu=pt
#   2. Blacklist nouveau: /etc/modprobe.d/blacklist.conf
#   3. Configure VFIO for RTX 2060 PCI passthrough
#   4. Pass GPU to K8s node VM via Proxmox UI
#   5. Install nvidia-driver + nvidia-container-toolkit in guest VM
# =============================================================================

# Variables
variable "nvidia_device_plugin_chart_version" {
  description = "NVIDIA device plugin Helm chart version"
  type        = string
  default     = "0.17.0"
}

variable "nvidia_device_plugin_enabled" {
  description = "Enable NVIDIA device plugin (set to true after GPU passthrough is configured)"
  type        = bool
  default     = false
}

# Helm Release — NVIDIA Device Plugin
resource "helm_release" "nvidia_device_plugin" {
  count = var.nvidia_device_plugin_enabled ? 1 : 0

  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.nvidia_device_plugin_chart_version
  namespace  = "kube-system"

  values = [
    yamlencode({
      compatWithCPUManager = false
      nodeSelector = {
        "nvidia.com/gpu.present" = "true"
      }
    })
  ]

  timeout = 300
  wait    = true
}

# Outputs
output "nvidia_device_plugin_info" {
  description = "NVIDIA device plugin information"
  value = {
    enabled       = var.nvidia_device_plugin_enabled
    chart_version = var.nvidia_device_plugin_chart_version

    prerequisites = {
      step_1 = "Enable IOMMU: add 'intel_iommu=on iommu=pt' to Proxmox host kernel cmdline"
      step_2 = "Blacklist nouveau: echo 'blacklist nouveau' >> /etc/modprobe.d/blacklist.conf && update-initramfs -u"
      step_3 = "Configure VFIO: bind RTX 2060 PCI IDs to vfio-pci driver"
      step_4 = "Pass GPU to K8s node VM via Proxmox UI"
      step_5 = "Install nvidia-driver + nvidia-container-toolkit in guest VM"
      step_6 = "Label GPU node: kubectl label node <node> nvidia.com/gpu.present=true"
    }

    commands = {
      check_plugin = "kubectl get pods -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin"
      check_gpu    = "kubectl describe node <gpu-node> | grep nvidia.com/gpu"
      test_gpu     = "kubectl run gpu-test --rm -it --image=nvidia/cuda:12.4.0-base-ubuntu22.04 --limits=nvidia.com/gpu=1 -- nvidia-smi"
    }
  }
}
```

**Step 2: Format and validate**

Run: `cd terraform && terraform fmt nvidia.tf && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
git add terraform/nvidia.tf
git commit -m "feat: add NVIDIA device plugin for GPU scheduling"
```

---

## Task 2: Create `terraform/ollama.tf` — LLM Inference

**Files:**
- Create: `terraform/ollama.tf`

**Step 1: Write the Ollama Terraform file**

Reference `terraform/bazarr.tf` for the Longhorn + NFS PV/PVC pattern. Ollama uses NFS for model storage with a `subPath` under the media share at `ai-models/ollama`. GPU scheduling uses `nodeSelector` and resource limits.

```hcl
# =============================================================================
# Ollama — Local LLM Inference
# =============================================================================
# Runs large language models locally with GPU acceleration. API endpoint
# accessible by other services (n8n, custom apps) via cluster DNS.
# Longhorn PVC for config, NFS mount for model storage under /volume2/media.
# =============================================================================

# Variables
variable "ollama_config_storage_size" {
  description = "Storage size for Ollama config"
  type        = string
  default     = "1Gi"
}

variable "ollama_memory_request" {
  description = "Memory request for Ollama container"
  type        = string
  default     = "2Gi"
}

variable "ollama_memory_limit" {
  description = "Memory limit for Ollama container"
  type        = string
  default     = "8Gi"
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

# Namespace
resource "kubernetes_namespace" "ollama" {
  metadata {
    name = "ollama"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "ollama"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "ollama_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "ollama-config"
    namespace = kubernetes_namespace.ollama.metadata[0].name
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
  metadata {
    name      = "ollama-models"
    namespace = kubernetes_namespace.ollama.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.ollama_models.metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "ollama" {
  depends_on = [
    kubernetes_persistent_volume_claim.ollama_config,
    kubernetes_persistent_volume_claim.ollama_models,
    helm_release.longhorn
  ]

  metadata {
    name      = "ollama"
    namespace = kubernetes_namespace.ollama.metadata[0].name
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
        dynamic "node_selector" {
          for_each = var.ollama_gpu_enabled ? [1] : []
          content {
          }
        }

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

        volume {
          name = "ollama-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_config.metadata[0].name
          }
        }

        volume {
          name = "models"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_models.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "ollama" {
  depends_on = [
    kubernetes_deployment.ollama
  ]

  metadata {
    name      = "ollama-service"
    namespace = kubernetes_namespace.ollama.metadata[0].name
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
  value = {
    namespace    = kubernetes_namespace.ollama.metadata[0].name
    service_name = kubernetes_service.ollama.metadata[0].name
    config_size  = var.ollama_config_storage_size
    gpu_enabled  = var.ollama_gpu_enabled

    access = {
      web_ui      = "https://ollama.${var.traefik_domain}"
      cluster_api = "ollama-service.${kubernetes_namespace.ollama.metadata[0].name}.svc.cluster.local:80"
    }

    nfs_mounts = {
      models = "${var.nfs_server}:${var.nfs_media_share}/ai-models/ollama"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.ollama.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.ollama.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.ollama.metadata[0].name} -l app=ollama -f"
      pull_model = "kubectl exec -n ${kubernetes_namespace.ollama.metadata[0].name} deploy/ollama -- ollama pull llama3.2"
      list_models = "kubectl exec -n ${kubernetes_namespace.ollama.metadata[0].name} deploy/ollama -- ollama list"
    }
  }

  sensitive = true
}
```

**Step 2: Format and validate**

Run: `cd terraform && terraform fmt ollama.tf && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
git add terraform/ollama.tf
git commit -m "feat: add Ollama LLM inference service"
```

---

## Task 3: Create `terraform/qdrant.tf` — Vector Database

**Files:**
- Create: `terraform/qdrant.tf`

**Step 1: Write the Qdrant Terraform file**

Reference `terraform/cleanuparr.tf` for the simple Longhorn-only pattern. Qdrant is CPU-only, no NFS, no GPU.

```hcl
# =============================================================================
# Qdrant — Vector Database
# =============================================================================
# Production-grade vector search engine for RAG pipelines and similarity search.
# REST API on port 6333, gRPC on port 6334. CPU-only, no GPU required.
# Longhorn PVC for persistent vector data storage.
# =============================================================================

# Variables
variable "qdrant_storage_size" {
  description = "Storage size for Qdrant data"
  type        = string
  default     = "4Gi"
}

variable "qdrant_memory_request" {
  description = "Memory request for Qdrant container"
  type        = string
  default     = "256Mi"
}

variable "qdrant_memory_limit" {
  description = "Memory limit for Qdrant container"
  type        = string
  default     = "1Gi"
}

variable "qdrant_cpu_request" {
  description = "CPU request for Qdrant container"
  type        = string
  default     = "100m"
}

variable "qdrant_cpu_limit" {
  description = "CPU limit for Qdrant container"
  type        = string
  default     = "1000m"
}

variable "qdrant_image_tag" {
  description = "Qdrant container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "qdrant" {
  metadata {
    name = "qdrant"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qdrant"
    })
  }
}

# Persistent Volume Claim — Data (Longhorn)
resource "kubernetes_persistent_volume_claim" "qdrant_data" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "qdrant-data"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.qdrant_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "qdrant" {
  depends_on = [
    kubernetes_persistent_volume_claim.qdrant_data,
    helm_release.longhorn
  ]

  metadata {
    name      = "qdrant"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qdrant"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "qdrant"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "qdrant"
        })
      }

      spec {
        container {
          name  = "qdrant"
          image = "qdrant/qdrant:${var.qdrant_image_tag}"

          port {
            container_port = 6333
            name           = "rest"
          }

          port {
            container_port = 6334
            name           = "grpc"
          }

          volume_mount {
            name       = "qdrant-data"
            mount_path = "/qdrant/storage"
          }

          resources {
            requests = {
              memory = var.qdrant_memory_request
              cpu    = var.qdrant_cpu_request
            }
            limits = {
              memory = var.qdrant_memory_limit
              cpu    = var.qdrant_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 6333
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 6333
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "qdrant-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.qdrant_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "qdrant" {
  depends_on = [
    kubernetes_deployment.qdrant
  ]

  metadata {
    name      = "qdrant-service"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qdrant"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "qdrant"
    }

    port {
      name        = "rest"
      protocol    = "TCP"
      port        = 80
      target_port = 6333
    }

    port {
      name        = "grpc"
      protocol    = "TCP"
      port        = 6334
      target_port = 6334
    }
  }
}

# Outputs
output "qdrant_info" {
  description = "Qdrant vector database information"
  value = {
    namespace    = kubernetes_namespace.qdrant.metadata[0].name
    service_name = kubernetes_service.qdrant.metadata[0].name
    storage_size = var.qdrant_storage_size

    access = {
      web_ui       = "https://qdrant.${var.traefik_domain}"
      cluster_rest = "qdrant-service.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local:80"
      cluster_grpc = "qdrant-service.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local:6334"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.qdrant.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.qdrant.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.qdrant.metadata[0].name} -l app=qdrant -f"
    }
  }

  sensitive = true
}
```

**Step 2: Format and validate**

Run: `cd terraform && terraform fmt qdrant.tf && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
git add terraform/qdrant.tf
git commit -m "feat: add Qdrant vector database service"
```

---

## Task 4: Create `terraform/chromadb.tf` — Vector Database

**Files:**
- Create: `terraform/chromadb.tf`

**Step 1: Write the ChromaDB Terraform file**

Same pattern as Qdrant — Longhorn PVC only, no NFS, no GPU.

```hcl
# =============================================================================
# ChromaDB — Vector Database
# =============================================================================
# Python-native vector database for RAG prototyping and experimentation.
# REST API on port 8000. CPU-only, no GPU required.
# Longhorn PVC for persistent vector data storage.
# =============================================================================

# Variables
variable "chromadb_storage_size" {
  description = "Storage size for ChromaDB data"
  type        = string
  default     = "4Gi"
}

variable "chromadb_memory_request" {
  description = "Memory request for ChromaDB container"
  type        = string
  default     = "256Mi"
}

variable "chromadb_memory_limit" {
  description = "Memory limit for ChromaDB container"
  type        = string
  default     = "1Gi"
}

variable "chromadb_cpu_request" {
  description = "CPU request for ChromaDB container"
  type        = string
  default     = "100m"
}

variable "chromadb_cpu_limit" {
  description = "CPU limit for ChromaDB container"
  type        = string
  default     = "1000m"
}

variable "chromadb_image_tag" {
  description = "ChromaDB container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "chromadb" {
  metadata {
    name = "chromadb"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "chromadb"
    })
  }
}

# Persistent Volume Claim — Data (Longhorn)
resource "kubernetes_persistent_volume_claim" "chromadb_data" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "chromadb-data"
    namespace = kubernetes_namespace.chromadb.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.chromadb_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "chromadb" {
  depends_on = [
    kubernetes_persistent_volume_claim.chromadb_data,
    helm_release.longhorn
  ]

  metadata {
    name      = "chromadb"
    namespace = kubernetes_namespace.chromadb.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "chromadb"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "chromadb"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "chromadb"
        })
      }

      spec {
        container {
          name  = "chromadb"
          image = "chromadb/chroma:${var.chromadb_image_tag}"

          port {
            container_port = 8000
            name           = "http"
          }

          env {
            name  = "IS_PERSISTENT"
            value = "TRUE"
          }

          env {
            name  = "PERSIST_DIRECTORY"
            value = "/chroma/chroma"
          }

          env {
            name  = "ANONYMIZED_TELEMETRY"
            value = "FALSE"
          }

          volume_mount {
            name       = "chromadb-data"
            mount_path = "/chroma/chroma"
          }

          resources {
            requests = {
              memory = var.chromadb_memory_request
              cpu    = var.chromadb_cpu_request
            }
            limits = {
              memory = var.chromadb_memory_limit
              cpu    = var.chromadb_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/api/v1/heartbeat"
              port = 8000
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/api/v1/heartbeat"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "chromadb-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.chromadb_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "chromadb" {
  depends_on = [
    kubernetes_deployment.chromadb
  ]

  metadata {
    name      = "chromadb-service"
    namespace = kubernetes_namespace.chromadb.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "chromadb"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "chromadb"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8000
    }
  }
}

# Outputs
output "chromadb_info" {
  description = "ChromaDB vector database information"
  value = {
    namespace    = kubernetes_namespace.chromadb.metadata[0].name
    service_name = kubernetes_service.chromadb.metadata[0].name
    storage_size = var.chromadb_storage_size

    access = {
      web_ui      = "https://chromadb.${var.traefik_domain}"
      cluster_api = "chromadb-service.${kubernetes_namespace.chromadb.metadata[0].name}.svc.cluster.local:80"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.chromadb.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.chromadb.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.chromadb.metadata[0].name} -l app=chromadb -f"
    }
  }

  sensitive = true
}
```

**Step 2: Format and validate**

Run: `cd terraform && terraform fmt chromadb.tf && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
git add terraform/chromadb.tf
git commit -m "feat: add ChromaDB vector database service"
```

---

## Task 5: Create `terraform/comfyui.tf` — Image Generation

**Files:**
- Create: `terraform/comfyui.tf`

**Step 1: Write the ComfyUI Terraform file**

Reference `terraform/ollama.tf` (Task 2) for the GPU + NFS pattern. ComfyUI needs Longhorn for config and NFS for models + output.

```hcl
# =============================================================================
# ComfyUI — Stable Diffusion Image Generation
# =============================================================================
# Node-based Stable Diffusion workflow builder with GPU acceleration.
# Longhorn PVC for config, NFS mount for models and generated outputs
# under /volume2/media/ai-models/comfyui/.
# =============================================================================

# Variables
variable "comfyui_config_storage_size" {
  description = "Storage size for ComfyUI config"
  type        = string
  default     = "1Gi"
}

variable "comfyui_memory_request" {
  description = "Memory request for ComfyUI container"
  type        = string
  default     = "2Gi"
}

variable "comfyui_memory_limit" {
  description = "Memory limit for ComfyUI container"
  type        = string
  default     = "8Gi"
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
  metadata {
    name = "comfyui"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "comfyui"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "comfyui_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "comfyui-config"
    namespace = kubernetes_namespace.comfyui.metadata[0].name
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
  metadata {
    name      = "comfyui-models"
    namespace = kubernetes_namespace.comfyui.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.comfyui_models.metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "comfyui" {
  depends_on = [
    kubernetes_persistent_volume_claim.comfyui_config,
    kubernetes_persistent_volume_claim.comfyui_models,
    helm_release.longhorn
  ]

  metadata {
    name      = "comfyui"
    namespace = kubernetes_namespace.comfyui.metadata[0].name
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
            claim_name = kubernetes_persistent_volume_claim.comfyui_config.metadata[0].name
          }
        }

        volume {
          name = "models"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.comfyui_models.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "comfyui" {
  depends_on = [
    kubernetes_deployment.comfyui
  ]

  metadata {
    name      = "comfyui-service"
    namespace = kubernetes_namespace.comfyui.metadata[0].name
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
  value = {
    namespace    = kubernetes_namespace.comfyui.metadata[0].name
    service_name = kubernetes_service.comfyui.metadata[0].name
    config_size  = var.comfyui_config_storage_size
    gpu_enabled  = var.comfyui_gpu_enabled

    access = {
      web_ui = "https://comfyui.${var.traefik_domain}"
    }

    nfs_mounts = {
      models = "${var.nfs_server}:${var.nfs_media_share}/ai-models/comfyui"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.comfyui.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.comfyui.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.comfyui.metadata[0].name} -l app=comfyui -f"
    }
  }

  sensitive = true
}
```

**Step 2: Format and validate**

Run: `cd terraform && terraform fmt comfyui.tf && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
git add terraform/comfyui.tf
git commit -m "feat: add ComfyUI image generation service"
```

---

## Task 6: Add Wave 5 IngressRoutes to `terraform/ingress.tf`

**Files:**
- Modify: `terraform/ingress.tf` — Insert 4 IngressRoutes before the `# --- Static Sites ---` section

**Step 1: Add IngressRoutes for ollama, qdrant, chromadb, comfyui**

Insert the following block before the `# --- Static Sites ---` comment (after the notifiarr IngressRoute). Each follows the same pattern as Wave 4 IngressRoutes with rate-limit + crowdsec-bouncer + oauth-forward-auth middleware.

```hcl
# --- Wave 5: AI/ML Stack ---

resource "kubernetes_manifest" "ingressroute_ollama" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "ollama"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`ollama.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.ollama.metadata[0].name
          namespace = kubernetes_namespace.ollama.metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.ollama,
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

resource "kubernetes_manifest" "ingressroute_qdrant" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "qdrant"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`qdrant.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.qdrant.metadata[0].name
          namespace = kubernetes_namespace.qdrant.metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.qdrant,
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

resource "kubernetes_manifest" "ingressroute_chromadb" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "chromadb"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`chromadb.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.chromadb.metadata[0].name
          namespace = kubernetes_namespace.chromadb.metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.chromadb,
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

resource "kubernetes_manifest" "ingressroute_comfyui" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "comfyui"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`comfyui.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.comfyui.metadata[0].name
          namespace = kubernetes_namespace.comfyui.metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.comfyui,
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}
```

**Step 2: Format and validate**

Run: `cd terraform && terraform fmt ingress.tf && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
git add terraform/ingress.tf
git commit -m "feat: add Wave 5 IngressRoutes for AI/ML services"
```

---

## Task 7: Add Wave 5 DNS records to `terraform/dns.tf`

**Files:**
- Modify: `terraform/dns.tf` — Add 4 entries to `dns_records` local

**Step 1: Add DNS records**

Add these 4 entries after the Wave 4 entries (after `notifiarr`) in the `dns_records` local map:

```hcl
    ollama       = "ollama"
    qdrant       = "qdrant"
    chromadb     = "chromadb"
    comfyui      = "comfyui"
```

**Step 2: Format and validate**

Run: `cd terraform && terraform fmt dns.tf && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Commit**

```bash
git add terraform/dns.tf
git commit -m "feat: add Wave 5 DNS records for AI/ML services"
```

---

## Task 8: Add Wave 5 Makefile targets

**Files:**
- Modify: `terraform/Makefile`

**Step 1: Add .PHONY entries**

Add to the `.PHONY` continuation after the Wave 4 entries:

```makefile
	plan-nvidia apply-nvidia plan-ollama apply-ollama plan-qdrant apply-qdrant \
	plan-chromadb apply-chromadb plan-comfyui apply-comfyui \
```

**Step 2: Add plan targets**

Insert after the `plan-flaresolverr` target:

```makefile
plan-nvidia: check-vars check-init ## Plan NVIDIA device plugin
	@echo "Planning NVIDIA device plugin..."
	terraform plan \
		-target=helm_release.nvidia_device_plugin

plan-ollama: check-vars check-init ## Plan Ollama LLM inference
	@echo "Planning Ollama components..."
	terraform plan \
		-target=kubernetes_namespace.ollama \
		-target=kubernetes_persistent_volume_claim.ollama_config \
		-target=kubernetes_persistent_volume.ollama_models \
		-target=kubernetes_persistent_volume_claim.ollama_models \
		-target=kubernetes_deployment.ollama \
		-target=kubernetes_service.ollama

plan-qdrant: check-vars check-init ## Plan Qdrant vector database
	@echo "Planning Qdrant components..."
	terraform plan \
		-target=kubernetes_namespace.qdrant \
		-target=kubernetes_persistent_volume_claim.qdrant_data \
		-target=kubernetes_deployment.qdrant \
		-target=kubernetes_service.qdrant

plan-chromadb: check-vars check-init ## Plan ChromaDB vector database
	@echo "Planning ChromaDB components..."
	terraform plan \
		-target=kubernetes_namespace.chromadb \
		-target=kubernetes_persistent_volume_claim.chromadb_data \
		-target=kubernetes_deployment.chromadb \
		-target=kubernetes_service.chromadb

plan-comfyui: check-vars check-init ## Plan ComfyUI image generation
	@echo "Planning ComfyUI components..."
	terraform plan \
		-target=kubernetes_namespace.comfyui \
		-target=kubernetes_persistent_volume_claim.comfyui_config \
		-target=kubernetes_persistent_volume.comfyui_models \
		-target=kubernetes_persistent_volume_claim.comfyui_models \
		-target=kubernetes_deployment.comfyui \
		-target=kubernetes_service.comfyui
```

**Step 3: Add apply targets**

Insert after the `apply-flaresolverr` target:

```makefile
apply-nvidia: check-vars check-init ## Deploy NVIDIA device plugin
	@echo "Deploying NVIDIA device plugin..."
	terraform apply -auto-approve \
		-target=helm_release.nvidia_device_plugin

apply-ollama: check-vars check-init ## Deploy Ollama LLM inference
	@echo "Deploying Ollama..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.ollama \
		-target=kubernetes_persistent_volume_claim.ollama_config \
		-target=kubernetes_persistent_volume.ollama_models \
		-target=kubernetes_persistent_volume_claim.ollama_models \
		-target=kubernetes_deployment.ollama \
		-target=kubernetes_service.ollama

apply-qdrant: check-vars check-init ## Deploy Qdrant vector database
	@echo "Deploying Qdrant..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.qdrant \
		-target=kubernetes_persistent_volume_claim.qdrant_data \
		-target=kubernetes_deployment.qdrant \
		-target=kubernetes_service.qdrant

apply-chromadb: check-vars check-init ## Deploy ChromaDB vector database
	@echo "Deploying ChromaDB..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.chromadb \
		-target=kubernetes_persistent_volume_claim.chromadb_data \
		-target=kubernetes_deployment.chromadb \
		-target=kubernetes_service.chromadb

apply-comfyui: check-vars check-init ## Deploy ComfyUI image generation
	@echo "Deploying ComfyUI..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.comfyui \
		-target=kubernetes_persistent_volume_claim.comfyui_config \
		-target=kubernetes_persistent_volume.comfyui_models \
		-target=kubernetes_persistent_volume_claim.comfyui_models \
		-target=kubernetes_deployment.comfyui \
		-target=kubernetes_service.comfyui
```

**Step 4: Commit**

```bash
git add terraform/Makefile
git commit -m "feat: add Wave 5 Makefile plan/apply targets"
```

---

## Task 9: Update `terraform/terraform.tfvars.example` with Wave 5 variables

**Files:**
- Modify: `terraform/terraform.tfvars.example`

**Step 1: Add Wave 5 variable examples**

Insert after the Flaresolverr section (before the `# Labels` section):

```hcl
# NVIDIA Device Plugin (Wave 5 — enable after GPU passthrough is configured)
#nvidia_device_plugin_enabled       = false
#nvidia_device_plugin_chart_version = "0.17.0"

# Ollama LLM Inference (Wave 5)
#ollama_config_storage_size = "1Gi"
#ollama_memory_request      = "2Gi"
#ollama_memory_limit        = "8Gi"
#ollama_image_tag           = "latest"
#ollama_gpu_enabled         = false    # Set to true after NVIDIA device plugin is running

# Qdrant Vector Database (Wave 5)
#qdrant_storage_size   = "4Gi"
#qdrant_memory_request = "256Mi"
#qdrant_memory_limit   = "1Gi"
#qdrant_image_tag      = "latest"

# ChromaDB Vector Database (Wave 5)
#chromadb_storage_size   = "4Gi"
#chromadb_memory_request = "256Mi"
#chromadb_memory_limit   = "1Gi"
#chromadb_image_tag      = "latest"

# ComfyUI Image Generation (Wave 5)
#comfyui_config_storage_size = "1Gi"
#comfyui_memory_request      = "2Gi"
#comfyui_memory_limit        = "8Gi"
#comfyui_image_tag           = "latest"
#comfyui_gpu_enabled         = false    # Set to true after NVIDIA device plugin is running
```

**Step 2: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "docs: add Wave 5 variable examples to terraform.tfvars.example"
```

---

## Task 10: Update `CLAUDE.md` with Wave 5 documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Wave 5 files to File Organization section**

Add after the flaresolverr.tf entry in the file organization list:

```markdown
- [nvidia.tf](terraform/nvidia.tf) — NVIDIA device plugin via Helm (GPU resource scheduling, conditional on `nvidia_device_plugin_enabled`)
- [ollama.tf](terraform/ollama.tf) — Ollama LLM inference (Longhorn config PVC + NFS models mount, GPU nodeSelector, ollama/ollama)
- [qdrant.tf](terraform/qdrant.tf) — Qdrant vector database (Longhorn data PVC, qdrant/qdrant)
- [chromadb.tf](terraform/chromadb.tf) — ChromaDB vector database (Longhorn data PVC, chromadb/chroma)
- [comfyui.tf](terraform/comfyui.tf) — ComfyUI image generation (Longhorn config PVC + NFS models mount, GPU nodeSelector, yanwk/comfyui-boot)
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Wave 5 AI/ML service files"
```

---

## Task 11: Validate full configuration

**Files:**
- None (validation only)

**Step 1: Format all Terraform files**

Run: `cd terraform && terraform fmt -check -recursive .`
Expected: No output (all files formatted correctly)

**Step 2: Validate configuration**

Run: `cd terraform && terraform validate`
Expected: `Success! The configuration is valid.`

**Step 3: Dry-run Makefile targets**

Run: `cd terraform && make -n plan-nvidia && make -n apply-ollama && make -n plan-comfyui`
Expected: Each prints the `terraform plan/apply` command with correct `-target` flags

**Step 4: Verify no uncommitted changes**

Run: `git status`
Expected: Clean working tree
