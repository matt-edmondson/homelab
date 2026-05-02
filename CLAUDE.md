# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Kubernetes homelab infrastructure-as-code project managed entirely with Terraform and Helm. All infrastructure code lives in the `terraform/` directory.

## Working in This Repository

All commands should be run from the `terraform/` directory where the Makefile lives.

## Common Commands

```bash
cd terraform

# Initialize Terraform
make init

# Validate configuration
make validate

# Format Terraform files
make format

# Plan full deployment
make plan

# Apply full deployment
make deploy

# Plan/apply a single component
make plan-networking
make plan-storage
make plan-monitoring
make plan-applications
make apply-networking
make apply-storage
make apply-monitoring
make apply-applications
make plan-traefik / make apply-traefik
make plan-ingress / make apply-ingress
make plan-static-sites / make apply-static-sites

# View status of deployed components
make status
make status-all-components

# Debug specific components
make debug-networking
make debug-storage
make debug-monitoring
make debug-applications

# Generate secure secrets for terraform.tfvars
make generate-secrets

# Destroy infrastructure
make destroy

# Full cleanup including Longhorn finalizer removal (use when stuck resources)
make force-clean
```

## Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` and populate values. The `.gitignore` excludes `*.tfvars` so secrets are never committed.

## Architecture

### File Organization (One Concern Per File)

- [common.tf](terraform/common.tf) — Provider configuration (Kubernetes `~> 2.38`, Helm `~> 3.0.2`), Metrics Server Helm release, kube-proxy RBAC, CoreDNS config (IPv6 AAAA filtering), shared outputs and variables
- [flannel.tf](terraform/flannel.tf) — Flannel CNI DaemonSet, RBAC, and ConfigMap (default pod CIDR: `10.244.0.0/16`, backend: VXLAN)
- [kube-vip.tf](terraform/kube-vip.tf) — kube-vip DaemonSet for ARP-based LoadBalancer IP assignment via router DHCP
- [longhorn.tf](terraform/longhorn.tf) — Longhorn distributed block storage via Helm (default chart version: `1.9.1`, default replicas: 2), plus a ClusterIP service for the Longhorn UI
- [monitoring.tf](terraform/monitoring.tf) — kube-prometheus-stack (Prometheus, Grafana, AlertManager) via Helm (default chart version: `76.3.0`); all use Longhorn storage
- [baget.tf](terraform/baget.tf) — BaGet NuGet package server (Deployment, PVC on Longhorn, ClusterIP Service, Secret, ConfigMap)
- [kubernetes-dashboard.tf](terraform/kubernetes-dashboard.tf) — Kubernetes Dashboard via Helm (default chart version: `7.13.0`) with admin ServiceAccount and ClusterIP service
- [devtron.tf](terraform/devtron.tf) — Devtron Kubernetes dashboard via Helm (dashboard-only, no CI/CD, default chart version: `0.23.2`, bundled Postgres on Longhorn)
- [traefik.tf](terraform/traefik.tf) — Traefik reverse proxy via Helm (ACME Let's Encrypt, Azure DNS challenge, Longhorn persistence)
- [ingress.tf](terraform/ingress.tf) — IngressRoute and Middleware CRD resources for all services
- [debug-ingress.tf](terraform/debug-ingress.tf) — Traefik-independent NodePort escape-hatch services for Headlamp and Devtron (reachable on `<node-ip>:30242` / `:30243`) so the debug dashboards stay accessible when Traefik is broken
- [static-sites.tf](terraform/static-sites.tf) — Nginx static site hosting (git-cloned content, auto-pull sidecar, multi-domain vhosts)
- [dns.tf](terraform/dns.tf) — Azure DNS A records for each service subdomain (uses azurerm provider)
- [bazarr.tf](terraform/bazarr.tf) — Bazarr subtitle management (Longhorn config PVC + NFS media mount, linuxserver/bazarr)
- [jackett.tf](terraform/jackett.tf) — Jackett indexer support (Longhorn config PVC, linuxserver/jackett)
- [cleanuparr.tf](terraform/cleanuparr.tf) — Cleanuparr library cleanup (stateless, flmedicmento/cleanuparr)
- [sabnzbd.tf](terraform/sabnzbd.tf) — SABnzbd Usenet client (Longhorn config PVC + NFS downloads mount, linuxserver/sabnzbd)
- [notifiarr.tf](terraform/notifiarr.tf) — Notifiarr rich notifications (Longhorn config PVC + config Secret, golift/notifiarr)
- [flaresolverr.tf](terraform/flaresolverr.tf) — Flaresolverr CAPTCHA solver (stateless, internal-only — no IngressRoute/DNS)
- [github-runners.tf](terraform/github-runners.tf) — GitHub Actions Runner Controller (ARC) — controller + two `gha-runner-scale-set` Helm releases (ktsu-dev org-scoped, matt-edmondson/CardApp repo-scoped), DinD sidecar, GitHub App auth, no ingress
- [nvidia.tf](terraform/nvidia.tf) — NVIDIA device plugin via Helm (GPU resource scheduling, conditional on `nvidia_device_plugin_enabled`)
- [ollama.tf](terraform/ollama.tf) — Ollama LLM inference (Longhorn config PVC + NFS models mount, GPU nodeSelector, ollama/ollama)
- [qdrant.tf](terraform/qdrant.tf) — Qdrant vector database (Longhorn data PVC, qdrant/qdrant)
- [chromadb.tf](terraform/chromadb.tf) — ChromaDB vector database (Longhorn data PVC, chromadb/chroma)
- [comfyui.tf](terraform/comfyui.tf) — ComfyUI image generation (Longhorn config PVC + NFS models mount, GPU nodeSelector, yanwk/comfyui-boot)
- [keel.tf](terraform/keel.tf) — Keel image auto-update controller via Helm (cluster-wide, polling mode); Deployments opt in via `keel.sh/policy=force` + `keel.sh/trigger=poll` annotations and Keel reads each Deployment's `imagePullSecrets` for registry auth

### Networking Model

Traefik serves as the single ingress entry point. It receives a LoadBalancer IP from kube-vip and routes traffic to backend ClusterIP services by hostname via IngressRoute CRDs.

- All services are ClusterIP; external access is through Traefik only
- kube-vip runs as a DaemonSet in `kube-system`, configured in ARP mode (`--arp` flag) — only Traefik gets a LoadBalancer IP
- Traefik provides automatic TLS via Let's Encrypt ACME (Azure DNS challenge) with wildcard certificates
- Flannel handles pod-to-pod networking (VXLAN backend)

### Storage Model

Longhorn provides distributed block storage. All PVCs reference the `longhorn` StorageClass, which is looked up via a data source after Helm installs it. Monitoring stack (Prometheus, Grafana, AlertManager) and BaGet all store data on Longhorn volumes.

### Key Patterns

- **Traefik CRD ordering** — Traefik Helm chart must be applied before IngressRoute resources (`make apply-traefik` then `make apply-ingress`). The CRDs don't exist until the Helm chart is installed.
- **Common labels** default to `managed-by = "terraform"` and `environment = "homelab"` (defined in `common.tf`, configurable via `var.common_labels`)
- **Longhorn startup** has special handling to work around a webhook circular dependency: extended manager timeout (300s), relaxed readiness probe (10 failures allowed), and webhooks set to `failurePolicy = "Ignore"`
- **Longhorn stuck resources** — use `make force-clean` which handles finalizer removal and force-deletion
- **Metrics Server** is optional (`var.metrics_server_enabled`, default `true`) and Longhorn depends on it being ready before installing
