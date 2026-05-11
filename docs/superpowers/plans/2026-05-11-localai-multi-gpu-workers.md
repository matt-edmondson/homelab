# LocalAI Multi-GPU Workers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run one LocalAI worker per GPU node where each worker claims all GPUs on that node, enabling llama.cpp to split large models across multiple GPUs within a single pod.

**Architecture:** Add a `gpu_counts` variable (node → GPU count) to `nvidia.tf` and generate `gpu-count-exact-N` node labels. Replace the single count-based worker DaemonSet in `localai.tf` with a `for_each` over unique GPU count tiers — one DaemonSet per tier (e.g. "1", "2"), each requesting N GPUs and targeting nodes labelled `gpu-count-exact-N`. LocalAI's SmartRouter handles VRAM-aware request routing automatically.

**Tech Stack:** Terraform (Kubernetes provider ~> 2.38), Kubernetes DaemonSet, LocalAI P2P swarm.

---

### Task 1: Add `gpu_counts` variable and node labels to `nvidia.tf`

**Files:**
- Modify: `terraform/nvidia.tf`
- Modify: `terraform/terraform.tfvars.example`

- [ ] **Step 1: Add the `gpu_counts` variable to `terraform/nvidia.tf`**

Insert after the closing `}` of `variable "gpu_nodes"` (after line 37):

```hcl
variable "gpu_counts" {
  description = "Map of GPU node hostname to number of GPUs (e.g. { \"node.home\" = 2 }). Nodes absent from this map default to 1 GPU."
  type        = map(number)
  default     = {}
}
```

- [ ] **Step 2: Add `gpu_count_exact_labels` to the `locals` block in `terraform/nvidia.tf`**

The current `locals` block ends at line 51. Add the new entry inside it, after `gpu_node_labels`:

```hcl
locals {
  vram_tiers = [4, 6, 8, 10, 12, 16, 24, 48]

  # For each GPU node, generate cumulative tier labels (a 12GB node satisfies 4, 6, 8, 10, 12)
  gpu_node_labels = {
    for node, vram in var.gpu_nodes : node => {
      for tier in local.vram_tiers :
      "gpu-vram-${tier}gb" => "true"
      if tier <= vram
    }
  }

  # For each GPU node, generate an exact GPU count label (a node with 2 GPUs gets gpu-count-exact-2)
  # Nodes absent from gpu_counts default to 1 GPU
  gpu_count_exact_labels = {
    for node, vram in var.gpu_nodes : node => {
      "gpu-count-exact-${lookup(var.gpu_counts, node, 1)}" = "true"
    }
  }
}
```

- [ ] **Step 3: Merge count labels into `kubernetes_labels.gpu_node_vram`**

Replace the current `labels` block inside `kubernetes_labels.gpu_node_vram`:

```hcl
# BEFORE:
  labels = merge(
    { "nvidia.com/gpu.present" = "true" },
    local.gpu_node_labels[each.key]
  )

# AFTER:
  labels = merge(
    { "nvidia.com/gpu.present" = "true" },
    local.gpu_node_labels[each.key],
    local.gpu_count_exact_labels[each.key]
  )
```

- [ ] **Step 4: Update the `nvidia_device_plugin_info` output**

In the `output "nvidia_device_plugin_info"` block, add `gpu_counts` next to `gpu_nodes` and update `check_labels` to also grep for count labels:

```hcl
# BEFORE:
    gpu_nodes     = var.gpu_nodes
    vram_labels   = local.gpu_node_labels
    ...
      check_labels = "kubectl get nodes --show-labels | grep gpu-vram"

# AFTER:
    gpu_nodes     = var.gpu_nodes
    gpu_counts    = var.gpu_counts
    vram_labels   = local.gpu_node_labels
    count_labels  = local.gpu_count_exact_labels
    ...
      check_labels = "kubectl get nodes --show-labels | grep -E 'gpu-vram|gpu-count'"
```

- [ ] **Step 5: Add `gpu_counts` placeholder to `terraform/terraform.tfvars.example`**

