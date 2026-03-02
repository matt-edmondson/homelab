# Wave 5: AI/ML Stack Design

## Context

Waves 0-4 deployed networking, security, automation, and media stack services. Wave 5 adds AI/ML capabilities: local LLM inference (Ollama), vector databases (Qdrant, ChromaDB), and image generation (ComfyUI). Two of these services require GPU access via NVIDIA RTX 2060 passthrough from the Proxmox host.

### Prerequisites

- Wave 0: NFS CSI driver (for Ollama and ComfyUI NFS model mounts)
- Wave 1: CrowdSec + OAuth (for ingress middleware)
- **Manual Proxmox host configuration** (not Terraform-managed):
  1. Enable IOMMU: Add `intel_iommu=on iommu=pt` to kernel cmdline, reboot
  2. Blacklist nouveau: Add `blacklist nouveau` to `/etc/modprobe.d/blacklist.conf`, run `update-initramfs -u`
  3. Configure VFIO: Bind RTX 2060 PCI device IDs to `vfio-pci` driver via `/etc/modprobe.d/vfio.conf`
  4. Pass GPU to K8s node: Add PCI device to one K8s node VM (e.g. k8s01) via Proxmox UI
  5. Increase node RAM: Bump GPU node (and potentially others) to accommodate ~9GB Wave 5 overhead
  6. Install NVIDIA drivers in guest VM: `nvidia-driver` kernel module + `nvidia-container-toolkit` package

## Design Decisions

1. **Same Terraform pattern as Waves 3-4:** One `.tf` file per service with variables, namespace, PVC(s), Deployment, Service, outputs.
2. **OAuth on all exposed services:** All 4 IngressRoutes get rate-limit + crowdsec-bouncer + oauth-forward-auth middleware.
3. **GPU scheduling via nodeSelector:** GPU services (Ollama, ComfyUI) use `nodeSelector` with `nvidia.com/gpu.present: "true"` and `resources.limits["nvidia.com/gpu"] = "1"`. No taints/tolerations needed.
4. **NVIDIA device plugin via Helm:** Deployed as a DaemonSet that detects GPUs and exposes `nvidia.com/gpu` as a schedulable K8s resource.
5. **NFS for model storage:** Ollama models and ComfyUI models/outputs stored on the NAS under `/volume2/media/ai-models/` subdirectories (reuses existing NFS media share).
6. **Longhorn for config/data:** Qdrant and ChromaDB get Longhorn PVCs for their databases. Ollama and ComfyUI get small Longhorn PVCs for config.

## Services

| Service | Image | Port | Longhorn PVC | NFS Mount | GPU | IngressRoute | DNS Subdomain | Est. RAM |
|---------|-------|------|-------------|-----------|-----|-------------|---------------|----------|
| NVIDIA device plugin | nvcr.io/nvidia/k8s-device-plugin | — | None | None | DaemonSet | No | None | 32MB |
| Ollama | ollama/ollama | 11434 | 1Gi (config) | media (models subpath) | Yes | Yes | ollama | 4GB |
| Qdrant | qdrant/qdrant | 6333/6334 | 4Gi (data) | None | No | Yes | qdrant | 512MB |
| ChromaDB | chromadb/chroma | 8000 | 4Gi (data) | None | No | Yes | chromadb | 512MB |
| ComfyUI | yanwk/comfyui-boot | 8188 | 1Gi (config) | media (models+output subpath) | Yes | Yes | comfyui | 4GB |

**Total estimated RAM: ~9GB + GPU**

## Integration Points

- **Ollama** — LLM API endpoint. Other services (n8n, custom apps) can call `ollama-service.ollama.svc.cluster.local:11434`
- **Qdrant** — Vector search API. gRPC on 6334, REST on 6333. Used by RAG pipelines and n8n workflows
- **ChromaDB** — Vector DB API on 8000. Python-native, used for experimentation and RAG prototyping
- **ComfyUI** — Stable Diffusion web UI. Standalone image generation workflow builder
- **NVIDIA device plugin** — Cluster-wide DaemonSet that makes GPUs schedulable. Ollama and ComfyUI request GPU resources from it

## NFS Model Storage Layout

All under the existing `/volume2/media` NFS share:

```
/volume2/media/ai-models/
├── ollama/          # Ollama model blobs (mounted at /root/.ollama/models)
└── comfyui/
    ├── models/      # SD checkpoints, LoRAs, VAEs (mounted at model paths)
    └── output/      # Generated images (mounted at /comfyui/output)
```

## Resource Budget

Current cluster: Will be increased before Wave 5 deployment.
Waves 0-4 estimated: ~8.7GB.
Wave 5 adds: ~9GB + GPU.
Running total after Wave 5: ~17.7GB (requires node RAM increase).

## Files to Create/Modify

**New files:** `nvidia.tf`, `ollama.tf`, `qdrant.tf`, `chromadb.tf`, `comfyui.tf`

**Modified files:**
- `ingress.tf` — Add IngressRoutes for 4 services (all except NVIDIA plugin)
- `dns.tf` — Add 4 DNS subdomain records (ollama, qdrant, chromadb, comfyui)
- `Makefile` — Add plan/apply targets for each service
- `terraform.tfvars.example` — Add Wave 5 variable examples
- `CLAUDE.md` — Update file organization and commands
