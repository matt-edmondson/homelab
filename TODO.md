# TODO

All services have been implemented in Terraform. See `docs/plans/` for design and implementation details.

## Completed (Waves 0-5)

- [x] CrowdSec (Wave 1)
- [x] Traefik Bouncer (Wave 1)
- [x] Traefik github oauth (Wave 1)
- [x] n8n (Wave 2)
- [x] postfix (Wave 2)
- [x] squid (Wave 2)
- [x] prowlarr (Wave 3)
- [x] sonarr (Wave 3)
- [x] radarr (Wave 3)
- [x] qbittorrent (Wave 3)
- [x] emby (Wave 3)
- [x] Bazarr (Wave 4)
- [x] Jackett (Wave 4)
- [x] Huntarr (Wave 4)
- [x] Cleanuparr (Wave 4)
- [x] SABnzbd (Wave 4)
- [x] notifiarr (Wave 4)
- [x] Flaresolverr (Wave 4)
- [x] ollama (Wave 5)
- [x] qdrant (Wave 5)
- [x] chromadb (Wave 5)
- [x] comfyui (Wave 5)
- [x] NVIDIA device plugin (Wave 5)

## Pending Manual Steps

- [ ] Configure GPU passthrough on Proxmox host (IOMMU, VFIO, nouveau blacklist)
- [ ] Pass RTX 2060 to K8s node VM
- [ ] Install NVIDIA drivers + nvidia-container-toolkit in guest VM
- [ ] Increase node RAM for Wave 5 services
- [ ] Enable `nvidia_device_plugin_enabled = true` after GPU passthrough
- [ ] Enable `ollama_gpu_enabled = true` and `comfyui_gpu_enabled = true` after device plugin
