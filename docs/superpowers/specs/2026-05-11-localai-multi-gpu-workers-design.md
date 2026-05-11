# LocalAI Multi-GPU Workers Design

**Date:** 2026-05-11  
**Files:** `terraform/nvidia.tf`, `terraform/localai.tf`, `terraform/terraform.tfvars.example`

## Goal

Run one LocalAI worker pod per GPU on nodes that have multiple GPUs. A 1-GPU node gets 1 worker; a 2-GPU node gets 2 workers; etc.

## Architecture

```
node-a (1 GPU)       node-b (2 GPUs)
  localai-worker-0     localai-worker-0   ← gpu-count-1=true on all GPU nodes
                       localai-worker-1   ← gpu-count-2=true only on 2+ GPU nodes
```

Each worker pod requests `nvidia.com/gpu=1`. The NVIDIA device plugin assigns a specific physical GPU to each pod automatically — no `NVIDIA_VISIBLE_DEVICES` override needed.

## Changes

### nvidia.tf

**New variable:**
```hcl
variable "gpu_counts" {
  description = "Map of GPU node hostname to number of GPUs"
  type        = map(number)
  default     = {}
}
```

**New locals:**
- `gpu_count_tiers` — range 1–8 (supports up to 8 GPUs per node)
- `gpu_count_labels` — cumulative per-node labels: a node with 2 GPUs gets `gpu-count-1=true` and `gpu-count-2=true`
- `max_gpus_per_node` — `max(values(var.gpu_counts)...)`, defaults to 1 when `gpu_counts` is empty

**Updated `kubernetes_labels.gpu_node_vram`:** merge `gpu_count_labels[node]` into each node's labels (alongside existing VRAM tier labels). Only nodes present in both `gpu_nodes` and `gpu_counts` get count labels; nodes absent from `gpu_counts` are unaffected.

### localai.tf

**DaemonSet count:** `count = var.localai_enabled && var.localai_gpu_enabled ? local.max_gpus_per_node : 0`

**Name:** `localai-worker-${count.index}` (was `localai-worker`)

**nodeSelector per instance:**
```hcl
node_selector = merge(
  { "gpu-count-${count.index + 1}" = "true" },
  var.localai_gpu_min_vram_gb > 0 ? { "gpu-vram-${var.localai_gpu_min_vram_gb}gb" = "true" } : {}
)
```
(The outer `var.localai_gpu_enabled` gate is no longer needed on the selector — the count being 0 when disabled already prevents any pods from deploying.)

### terraform.tfvars.example

Add `gpu_counts` placeholder in the NVIDIA section, alongside `gpu_nodes`.

## Migration note

The existing `localai-worker` DaemonSet is renamed to `localai-worker-0` on next apply. Terraform will destroy and recreate the DaemonSet object (pod restarts), but NFS-backed volumes are unaffected.

## Backward compatibility

If `gpu_counts` is not set (empty map, the default), `max_gpus_per_node` = 1 and behaviour is identical to the current single-DaemonSet setup.
