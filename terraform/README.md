# Kubernetes Homelab Infrastructure with Terraform

This Terraform configuration sets up a complete Kubernetes homelab environment with the following components:

- **Flannel** - CNI plugin for pod networking (VXLAN backend)
- **kube-vip** - LoadBalancer IP assignment via ARP and router DHCP
- **Longhorn** - Distributed block storage
- **Prometheus & Grafana** - Complete monitoring and visualization stack
- **AlertManager** - Alert management (part of Prometheus stack)
- **Metrics Server** - Resource metrics for `kubectl top` and Horizontal Pod Autoscaler (HPA)
- **Baget** - NuGet package server
- **Kubernetes Dashboard** - Web UI for cluster management

## File Structure

The Terraform configuration is organized by concern into separate files:

```
terraform/
├── common.tf                 # Providers, shared variables, Metrics Server, kube-proxy RBAC
├── flannel.tf                # Flannel CNI DaemonSet and RBAC
├── kube-vip.tf               # kube-vip LoadBalancer DaemonSet and RBAC
├── longhorn.tf               # Longhorn distributed storage
├── monitoring.tf             # Prometheus, Grafana, and AlertManager
├── baget.tf                  # BaGet NuGet server
├── kubernetes-dashboard.tf   # Kubernetes Dashboard
├── terraform.tfvars.example  # Example configuration
└── Makefile                  # Automation helpers
```

## Architecture Overview

```
┌─────────────────┐         ┌──────────────────────────────┐
│  Home Router    │  DHCP   │ Kubernetes Cluster           │
│  (DHCP Server)  │◄────────┤                              │
│                 │         │  ┌─────────────────────────┐ │
└─────────────────┘         │  │ kube-vip (ARP mode)     │ │
                            │  │ DHCP IPs per service    │ │
                            │  └─────────────────────────┘ │
                            │                              │
                            │  ┌─────────────────────────┐ │
                            │  │ Applications            │ │
                            │  │ • Prometheus            │ │
                            │  │ • Grafana               │ │
                            │  │ • Baget                 │ │
                            │  │ • Longhorn UI           │ │
                            │  │ • Kubernetes Dashboard  │ │
                            │  └─────────────────────────┘ │
                            │                              │
                            │  ┌─────────────────────────┐ │
                            │  │ Longhorn Storage        │ │
                            │  │ Replicas: 2 (default)   │ │
                            │  └─────────────────────────┘ │
                            └──────────────────────────────┘
```

Each LoadBalancer service gets a DHCP-assigned IP from your router via kube-vip's ARP mode. Pin/reserve these IPs in your router's DHCP settings for stable addresses.

## Prerequisites

1. **Kubernetes Cluster** - A running Kubernetes cluster
2. **kubectl** - Configured to access your cluster
3. **Terraform** >= 1.0
4. **Helm** (Terraform manages Helm releases, but having the Helm CLI is helpful for debugging)

## Quick Start

### 1. Clone and Configure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### 2. Customize Configuration

Edit `terraform.tfvars` with your specific settings:

```hcl
kubeconfig_path        = "~/.kube/config"
kube_vip_interface     = "eth0"           # Network interface on your nodes

# Security - CHANGE THESE
baget_api_key          = "your-secure-api-key"
grafana_admin_password = "your-secure-password"
```

### 3. Generate Secure Keys

```bash
make generate-secrets
```

Or manually:

```bash
cat >> terraform.tfvars << EOF
baget_api_key          = "$(openssl rand -base64 32)"
grafana_admin_password = "$(openssl rand -base64 16)"
EOF
```

### 4. Deploy Infrastructure

```bash
make init
make deploy
```

## Post-Deployment

### Check Service Status

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Get LoadBalancer IPs assigned by kube-vip DHCP
kubectl get services --all-namespaces | grep LoadBalancer
```

### Access Applications

After deployment, get the DHCP-assigned LoadBalancer IPs:

```bash
kubectl get svc --all-namespaces | grep LoadBalancer
```

Then access:
- **Grafana**: `http://<grafana-lb-ip>` (admin / your-password)
- **Prometheus**: `http://<prometheus-lb-ip>:9090`
- **Longhorn UI**: `http://<longhorn-lb-ip>`
- **Baget**: `http://<baget-lb-ip>`
- **Kubernetes Dashboard**: `https://<dashboard-lb-ip>`

### Configure Baget NuGet Source

```bash
# Add Baget as a NuGet source
dotnet nuget add source http://<baget-lb-ip>/v3/index.json -n "Homelab Baget"

# Push a package
dotnet nuget push package.nupkg -s http://<baget-lb-ip>/v3/index.json -k your-api-key
```

