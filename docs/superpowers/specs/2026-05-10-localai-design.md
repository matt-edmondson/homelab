# LocalAI Deployment Design

**Date:** 2026-05-10
**Status:** Approved

## Goal

Add LocalAI to the cluster as a full-stack AI inference service (LLM + embeddings + image gen + audio), running alongside Ollama during a migration period, with the intent to eventually replace Ollama.

## Architecture

A new `localai.tf` file owns all resources: variables, NFS PV/PVC pairs, and a `helm_release` using the `go-skynet/local-ai` chart. A `localai_enabled` variable gates everything.

Ingress entries go in `ingress.tf` (external) and `ingress-local.tf` (local, no OAuth). A single `localai` entry in the `dns_records` map in `dns.tf` produces both `localai.ktsu.dev` and `localai.local.ktsu.dev` automatically via the existing DNS loop.

Ollama continues running unchanged during migration. Cutover is `ollama_enabled = false` in `terraform.tfvars`.

## Storage

Two static NFS PVs + PVCs, both using `nfs-media` storage class and `Retain` reclaim policy:

| PV/PVC name | NFS path | Container mount | Access mode |
|---|---|---|---|
| `localai-models-pv` / `localai-models` | `${nfs_media_share}/ai-models/localai/models` | `/models` | ReadWriteMany |
| `localai-output-pv` / `localai-output` | `${nfs_media_share}/ai-models/localai/output` | `/tmp/generated` | ReadWriteMany |

The `/models` directory holds both model weight files (GGUF, safetensors, Whisper bins) and their companion YAML config files — managed directly on the NAS, no `kubectl exec` needed.

The chart's built-in persistence is disabled (`persistence.models.enabled = false`, `persistence.output.enabled = false`). Both volumes are injected via `extraVolumes` + `extraVolumeMounts` in the Helm values.

No Longhorn PVCs are needed for LocalAI.

## GPU & Resources

Follows the existing NVIDIA device plugin pattern (no `runtimeClassName`):

- `nodeSelector`: `nvidia.com/gpu.present: "true"`, plus optional VRAM label via `localai_gpu_min_vram_gb`
- Resource limit: `nvidia.com/gpu: "1"` added when `localai_gpu_enabled = true` (default: `true`)
- Tunable variables: `localai_memory_request/limit`, `localai_cpu_request/limit`
- Image tag: `localai_image_tag`, default `master-cublas-cuda12-ffmpeg` (GPU + audio build)

## Ingress & DNS

| Route | File | Middlewares | Hostname |
|---|---|---|---|
| External | `ingress.tf` | `crowdsec-bouncer` + `oauth-forward-auth` | `localai.${traefik_domain}` |
| Local | `ingress-local.tf` | none | `localai.local.${traefik_domain}` |

Service is ClusterIP on port 80 → container port 8080 (LocalAI default). The Helm chart creates the Service; IngressRoutes reference it by the Helm release name (`localai`).

## Helm Chart

- Repo: `https://go-skynet.github.io/helm-charts/`
- Chart: `go-skynet/local-ai`
- Default tag: `master-cublas-cuda12-ffmpeg`

## Files to Create / Modify

| File | Change |
|---|---|
| `terraform/localai.tf` | New file — all LocalAI resources |
| `terraform/ingress.tf` | Add `ingressroute_localai` (Wave 5, AI/ML Stack section) |
| `terraform/ingress-local.tf` | Add local no-OAuth IngressRoute |
| `terraform/dns.tf` | Add `localai` to `dns_records` map |

## Out of Scope

- Migrating models from Ollama to LocalAI format
- Disabling Ollama (done manually via `terraform.tfvars` when ready)
- Open WebUI or other frontend (separate concern)
