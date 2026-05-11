# LocalAI Swarm: Controller + GPU Worker DaemonSet

**Date:** 2026-05-11  
**File:** `terraform/localai.tf`

## Goal

Run LocalAI in distributed swarm mode: one controller pod (no GPU) handles the HTTP API and routes inference requests, while a DaemonSet deploys a worker pod on every GPU node in the cluster (including the controller's node if it has a GPU). Workers do the actual inference.

## Architecture

```
HTTP clients
     │
     ▼
[Controller Deployment] ── P2P token ──► [Worker DaemonSet pod / node-a (GPU)]
  replicas=1, no GPU                      [Worker DaemonSet pod / node-b (GPU)]
  floats to any node                      [Worker DaemonSet pod / node-n (GPU)]
```

- **Controller**: `kubernetes_deployment.localai`, `replicas=1`, no GPU allocation. Serves the OpenAI-compatible HTTP API on port 8080. Runs with `LOCALAI_P2P=true`.
- **Workers**: `kubernetes_daemonset.localai_worker`, one pod per node labelled `nvidia.com/gpu.present=true`. Each claims `nvidia.com/gpu=1`. Runs with `LOCALAI_WORKER=true`.
- **Discovery**: Token-based libp2p P2P — workers self-register with the controller using a shared secret. (`LOCALAI_GRPC_SERVERS` is for external gRPC backends and does not apply to swarm workers.)

## Changes to Existing Controller Deployment

- **Remove**: `nvidia.com/gpu` from resource limits.
- **Remove**: GPU `nodeSelector` (`nvidia.com/gpu.present`, `gpu-vram-*`).
- **Add**: `LOCALAI_P2P=true` env var.
- **Add**: `LOCALAI_P2P_TOKEN` env var sourced from `kubernetes_secret.localai_p2p`.
- **Keep**: All NFS mounts (models, backends, configuration, data, output), HTTP service, probes, everything else.

The `localai_gpu_enabled` and `localai_gpu_min_vram_gb` variables are now worker-only. The controller never requests GPU regardless of these flags.

## New Worker DaemonSet

Resource: `kubernetes_daemonset.localai_worker`

| Property | Value |
|---|---|
| Namespace | `localai` |
| Image | `localai/localai:${var.localai_image_tag}` |
| nodeSelector | `nvidia.com/gpu.present=true` |
| GPU limit | `nvidia.com/gpu=1` |
| Env: LOCALAI_WORKER | `true` |
| Env: LOCALAI_P2P_TOKEN | from `kubernetes_secret.localai_p2p` |
| NFS mounts | models, backends, configuration |
| HTTP service | none |
| Enabled gate | `var.localai_enabled` |
| Resource requests/limits | reuses existing `localai_memory_*` and `localai_cpu_*` vars |

Workers mount models, backends, and configuration because they run inference. They do not mount data or output (those stay on the controller).

## New Secret

`kubernetes_secret.localai_p2p` in the `localai` namespace, holding the token from `var.localai_p2p_token`.

## New Variable

```hcl
variable "localai_p2p_token" {
  description = "Shared P2P token for LocalAI swarm (controller + workers)"
  type        = string
  sensitive   = true
}
```

Must be added to `terraform.tfvars` (gitignored). Also added to `terraform.tfvars.example` as a placeholder.

## Files Changed

| File | Change |
|---|---|
| `terraform/localai.tf` | Add variable, Secret, modify controller Deployment, add worker DaemonSet |
| `terraform/terraform.tfvars.example` | Add `localai_p2p_token` placeholder |
