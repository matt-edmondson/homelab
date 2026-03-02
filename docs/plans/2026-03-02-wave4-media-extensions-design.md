# Wave 4: Media Stack Extensions Design

## Context

Wave 3 deployed the core media stack (Prowlarr, Sonarr, Radarr, qBittorrent, Emby). Wave 4 adds supporting services that extend the media stack with subtitle management, additional indexers, missing media hunting, library cleanup, Usenet downloads, rich notifications, and CAPTCHA solving.

### Prerequisites

- Wave 0: NFS CSI driver (for Bazarr and SABnzbd NFS mounts)
- Wave 1: CrowdSec + OAuth (for ingress middleware)
- Wave 3: Core media stack (Prowlarr, Sonarr, Radarr — APIs that Wave 4 services connect to)

## Design Decisions

1. **Same Terraform pattern as Wave 3:** One `.tf` file per service with variables, namespace, PVC(s), Deployment, Service, outputs. linuxserver.io images where available.
2. **OAuth on all exposed services:** All IngressRoutes get rate-limit + crowdsec-bouncer + oauth-forward-auth middleware.
3. **Flaresolverr is internal-only:** No IngressRoute or DNS record. Prowlarr connects via cluster DNS.
4. **Notifiarr config from LXC 101:** Config file managed as a sensitive Terraform variable, stored in a Kubernetes Secret, mounted at `/config/notifiarr.conf`.
5. **SABnzbd configured post-deploy:** Empty config — Usenet servers configured via web UI after deployment.
6. **Bazarr needs NFS media mount:** Writes subtitle files directly alongside video files on the NAS.
7. **SABnzbd needs NFS downloads mount:** Writes completed Usenet downloads to the NAS for Sonarr/Radarr to import.

## Services

| Service | Image | Port | Longhorn PVC | NFS Mount | IngressRoute | DNS Subdomain | Est. RAM |
|---------|-------|------|-------------|-----------|--------------|---------------|----------|
| Bazarr | linuxserver/bazarr | 6767 | 1Gi (config) | media (RW) | Yes | bazarr | 256MB |
| Jackett | linuxserver/jackett | 9117 | 1Gi (config) | None | Yes | jackett | 256MB |
| Huntarr | huntarr/huntarr | 9705 | 512Mi (config) | None | Yes | huntarr | 128MB |
| Cleanuparr | flmedicmento/cleanuparr | 80 | None | None | Yes | cleanuparr | 128MB |
| SABnzbd | linuxserver/sabnzbd | 8080 | 1Gi (config) | downloads (RW) | Yes | sabnzbd | 512MB |
| Notifiarr | golift/notifiarr | 5454 | 1Gi (config) | None | Yes | notifiarr | 128MB |
| Flaresolverr | ghcr.io/flaresolverr/flaresolverr | 8191 | None | None | No (internal) | None | 512MB |

**Total estimated RAM: ~1.9GB**

## Integration Points

- **Bazarr** → Sonarr API + Radarr API (subtitle management) + NFS media filesystem
- **Jackett** → Prowlarr (additional indexer support)
- **Huntarr** → Sonarr API + Radarr API (missing media detection)
- **Cleanuparr** → Sonarr API + Radarr API (library cleanup)
- **SABnzbd** → Sonarr/Radarr configure it as a download client + NFS downloads filesystem
- **Notifiarr** → Receives webhooks from arr services → sends rich notifications
- **Flaresolverr** → Prowlarr (CAPTCHA/Cloudflare bypass via `flaresolverr-service.flaresolverr.svc.cluster.local:8191`)

## Resource Budget

Current cluster: 12GB RAM across 3 nodes.
Waves 0-3 estimated: ~6.8GB.
Wave 4 adds: ~1.9GB.
Running total after Wave 4: ~8.7GB (fits within current capacity).

## Files to Create/Modify

**New files:** `bazarr.tf`, `jackett.tf`, `huntarr.tf`, `cleanuparr.tf`, `sabnzbd.tf`, `notifiarr.tf`, `flaresolverr.tf`

**Modified files:**
- `ingress.tf` — Add IngressRoutes for 6 services (all except Flaresolverr)
- `dns.tf` — Add 6 DNS subdomain records
- `Makefile` — Add plan/apply targets for each service
- `terraform.tfvars.example` — Add Wave 4 variable examples
- `CLAUDE.md` — Update file organization and commands
