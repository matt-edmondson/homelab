# Homelab Migration Prioritization Design

## Context

This project migrates services currently running as Proxmox LXC containers and VMs into the existing Kubernetes cluster managed by Terraform and Helm.

### Current Infrastructure

**Proxmox Host (pvei5):** Intel i5-10400F (6C/12T), 64GB RAM, NVIDIA RTX 2060 (nouveau, no passthrough), Proxmox 8.2.7

**K8s Cluster:** 3 VMs (k8s01: 4GB/100G, k8s02: 4GB/200G, k8s03: 4GB/200G)

**NAS:** Synology at 192.168.0.148, NFS exports `/volume2/media` and `/volume2/downloads` (35T)

**Already in K8s:** Traefik (ingress + TLS), Longhorn (storage), kube-prometheus-stack (monitoring), BaGet, Kubernetes Dashboard, Flannel (CNI), kube-vip (LoadBalancer), static sites, Azure DNS

### Existing Proxmox Services to Migrate

| VMID | Name | Type | Actual RAM Usage | Key Config |
|------|------|------|-----------------|------------|
| 101 | notifiarr | LXC | 80MB | notifiarr.service |
| 102 | postfix | LXC | 46MB | Virtual domains: ktsu.dev, ktsu.io, matthewedmondson.com → gmail |
| 103 | nginx/OpenResty | LXC | 168MB | Reverse proxy (being replaced by Traefik), auto-SSL |
| 105 | squid | LXC | 37MB | Currently idle/minimal |
| 107 | mirror | LXC | 640MB | apt-mirror (jammy/noble/raspbian), apt-cacher-ng |
| 108 | influx | LXC | 400MB | InfluxDB v2 |
| 109 | emby | LXC | 921MB | NFS: /volume2/media, port 8096 |
| 110 | prowlarr | LXC | 332MB | Port 9696, forms auth |
| 111 | radarr | LXC | 875MB | Port 7878, NFS: media + downloads |
| 112 | sonarr | LXC | 441MB | Port 8989, NFS: media + downloads |
| 113 | qbit | VM | 1.6GB | Port 8080, 800G disk |
| 114 | pihole | LXC | 214MB | DNS server |

### Not Currently Running (New Deployments)

- CrowdSec + Traefik Bouncer
- Traefik GitHub OAuth
- n8n
- Bazarr, Jackett, Huntarr, Cleanuparr, SABnzbd, Flaresolverr
- ollama, qdrant, chromadb, comfyui

## Design Decisions

1. **NFS access:** NFS CSI driver for dynamic PV provisioning from the Synology NAS
2. **Resource limits:** Right-sized based on actual usage (not the over-allocated LXC values)
3. **Migration pattern:** Deploy in K8s → verify → update DNS/routing → decommission LXC
4. **Per-service Terraform pattern:** New `.tf` file + IngressRoute in ingress.tf + DNS A record in dns.tf

## Wave Ordering

### Wave 0: NFS CSI Driver (prerequisite for media stack)

Deploy the NFS CSI driver to enable K8s pods to mount NAS shares. This is required before any service that needs `/volume2/media` or `/volume2/downloads`.

**Components:**
- nfs-subdir-external-provisioner or csi-driver-nfs Helm chart
- StorageClass for NFS-backed PVs
- Test PVC to validate connectivity to 192.168.0.148

**New file:** `nfs.tf`

### Wave 1: Security & Auth (new deployments)

**CrowdSec** — Intrusion detection using community threat intelligence.
- DaemonSet on each K8s node
- CrowdSec Local API (LAPI) as a Deployment
- Longhorn PVC for decision database
- Resource estimate: ~128MB RAM

**Traefik Bouncer** — Middleware plugin that queries CrowdSec LAPI to block malicious IPs at the Traefik level.
- Installed as a Traefik plugin or sidecar
- Configured as a Traefik Middleware CRD applied to all IngressRoutes

**Traefik GitHub OAuth** — ForwardAuth middleware using oauth2-proxy or traefik-forward-auth with GitHub provider.
- Replaces basic auth for all protected routes
- Deployment + ClusterIP Service
- Traefik ForwardAuth Middleware CRD
- Resource estimate: ~64MB RAM

**Outcome:** Every subsequent service is protected from day one.

**New files:** `crowdsec.tf`, `oauth.tf`
**Modified files:** `ingress.tf` (add CrowdSec + OAuth middleware to routes)

### Wave 2: Automation & Infrastructure (mix of migration + new)

**n8n** (new) — Workflow automation platform.
- Deployment with Longhorn PVC (SQLite mode)
- ClusterIP Service + IngressRoute
- Resource estimate: ~256MB RAM

**postfix** (migrate from LXC 102) — Outbound SMTP relay.
- Deployment with ConfigMap for main.cf and virtual alias maps
- Domains: ktsu.dev, ktsu.io, matthewedmondson.com → gmail
- ClusterIP Service (port 25/587)
- Resource estimate: ~64MB RAM

**squid** (migrate from LXC 105) — Caching HTTP proxy.
- Deployment with ConfigMap for squid.conf
- Longhorn PVC for cache
- ClusterIP Service
- Resource estimate: ~128MB RAM
- Note: Currently appears idle; consider whether this is still needed

**New files:** `n8n.tf`, `postfix.tf`, `squid.tf`

### Wave 3: Media Stack Core (migrate from LXCs)

All media services mount NFS volumes from the NAS via the NFS CSI driver (Wave 0).

**prowlarr** (migrate from LXC 110) — Indexer aggregation.
- Deployment, Longhorn PVC for config/DB
- Port 9696, ClusterIP Service + IngressRoute
- Resource limits: 512MB RAM
- Migrate: Export config.xml, indexer settings