## Component Details

### kube-vip (LoadBalancer)

- **Mode**: ARP with DHCP IP assignment
- IPs are requested from your router's DHCP server and assigned per service
- Set `kube_vip_interface` to the node network interface (e.g., `eth0`, `ens18`)
- Reserve/pin DHCP leases in your router for stable addresses
- All LoadBalancer services use `load_balancer_ip = "0.0.0.0"` to trigger DHCP

### Flannel CNI

- **Backend**: VXLAN
- **Pod CIDR**: `10.244.0.0/16` (configurable via `flannel_network_cidr`)
- Runs as a DaemonSet on all Linux nodes

### Longhorn Storage

- **Chart version**: `1.9.1` (configurable)
- **Replicas**: 2 (configurable via `longhorn_replica_count`)
- **Storage Class**: `longhorn` (used by all PVCs in this configuration)
- Startup reliability workarounds are applied for the webhook circular dependency (extended manager timeout, relaxed readiness probe, `failurePolicy: Ignore` on webhooks)

### Monitoring Stack (Prometheus + Grafana)

- **Chart**: kube-prometheus-stack `76.3.0` (configurable)
- **Prometheus**: 20Gi storage (Longhorn), 15-day retention
- **Grafana**: 10Gi storage (Longhorn), pre-configured dashboards for Kubernetes and storage
- **AlertManager**: 5Gi storage (Longhorn)

### Baget NuGet Server

- **Storage**: 10Gi persistent volume (Longhorn)
- **Database**: SQLite
- **API**: Full NuGet v3 API support
- **Authentication**: API key via Kubernetes Secret

### Kubernetes Dashboard

- **Chart version**: `7.13.0` (configurable)
- Admin ServiceAccount with `cluster-admin` binding
- Skip login and insecure login enabled for homelab convenience
- 12-hour session lifetime

## Maintenance

### Upgrading Components

Update chart version variables in `terraform.tfvars` or the variable defaults in the relevant `.tf` file, then:

```bash
terraform plan
terraform apply

# Or target a specific component
terraform apply -target=helm_release.longhorn
terraform apply -target=helm_release.prometheus_stack
terraform apply -target=kubernetes_deployment.baget
```

### Backup Strategy

Longhorn provides built-in backup capabilities. Access the Longhorn UI to configure backups to S3, NFS, or other targets.

## Troubleshooting

### Stuck Resources (Longhorn Finalizers)

```bash
make force-clean
```

### LoadBalancer Services Stuck in Pending

```bash
# Check kube-vip pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip

# Verify the node interface name matches kube_vip_interface in terraform.tfvars
ip link show
```

### Longhorn Issues

```bash
kubectl get pods -n longhorn-system
kubectl get storageclass,pv,pvc --all-namespaces
```

### Prometheus Not Scraping

```bash
kubectl get servicemonitors -A
kubectl get pods -n monitoring
```

### Useful Commands

```bash
# Check Terraform state by component
terraform state list | grep longhorn
terraform state list | grep prometheus
terraform state list | grep baget

# Check Helm releases
helm list -A

# Debug specific components
kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip
kubectl logs -n longhorn-system -l app=longhorn-manager
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus
kubectl logs -n baget -l app=baget
```

## Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `kubeconfig_path` | Path to kubeconfig | `~/.kube/config` |
| `kube_vip_version` | kube-vip image version | `v1.0.0` |
| `kube_vip_interface` | Node network interface | `eth0` |
| `flannel_network_cidr` | Pod network CIDR | `10.244.0.0/16` |
| `flannel_version` | Flannel image version | `v0.27.2` |
| `longhorn_chart_version` | Longhorn Helm chart version | `1.9.1` |
| `longhorn_replica_count` | Longhorn replica count | `2` |
| `prometheus_stack_chart_version` | kube-prometheus-stack version | `76.3.0` |
| `prometheus_storage_size` | Prometheus PVC size | `20Gi` |
| `prometheus_retention` | Prometheus data retention | `15d` |
| `grafana_admin_password` | Grafana admin password | `admin123` |
| `grafana_storage_size` | Grafana PVC size | `10Gi` |
| `alertmanager_storage_size` | AlertManager PVC size | `5Gi` |
| `baget_api_key` | BaGet API key | *(required)* |
| `baget_storage_size` | BaGet PVC size | `10Gi` |
| `metrics_server_enabled` | Install Metrics Server | `true` |
| `kubernetes_dashboard_chart_version` | Dashboard Helm chart version | `7.13.0` |
