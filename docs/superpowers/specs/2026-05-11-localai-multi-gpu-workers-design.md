# LocalAI Multi-GPU Workers Design

**Date:** 2026-05-11  
**Files:** `terraform/nvidia.tf`, `terraform/localai.tf`, `terraform/terraform.tfvars.example`

## Goal

Run one LocalAI worker pod per GPU node, where each worker claims **all GPUs on that node**. Nodes with 2 GPUs run one worker requesting 2 GPUs; nodes with 1 GPU run one worker requesting 1 GPU. LocalAI's SmartRouter handles VRAM-aware routing — large models are automatically directed to workers with enough capacity, and the P2P weight-sharing mode can split a model's weights across multiple workers proportionally.

## Why one worker per node (not one per GPU)

LocalAI's SmartRouter already handles routing intelligence — it knows each worker's VRAM and routes accordingly. A single multi-GPU worker pod gives llama.cpp access to all GPUs on the node simultaneously (CUDA handles the within-node split). This is simpler and more effective than multiple single-GPU workers for large models.

## Architecture

```
node-a (1x 12GB GPU)    node-b (2x 24GB GPUs)    node-c (1x 24GB GPU)
  localai-worker-1gpu      localai-worker-2gpu       localai-worker-1gpu
  requests 1 GPU           requests 2 GPUs           requests 1 GPU
  ~12GB VRAM               ~48GB VRAM                ~24GB VRAM

SmartRouter routes:
  small model (8GB)  → any available worker
  large model (40GB) → worker-2gpu only
```

## Changes

### nvidia.tf

**New variable:**
```hcl
variable "gpu_counts" {
  description = "Map of GPU node hostname to number of GPUs (e.g. { \"node-b.home\" = 2 }). Nodes absent from this map default to 1 GPU."
  type        = map(number)
  default     = {}
}
```

**New local — exact GPU count labels:**
```hcl
gpu_count_exact_labels = {
  for node, vram in var.gpu_nodes : node => {
    "gpu-count-exact-${lookup(var.gpu_counts, node, 1)}" = "true"
  }
}
```

Each node in `gpu_nodes` gets a `gpu-count-exact-N` label where N comes from `gpu_counts` or defaults to 1. Using an exact (non-cumulative) label so each DaemonSet targets precisely the right tier of nodes.

**Updated `kubernetes_labels.gpu_node_vram`:** merge `gpu_count_exact_labels[node]` into each node's labels alongside existing VRAM tier labels.

### localai.tf

**New local:**
```hcl
localai_worker_gpu_tiers = toset([
  for node in keys(var.gpu_nodes) : tostring(lookup(var.gpu_counts, node, 1))
])
```

Derives unique GPU count values across all GPU nodes. Empty when `gpu_nodes` is unset.

**DaemonSet change — `count` → `for_each`:**

Replace the single `count`-based DaemonSet with a `for_each` over `localai_worker_gpu_tiers`:

```hcl
resource "kubernetes_daemonset" "localai_worker" {
  for_each = var.localai_enabled && var.localai_gpu_enabled ? local.localai_worker_gpu_tiers : toset([])
```

Per-instance differences:
- **Name:** `localai-worker-${each.key}gpu`
- **GPU limit:** `"nvidia.com/gpu" = each.key`
- **nodeSelector:** `{ "gpu-count-exact-${each.key}" = "true" }` merged with optional VRAM tier constraint (`localai_gpu_min_vram_gb`)

Everything else (image, env vars, NFS mounts, P2P token, depends_on) is identical across instances.

### terraform.tfvars.example

Add `gpu_counts` in the NVIDIA section, adjacent to the existing `gpu_nodes` entry.

## Backward compatibility

- If `gpu_counts` is unset (default `{}`), all nodes in `gpu_nodes` default to 1 GPU → `localai_worker_gpu_tiers = ["1"]` → single DaemonSet named `localai-worker-1gpu` requesting 1 GPU with nodeSelector `gpu-count-exact-1=true`.
- The existing `localai-worker` DaemonSet (from the P2P swarm commit) will be destroyed and replaced by `localai-worker-1gpu`. Pods restart; NFS-backed volumes are unaffected.

## Migration note

Changing from `count` to `for_each` means Terraform addresses change:
- Before: `kubernetes_daemonset.localai_worker[0]`
- After: `kubernetes_daemonset.localai_worker["1"]`, `["2"]`, etc.

Terraform will destroy the old resource and create new ones. This is expected and acceptable.
