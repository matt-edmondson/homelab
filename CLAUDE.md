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

- [common.tf](terraform/common.tf) — Provider configuration (Kubernetes `~> 2.38`, Helm `~> 3.0.2`), Metrics Server Helm release, kube-proxy RBAC, shared outputs and variables
- [flannel.tf](terraform/flannel.tf) — Flannel CNI DaemonSet, RBAC, and ConfigMap (default pod CIDR: `10.244.0.0/16`, backend: VXLAN)
- [kube-vip.tf](terraform/kube-vip.tf) — kube-vip DaemonSet for ARP-based LoadBalancer IP assignment via router DHCP
- [longhorn.tf](terraform/longhorn.tf) — Longhorn distributed block storage via Helm (default chart version: `1.9.1`, default replicas: 2), plus a LoadBalancer service for the Longhorn UI
- [monitoring.tf](terraform/monitoring.tf) — kube-prometheus-stack (Prometheus, Grafana, AlertManager) via Helm (default chart version: `76.3.0`); all use Longhorn storage
- [baget.tf](terraform/baget.tf) — BaGet NuGet package server (Deployment, PVC on Longhorn, LoadBalancer Service, Secret, ConfigMap)
- [kubernetes-dashboard.tf](terraform/kubernetes-dashboard.tf) — Kubernetes Dashboard via Helm (default chart version: `7.13.0`) with admin ServiceAccount and LoadBalancer service

### Networking Model

kube-vip handles all external service exposure:

- kube-vip runs as a DaemonSet in `kube-system`, configured in ARP mode (`--arp` flag)
- LoadBalancer services are assigned IPs dynamically from the router's DHCP pool — no fixed IP range is configured in Terraform
- Services trigger DHCP assignment by setting `load_balancer_ip = "0.0.0.0"` and using the `kube-vip.io/loadbalancerHostname` annotation
- Flannel handles pod-to-pod networking (VXLAN backend)

### Storage Model

Longhorn provides distributed block storage. All PVCs reference the `longhorn` StorageClass, which is looked up via a data source after Helm installs it. Monitoring stack (Prometheus, Grafana, AlertManager) and BaGet all store data on Longhorn volumes.

### Key Patterns

- **LoadBalancer services** all use `load_balancer_ip = "0.0.0.0"` to trigger kube-vip DHCP behavior, with `kube-vip.io/loadbalancerHostname` annotations for DNS hostname hints
- **Common labels** default to `managed-by = "terraform"` and `environment = "homelab"` (defined in `common.tf`, configurable via `var.common_labels`)
- **Longhorn startup** has special handling to work around a webhook circular dependency: extended manager timeout (300s), relaxed readiness probe (10 failures allowed), and webhooks set to `failurePolicy = "Ignore"`
- **Longhorn stuck resources** — use `make force-clean` which handles finalizer removal and force-deletion
- **Metrics Server** is optional (`var.metrics_server_enabled`, default `true`) and Longhorn depends on it being ready before installing