**sonarr** (migrate from LXC 112) — TV show management.
- Deployment, Longhorn PVC for config/DB, NFS PVC for media + downloads
- Port 8989, ClusterIP Service + IngressRoute
- Resource limits: 1GB RAM
- Migrate: Export config.xml, quality profiles, download client settings

**radarr** (migrate from LXC 111) — Movie management.
- Deployment, Longhorn PVC for config/DB, NFS PVC for media + downloads
- Port 7878, ClusterIP Service + IngressRoute
- Resource limits: 1GB RAM
- Migrate: Export config.xml, quality profiles, download client settings

**qbittorrent** (migrate from VM 113) — BitTorrent client.
- Deployment, Longhorn PVC for config, NFS PVC for downloads
- Port 8080 (web UI), ClusterIP Service + IngressRoute
- Resource limits: 2GB RAM
- **VPN requirement:** Runs full-time through Private Internet Access (PIA) VPN tunnel
- VPN approach: Use a sidecar container (e.g. gluetun) that establishes the PIA WireGuard/OpenVPN tunnel, and route all qbittorrent traffic through it. The web UI is still accessible via Traefik (routed through the pod's network namespace). Alternatively, use a dedicated VPN gateway pod.
- Note: Currently a full VM with 800G disk; in K8s, downloads go directly to NFS

**emby** (migrate from LXC 109) — Media server.
- Deployment, Longhorn PVC for config/metadata, NFS PVC for media library
- Port 8096/8920, ClusterIP Service + IngressRoute
- Resource limits: 1.5GB RAM
- Migrate: Backup /var/lib/emby (config, metadata, user data)

**New files:** `prowlarr.tf`, `sonarr.tf`, `radarr.tf`, `qbittorrent.tf`, `emby.tf`

### Wave 4: Media Stack Extensions (mostly new deployments)

**Bazarr** — Subtitle management (integrates with sonarr/radarr).
- Resource estimate: ~256MB RAM

**Jackett** — Additional indexer support.
- Resource estimate: ~256MB RAM

**Huntarr** — Missing media hunter.
- Resource estimate: ~128MB RAM

**Cleanuparr** — Library cleanup automation.
- Resource estimate: ~128MB RAM

**SABnzbd** — Usenet download client.
- Resource estimate: ~512MB RAM, NFS PVC for downloads

**notifiarr** (migrate from LXC 101) — Rich notifications for arr stack.
- Resource estimate: ~128MB RAM
- Migrate: Export config

**Flaresolverr** — CAPTCHA/Cloudflare bypass proxy (headless browser).
- Resource estimate: ~512MB RAM (runs Chromium)

**New files:** `bazarr.tf`, `jackett.tf`, `huntarr.tf`, `cleanuparr.tf`, `sabnzbd.tf`, `notifiarr.tf`, `flaresolverr.tf`

### Wave 5: AI/ML Stack (new deployments, requires GPU passthrough)

**Prerequisites:**
- Enable IOMMU on Proxmox host (kernel cmdline: `intel_iommu=on iommu=pt`)
- Blacklist nouveau, configure VFIO for RTX 2060
- Pass GPU through to one K8s node VM
- Install NVIDIA device plugin in K8s

**ollama** — Local LLM inference.
- Deployment with GPU resource request
- Longhorn PVC for model storage
- Resource estimate: ~4GB RAM + GPU
- Node selector for GPU node

**qdrant** — Vector database.
- Deployment + Longhorn PVC
- Resource estimate: ~512MB RAM

**chromadb** — Vector database (alternative/complement to qdrant).
- Deployment + Longhorn PVC
- Resource estimate: ~512MB RAM

**comfyui** — Stable Diffusion image generation UI.
- Deployment with GPU resource request
- Longhorn PVC for models/outputs
- Resource estimate: ~4GB RAM + GPU
- Node selector for GPU node

**New files:** `nvidia.tf` (GPU setup), `ollama.tf`, `qdrant.tf`, `chromadb.tf`, `comfyui.tf`

## Migration Checklist Per Service

1. Deploy K8s resources via Terraform
2. Verify service is running and accessible via Traefik
3. Migrate data/config from LXC (if applicable)
4. Update DNS to point to Traefik instead of LXC IP
5. Validate end-to-end functionality
6. Stop LXC container
7. Monitor for issues (keep LXC available for rollback)
8. After stabilization, delete LXC

## Resource Budget

| Wave | Services | Estimated Total RAM |
|------|----------|-------------------|
| 0 | NFS CSI | ~64MB |
| 1 | CrowdSec, Bouncer, OAuth | ~256MB |
| 2 | n8n, postfix, squid | ~448MB |
| 3 | prowlarr, sonarr, radarr, qbit, emby | ~6GB |
| 4 | Bazarr, Jackett, Huntarr, Cleanuparr, SABnzbd, notifiarr, Flaresolverr | ~1.9GB |
| 5 | ollama, qdrant, chromadb, comfyui | ~9GB + GPU |
| **Total** | | **~17.7GB** |

Current K8s cluster has 12GB RAM across 3 nodes. After decommissioning LXCs, node RAM can be increased. Waves 0-2 fit in current capacity. Wave 3 will likely require increasing at least one node's RAM.

## Services NOT Being Migrated to K8s

These should be discussed separately:
- **pihole (LXC 114)** — DNS server; may stay as LXC since it serves the whole network
- **mirror (LXC 107)** — apt-mirror/apt-cacher-ng; niche use case, low priority
- **influx (LXC 108)** — InfluxDB; K8s already has Prometheus via kube-prometheus-stack
- **OpenResty (LXC 103)** — Being replaced by Traefik; decommission after migration