Insert after line 228 (the closing `#}` of the `gpu_nodes` block):

```hcl

# GPU Node Count Map — maps node hostname to number of GPUs (omit nodes with 1 GPU, that is the default)
# Used to generate gpu-count-exact-N labels; LocalAI workers use these to request all GPUs on a node
#gpu_counts = {
#  "rainbow.home" = 2
#}
```

- [ ] **Step 6: Validate**

```
cd C:\dev\matt-edmondson\homelab\terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```
git add terraform/nvidia.tf terraform/terraform.tfvars.example
git commit -m "feat(nvidia): add gpu_counts variable and gpu-count-exact-N node labels"
```

Do NOT add "Co-Authored-By" to the commit message.

---

### Task 2: Replace worker DaemonSet with per-GPU-tier `for_each`

**Files:**
- Modify: `terraform/localai.tf` — replace the DaemonSet block (lines ~501–642) and update the output block

- [ ] **Step 1: Add a `locals` block with `localai_worker_gpu_tiers` to `terraform/localai.tf`**

Insert immediately before the `# === Worker DaemonSet ===` comment (before line 501). This derives the unique GPU count values across all GPU nodes, defaulting to "1" for any node absent from `gpu_counts`:

```hcl
locals {
  localai_worker_gpu_tiers = toset([
    for node in keys(var.gpu_nodes) : tostring(lookup(var.gpu_counts, node, 1))
  ])
}

```

- [ ] **Step 2: Replace the entire `kubernetes_daemonset "localai_worker"` block**

Delete everything from `# === Worker DaemonSet ===` through the closing `}` of the resource (lines ~501–642) and replace with:

```hcl
# =============================================================================
# Worker DaemonSet — one GPU worker per GPU-count tier
# =============================================================================
# One DaemonSet per unique GPU count value (e.g. "1", "2"). Each DaemonSet
# targets nodes labelled gpu-count-exact-N and requests N GPUs, letting
# llama.cpp use all GPUs on the node for large-model inference.

resource "kubernetes_daemonset" "localai_worker" {
  for_each = var.localai_enabled && var.localai_gpu_enabled ? local.localai_worker_gpu_tiers : toset([])

  depends_on = [
    kubernetes_secret.localai_p2p,
    kubernetes_persistent_volume_claim.localai_models,
    kubernetes_persistent_volume_claim.localai_backends,
    kubernetes_persistent_volume_claim.localai_configuration,
    helm_release.longhorn,
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
          image = "localai/localai:${var.localai_image_tag}"

          env {
            name  = "LOCALAI_WORKER"
            value = "true"
          }

          env {
            name = "LOCALAI_P2P_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.localai_p2p[0].metadata[0].name
                key  = "token"
              }
            }
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
```

- [ ] **Step 3: Update `worker_logs` in the output block**

The `worker_logs` command currently uses `-l app=localai-worker` which will no longer match the new pod labels. Update it to use the `role` label:

```hcl
# BEFORE:
      worker_logs = "kubectl logs -n ${kubernetes_namespace.localai[0].metadata[0].name} -l app=localai-worker -f"

# AFTER:
      worker_logs = "kubectl logs -n ${kubernetes_namespace.localai[0].metadata[0].name} -l role=localai-worker -f"
```

- [ ] **Step 4: Validate**

```
cd C:\dev\matt-edmondson\homelab\terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Preview the plan**

```
cd C:\dev\matt-edmondson\homelab\terraform && make plan-localai
```

Expected output includes:
- `kubernetes_daemonset.localai_worker[0]` will be **destroyed** (old count-based resource)
- `kubernetes_daemonset.localai_worker["1"]` will be **created** (new for_each resource, 1-GPU tier)
- If `gpu_counts` has nodes with 2 GPUs: `kubernetes_daemonset.localai_worker["2"]` will also be created

- [ ] **Step 6: Commit**

```
git add terraform/localai.tf
git commit -m "feat(localai): replace worker DaemonSet with per-GPU-tier for_each"
```

Do NOT add "Co-Authored-By" to the commit message.
