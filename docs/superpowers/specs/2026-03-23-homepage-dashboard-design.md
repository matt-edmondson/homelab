# Homepage Dashboard Design Spec

## Overview

Deploy [Homepage](https://gethomepage.dev/) as the application portal for the homelab cluster. Homepage is a modern, widget-rich dashboard that provides categorized links to all services with live API-driven widgets showing download status, media counts, storage usage, and system metrics.

## Goals

- Single entry point to discover and access all homelab services
- Live status widgets for key services (Arr suite, download clients, monitoring, storage)
- Fully declarative configuration via Terraform ConfigMaps — no persistent state
- Consistent with existing deployment patterns (feature flag, namespace isolation, Traefik ingress, OAuth)

## Architecture

### New File: `homepage.tf`

Following the one-concern-per-file pattern, all Homepage resources live in a single file:

- `kubernetes_namespace.homepage`
- `kubernetes_service_account.homepage` (for Kubernetes widget RBAC)
- `kubernetes_cluster_role.homepage` (read-only access to nodes, pods, etc.)
- `kubernetes_cluster_role_binding.homepage`
- `kubernetes_deployment.homepage`
- `kubernetes_service.homepage` (ClusterIP, port 3000)
- `kubernetes_config_map.homepage_config` (Homepage YAML files: settings, services, widgets)
- `kubernetes_secret.homepage_secrets` (API keys for widget integrations)
- `output "homepage_info"` (namespace, URL, kubectl commands — matches existing `*_info` pattern)

### Modified Files

- **`ingress.tf`** — Add IngressRoute for `homepage.{domain}` with middleware chain: rate-limit, crowdsec-bouncer, oauth-forward-auth (matching existing order)
- **`dns.tf`** — Add `var.homepage_enabled ? { homepage = "homepage" } : {}` to the `local.dns_records` merge block
- **`Makefile`** — Add `plan-homepage` / `apply-homepage` targets (including namespace, RBAC, configmap, secret, deployment, service); add homepage resources to `apply-applications` target; add to `.PHONY` declaration
- **`terraform.tfvars.example`** — Add `homepage_enabled` flag and API key placeholders

### Traffic Flow

```
User → Traefik (443) → Host(`homepage.{domain}`)
     → rate-limit → crowdsec-bouncer → oauth-forward-auth
     → homepage-service.homepage.svc.cluster.local:3000
```

## Configuration

### Feature Flag

```hcl
variable "homepage_enabled" {
  description = "Enable Homepage dashboard"
  type        = bool
  default     = false
}
```

All resources gated with `count = var.homepage_enabled ? 1 : 0`.

### Variables

```hcl
variable "homepage_image" {
  description = "Homepage container image"
  type        = string
  default     = "ghcr.io/gethomepage/homepage"
}

variable "homepage_image_tag" {
  description = "Homepage container image tag"
  type        = string
  default     = "latest"
}

variable "homepage_memory_request" {
  description = "Memory request for Homepage"
  type        = string
  default     = "128Mi"
}
variable "homepage_memory_limit" {
  description = "Memory limit for Homepage"
  type        = string
  default     = "256Mi"
}
variable "homepage_cpu_request" {
  description = "CPU request for Homepage"
  type        = string
  default     = "50m"
}
variable "homepage_cpu_limit" {
  description = "CPU limit for Homepage"
  type        = string
  default     = "200m"
}
```

Image constructed as `"${var.homepage_image}:${var.homepage_image_tag}"` in the deployment, matching the `*_image` / `*_image_tag` pattern used by other services.

### API Key Variables

New variables for widget integrations. These are all new — only `baget_api_key` exists today. All follow the same pattern with `type`, `description`, `default`, and `sensitive`:

```hcl
variable "sonarr_api_key" {
  description = "Sonarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "radarr_api_key" {
  description = "Radarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "prowlarr_api_key" {
  description = "Prowlarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "bazarr_api_key" {
  description = "Bazarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "jackett_api_key" {
  description = "Jackett API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "huntarr_api_key" {
  description = "Huntarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "sabnzbd_api_key" {
  description = "SABnzbd API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "qbittorrent_username" {
  description = "qBittorrent username for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "qbittorrent_password" {
  description = "qBittorrent password for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
variable "emby_api_key" {
  description = "Emby API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
```

### Container Configuration

- **Image**: `"${var.homepage_image}:${var.homepage_image_tag}"`
- **Port**: 3000
- **Service account**: `homepage` (with cluster-reader RBAC for Kubernetes widget)
- **No persistent storage** — all config mounted from ConfigMaps
- **`depends_on`**: `kubernetes_config_map.homepage_config`, `kubernetes_secret.homepage_secrets`
- **Volume mounts**:
  - ConfigMap `homepage-config` mounted at `/app/config/` with keys: `settings.yaml`, `services.yaml`, `widgets.yaml`
  - Secret `homepage-secrets` mounted as environment variables

### RBAC (for Kubernetes Widget)

Homepage needs read-only cluster access to show node/pod counts and resource usage:

```hcl
kubernetes_service_account.homepage  # in namespace "homepage"
kubernetes_cluster_role.homepage     # rules: get/list/watch on nodes, pods, namespaces
kubernetes_cluster_role_binding.homepage  # binds role to service account
```

### Health Probes

```hcl
liveness_probe {
  http_get { path = "/api/healthcheck" port = 3000 }
  initial_delay_seconds = 15
  period_seconds        = 30
  timeout_seconds       = 5
  failure_threshold     = 3
}

readiness_probe {
  http_get { path = "/api/healthcheck" port = 3000 }
  initial_delay_seconds = 10
  period_seconds        = 15
  timeout_seconds       = 5
  failure_threshold     = 3
}
```

## Service Groups & Widgets

Homepage config (`services.yaml`) organized into 6 groups. Each group only includes services whose `*_enabled` flag is true. Use Terraform's `yamlencode()` to dynamically build the services list.

### Media Management
| Service | Widget Type | Data Shown |
|---------|------------|------------|
| Sonarr | `sonarr` | Series count, upcoming, queue |
| Radarr | `radarr` | Movie count, upcoming, queue |
| Bazarr | `bazarr` | Subtitles wanted/missing |
| Prowlarr | `prowlarr` | Indexer count, recent grabs |
| Jackett | — | Link only (no native widget) |
| Huntarr | — | Link only |
| Cleanuparr | — | Link only |
| Notifiarr | — | Link only |

### Downloads
| Service | Widget Type | Data Shown |
|---------|------------|------------|
| qBittorrent | `qbittorrent` | Active downloads, speed, queue |
| SABnzbd | `sabnzbd` | Active downloads, speed, queue |

### Media Streaming
| Service | Widget Type | Data Shown |
|---------|------------|------------|
| Emby | `emby` | Active streams, library count |

### Monitoring
| Service | Widget Type | Data Shown |
|---------|------------|------------|
| Grafana | `grafana` | Link + status |
| Prometheus | `prometheus` | Targets up/down |
| AlertManager | — | Link only |

### AI / ML
| Service | Widget Type | Data Shown |
|---------|------------|------------|
| Ollama | — | Link only |
| Qdrant | — | Link only |
| ChromaDB | — | Link only |
| ComfyUI | — | Link only |

### Infrastructure
| Service | Widget Type | Data Shown |
|---------|------------|------------|
| Traefik | `traefik` | Routers, services, middleware counts |
| Longhorn | `longhorn` | Storage usage, volume health |
| Headlamp | — | Link only |
| BaGet | — | Link only |
| n8n | — | Link only |

### System Widgets (`widgets.yaml`)

Top-of-page system info widgets:

- **Kubernetes** — node count, pod count, CPU/memory usage
- **Search** — optional search bar (provider configurable)

### Settings (`settings.yaml`)

```yaml
title: Homelab
background: ""
theme: dark
color: slate
headerStyle: clean
layout:
  Media Management:
    style: row
    columns: 4
  Downloads:
    style: row
    columns: 2
  Media Streaming:
    style: row
    columns: 1
  Monitoring:
    style: row
    columns: 3
  AI / ML:
    style: row
    columns: 4
  Infrastructure:
    style: row
    columns: 3
```

## Conditional Service Inclusion

The services ConfigMap is built dynamically using Terraform locals and `yamlencode()`. Pattern:

```hcl
locals {
  homepage_media_services = concat(
    var.sonarr_enabled ? [{
      "Sonarr" = {
        href        = "https://sonarr.${var.traefik_domain}"
        icon        = "sonarr"
        description = "TV Shows"
        widget = {
          type = "sonarr"
          url  = "http://sonarr-service.sonarr.svc.cluster.local:8989"
          key  = var.sonarr_api_key
        }
      }
    }] : [],
    var.radarr_enabled ? [{
      "Radarr" = { ... }
    }] : [],
    # ... etc
  )

  homepage_services_yaml = yamlencode([
    { "Media Management" = local.homepage_media_services },
    { "Downloads"        = local.homepage_download_services },
    # ... etc
  ])
}
```

Empty groups (where no services are enabled) should be filtered out using a conditional check (e.g., `length(local.homepage_media_services) > 0`) so they don't appear as blank sections on the dashboard.

## Auth & Security

Same middleware chain as other protected services (in established order):
1. Rate limiting (default 100 req/s average, 200 burst)
2. CrowdSec bouncer (IP threat detection)
3. OAuth2 proxy (GitHub SSO) — when `var.oauth_enabled` is true

## Deployment

### Makefile Targets

```makefile
plan-homepage:
    terraform plan \
        -target=kubernetes_namespace.homepage \
        -target=kubernetes_service_account.homepage \
        -target=kubernetes_cluster_role.homepage \
        -target=kubernetes_cluster_role_binding.homepage \
        -target=kubernetes_config_map.homepage_config \
        -target=kubernetes_secret.homepage_secrets \
        -target=kubernetes_deployment.homepage \
        -target=kubernetes_service.homepage

apply-homepage:
    terraform apply -auto-approve \
        -target=kubernetes_namespace.homepage \
        -target=kubernetes_service_account.homepage \
        -target=kubernetes_cluster_role.homepage \
        -target=kubernetes_cluster_role_binding.homepage \
        -target=kubernetes_config_map.homepage_config \
        -target=kubernetes_secret.homepage_secrets \
        -target=kubernetes_deployment.homepage \
        -target=kubernetes_service.homepage
```

Also add homepage targets to `apply-applications` aggregate target and `plan-homepage apply-homepage` to `.PHONY`.

### Deployment Order

No special ordering needed. Homepage depends on:
- Traefik CRDs existing (for IngressRoute) — already handled by `apply-traefik` → `apply-ingress` ordering
- Backend services running (for widgets) — widgets gracefully degrade if a service is unavailable

## Testing

After deployment:
1. `kubectl get pods -n homepage` — verify Running status
2. `curl -s https://homepage.{domain}/api/healthcheck` — verify 200 response
3. Open `https://homepage.{domain}` — verify all enabled service groups appear
4. Verify widgets show live data for services with configured API keys
