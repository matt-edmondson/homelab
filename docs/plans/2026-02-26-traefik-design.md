# Traefik Reverse Proxy Design

## Overview

Deploy Traefik as the central reverse proxy for all Kubernetes homelab services, replacing individual LoadBalancer services with hostname-based routing through a single entry point.

## Goals

- Single LoadBalancer IP (via kube-vip DHCP) as the entry point for all HTTP/HTTPS traffic
- Hostname-based routing (direct subdomains: `grafana.<domain>`, `baget.<domain>`, etc.)
- Automatic TLS via Let's Encrypt built-in ACME with Azure DNS challenge
- Middleware: HTTPS redirect, basic auth, rate limiting
- Traefik dashboard exposed with basic auth protection
- Migrate all existing LoadBalancer services to ClusterIP, routed through Traefik

## Architecture

### Approach: `traefik.tf` + `ingress.tf`

Traefik infrastructure lives in `traefik.tf`. All IngressRoute resources and middleware definitions are consolidated in `ingress.tf`. Existing service files are updated to use ClusterIP instead of LoadBalancer.

### Dependency Chain

```
flannel -> kube-vip -> metrics-server -> longhorn -> traefik -> ingress routes
                                                                     |
                                                          monitoring + applications
```

## File: `traefik.tf` — Core Infrastructure

Contains:
- `traefik` namespace
- Traefik Helm release (official `traefik/traefik` chart)
- Single LoadBalancer service via kube-vip DHCP
- ACME certificate resolver: Let's Encrypt + Azure DNS challenge
- Azure DNS credentials as Kubernetes Secret (from `terraform.tfvars`)
- Persistent volume (Longhorn) for ACME certificate storage
- Traefik dashboard enabled (exposed via `ingress.tf`)

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `traefik_chart_version` | Helm chart version | Latest stable |
| `traefik_domain` | Base domain for services | Required |
| `traefik_acme_email` | Let's Encrypt registration email | Required |
| `azure_dns_client_id` | Azure DNS SP client ID | Required |
| `azure_dns_client_secret` | Azure DNS SP client secret | Required (sensitive) |
| `azure_dns_tenant_id` | Azure AD tenant ID | Required |
| `azure_dns_subscription_id` | Azure subscription ID | Required |
| `azure_dns_resource_group` | Azure DNS zone resource group | Required |
| `traefik_dashboard_password` | Basic auth password for dashboard | Required (sensitive) |
| `traefik_log_level` | Traefik log level | `ERROR` |
| `traefik_acme_storage_size` | PVC size for ACME certs | `1Gi` |

## File: `ingress.tf` — Routing & Middleware

### Shared Middleware

1. **`https-redirect`** — Redirects HTTP to HTTPS
2. **`rate-limit`** — Default rate limiting (configurable average/burst)
3. **`basic-auth`** — Username/password protection via Kubernetes Secret

### Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `rate_limit_average` | Rate limit requests/second | `100` |
| `rate_limit_burst` | Rate limit burst | `200` |
| `basic_auth_users` | Map of username to password | Required (sensitive) |

### IngressRoute Table

| Service | Hostname | Middleware | Backend Port | TLS |
|---------|----------|------------|-------------|-----|
| Grafana | `grafana.<domain>` | https-redirect, rate-limit | 80 | Yes |
| Prometheus | `prometheus.<domain>` | https-redirect, rate-limit, basic-auth | 9090 | Yes |
| AlertManager | `alertmanager.<domain>` | https-redirect, rate-limit, basic-auth | 9093 | Yes |
| BaGet | `baget.<domain>` | https-redirect, rate-limit | 80 | Yes |
| Longhorn UI | `longhorn.<domain>` | https-redirect, rate-limit, basic-auth | 80 | Yes |
| K8s Dashboard | `dashboard.<domain>` | https-redirect, rate-limit | 443 | Yes |
| Traefik Dashboard | `traefik.<domain>` | https-redirect, rate-limit, basic-auth | 9000 | Yes |

## Service Migration Changes

### `baget.tf`
- Change service type from `LoadBalancer` to `ClusterIP`
- Remove `load_balancer_ip` and kube-vip annotations
- Remove LoadBalancer IP output

### `monitoring.tf`
- Set Grafana service type to `ClusterIP` in Helm values
- Set Prometheus service type to `ClusterIP` in Helm values
- Set AlertManager service type to `ClusterIP` in Helm values

### `longhorn.tf`
- Change `kubernetes_service.longhorn_frontend` from `LoadBalancer` to `ClusterIP`
- Remove kube-vip annotations

### `kubernetes-dashboard.tf`
- Update Helm values to use `ClusterIP`
- Traefik handles TLS termination

### `common.tf` / outputs
- Add output for Traefik LoadBalancer IP (single entry point)
- Remove individual service LoadBalancer IP outputs

### `terraform.tfvars.example`
- Add all new Traefik and Azure DNS variables with placeholder values

## Makefile Integration

New targets added:
- `plan-traefik` / `apply-traefik` — Deploy Traefik Helm release
- `plan-ingress` / `apply-ingress` — Deploy IngressRoutes and middleware

Updated `make deploy` order:
1. `apply-networking` (flannel, kube-vip, metrics-server)
2. `apply-storage` (longhorn)
3. `apply-traefik` (Traefik Helm release)
4. `apply-ingress` (IngressRoutes and middleware)
5. `apply-monitoring` (monitoring services as ClusterIP)
6. `apply-applications` (baget, dashboard as ClusterIP)

## Bearer Token Auth

Handled at the application level (e.g. BaGet's built-in API key). No ForwardAuth service needed.

## TLS Strategy

- Let's Encrypt via Traefik built-in ACME
- Azure DNS challenge (no public port exposure needed)
- ACME certs persisted on Longhorn PVC
- Self-signed fallback if ACME fails (Traefik default behavior)
