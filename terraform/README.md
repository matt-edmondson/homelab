# Kubernetes Homelab Infrastructure with Terraform

This Terraform configuration sets up a complete Kubernetes homelab environment with the following components:

- **MetalLB** - Load balancer with BGP for VIP advertisement to your router
- **Longhorn** - Distributed block storage
- **Prometheus & Grafana** - Complete monitoring and visualization stack
- **Baget** - NuGet package server
- **AlertManager** - Alert management (part of Prometheus stack)
- **Metrics Server** - Resource metrics for `kubectl top` and Horizontal Pod Autoscaler (HPA)
- **Pi-hole DNS Sync** - Automatic DNS record management for LoadBalancer services

## File Structure

The Terraform configuration is organized by concern into separate files:

```
terraform/
├── providers.tf        # Terraform and provider configurations
├── variables.tf        # All variable definitions
├── outputs.tf          # All output definitions
├── namespaces.tf       # Kubernetes namespace resources
├── networking.tf       # MetalLB load balancer and metrics server
├── storage.tf          # Longhorn distributed storage
├── monitoring.tf       # Prometheus, Grafana, and AlertManager
├── applications.tf     # Application deployments (Baget)
├── dns.tf             # Pi-hole DNS sync for automatic service discovery
├── terraform.tfvars.example  # Example configuration
└── Makefile           # Automation helpers
```

This modular structure makes it easier to:
- Understand and maintain individual components
- Add new applications or infrastructure components
- Troubleshoot specific areas of the infrastructure
- Apply changes to specific concerns independently

## Architecture Overview

```
┌─────────────────┐    BGP    ┌──────────────────────────────┐
│ UDM Pro Router  │◄─────────►│ Kubernetes Cluster          │
│ ASN: 65001      │           │ ASN: 65002                   │
│ IP: 192.168.0.1 │           │                              │
└─────────────────┘           │  ┌─────────────────────────┐ │
                              │  │ MetalLB LoadBalancers   │ │
                              │  │ IP Pool: 192.168.1.x    │ │
                              │  └─────────────────────────┘ │
                              │                              │
                              │  ┌─────────────────────────┐ │
                              │  │ Applications            │ │
                              │  │ • Prometheus            │ │
                              │  │ • Grafana              │ │
                              │  │ • Baget                │ │
                              │  │ • Longhorn UI          │ │
                              │  └─────────────────────────┘ │
                              │                              │
                              │  ┌─────────────────────────┐ │
                              │  │ Longhorn Storage        │ │
                              │  │ Replicas: 2             │ │
                              │  └─────────────────────────┘ │
                              └──────────────────────────────┘
```

## Prerequisites

1. **Kubernetes Cluster** - A running Kubernetes cluster
2. **kubectl** - Configured to access your cluster
3. **Terraform** >= 1.0
4. **Helm** (Terraform will manage Helm releases, but having Helm CLI is helpful for debugging)

## Quick Start

### 1. Clone and Configure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

### 2. Customize Configuration

Edit `terraform.tfvars` with your specific network settings:

```hcl
# Network Configuration - IMPORTANT: Adjust for your network
metallb_ip_range = ["192.168.1.10-192.168.1.250"]  # Available IPs for LoadBalancers
router_ip        = "192.168.0.1"                   # Your router's IP
metallb_asn      = 65002                           # Cluster BGP ASN
router_asn       = 65001                           # Router BGP ASN

# Security - CHANGE THESE!
baget_api_key           = "$(openssl rand -base64 32)"
grafana_admin_password  = "your-secure-password"
```

### 3. Generate Secure Keys

```bash
# Generate a secure API key for Baget
echo "baget_api_key = \"$(openssl rand -base64 32)\"" >> terraform.tfvars

# Or use this one-liner to generate both
cat >> terraform.tfvars << EOF
baget_api_key = "$(openssl rand -base64 32)"
grafana_admin_password = "$(openssl rand -base64 16)"
EOF
```

### 4. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 5. Configure Router BGP (UDM Pro)

Add this configuration to your UDM Pro (use the output from `terraform output bgp_router_config`):

```bash
configure
set protocols bgp 65001 parameters router-id 192.168.0.1
set protocols bgp 65001 neighbor 192.168.0.0/24 peer-group K8S-PEERS
set protocols bgp 65001 neighbor 192.168.0.0/24 remote-as 65002
commit
save
```

## Post-Deployment

### Check Service Status

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Get LoadBalancer IPs
kubectl get services --all-namespaces | grep LoadBalancer

# Check MetalLB BGP status
kubectl get bgppeers -n metallb-system
kubectl get ipaddresspools -n metallb-system
```

### Access Applications

After deployment, get the LoadBalancer IPs:

```bash
# Get all LoadBalancer services
kubectl get svc --all-namespaces -o wide | grep LoadBalancer
```

Then access:
- **Grafana**: `http://<grafana-lb-ip>` (admin / your-password)
- **Prometheus**: `http://<prometheus-lb-ip>:9090`
- **Longhorn UI**: `http://<longhorn-lb-ip>`
- **Baget**: `http://<baget-lb-ip>`

### Configure Baget NuGet Source

```bash
# Add Baget as NuGet source
dotnet nuget add source http://<baget-lb-ip>/v3/index.json -n "Homelab Baget"

# Push a package (replace with your API key from terraform.tfvars)
dotnet nuget push package.nupkg -s http://<baget-lb-ip>/v3/index.json -k your-api-key
```

## Component Details

### MetalLB Configuration

- **Mode**: BGP
- **IP Pool**: Configurable (default: 192.168.1.10-192.168.1.250)
- **BGP ASN**: 65002 (cluster) ↔ 65001 (router)
- **BFD**: Enabled for fast failover (300ms intervals)

### Longhorn Storage

- **Replicas**: 2 (configurable)
- **Default Storage Class**: Yes
- **File System**: ext4
- **Volume Expansion**: Enabled
- **Web UI**: Accessible via LoadBalancer

### Monitoring Stack (Prometheus + Grafana)

- **Prometheus**: 
  - Storage: 20Gi (Longhorn)
  - Retention: 15 days
  - Scrapes: Kubernetes metrics, node metrics, cAdvisor
- **Grafana**: 
  - Pre-configured dashboards for Kubernetes and Longhorn
  - Persistent storage: 10Gi (Longhorn)
- **AlertManager**: 
  - Storage: 5Gi (Longhorn)
  - Integrated with Prometheus

### Baget NuGet Server

- **Storage**: 10Gi persistent volume (Longhorn)
- **Database**: SQLite
- **API**: Full NuGet v3 API support
- **Authentication**: API key-based

## Maintenance

### Upgrading Components

```bash
# Update Helm chart versions in variables.tf, then:
terraform plan
terraform apply

# Or upgrade individual components by targeting specific files:
terraform apply -target=helm_release.longhorn              # Storage
terraform apply -target=helm_release.metallb               # Networking
terraform apply -target=helm_release.prometheus_stack      # Monitoring
terraform apply -target=kubernetes_deployment.baget        # Applications
```

### Backup Strategy

Longhorn provides built-in backup capabilities:

```bash
# Access Longhorn UI to configure backups to S3, NFS, etc.
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
```

### Monitoring BGP

```bash
# Check MetalLB speaker logs
kubectl logs -n metallb-system -l app=metallb

# Check BGP peer status
kubectl describe bgppeers -n metallb-system

# Router side (UDM Pro)
show ip bgp summary
show ip bgp neighbors
```

## Troubleshooting

### File-Specific Debugging

With the modular structure, you can troubleshoot specific components:

```bash
# Debug networking issues (MetalLB)
terraform plan -target=module.kubernetes_manifest.metallb_ipaddresspool
kubectl get pods -n metallb-system
kubectl get bgppeers,ipaddresspools,bgpadvertisements -n metallb-system

# Debug storage issues (Longhorn)
terraform plan -target=helm_release.longhorn
kubectl get pods -n longhorn-system
kubectl get storageclass,pv,pvc --all-namespaces

# Debug monitoring issues (Prometheus/Grafana)
terraform plan -target=helm_release.prometheus_stack
kubectl get pods -n monitoring
kubectl get servicemonitors,prometheusrules -A

# Debug application issues (Baget)
terraform plan -target=kubernetes_deployment.baget
kubectl get pods,svc,pvc -n baget

# Debug DNS sync issues (Pi-hole)
terraform plan -target=kubernetes_deployment.pihole_dns_sync
kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync -f
```

### Common Issues

1. **LoadBalancer services stuck in Pending**
   - Check MetalLB pods: `kubectl get pods -n metallb-system`
   - Verify IP pool: `kubectl get ipaddresspools -n metallb-system`
   - Check BGP peer: `kubectl get bgppeers -n metallb-system`
   - Review networking.tf for configuration issues

2. **BGP not working**
   - Verify router configuration
   - Check ASN numbers match between cluster and router
   - Ensure IP addresses are correct
   - Check variables.tf for correct network settings

3. **Longhorn issues**
   - Check node storage: `kubectl get nodes -o wide`
   - Verify Longhorn system pods: `kubectl get pods -n longhorn-system`
   - Check storage class: `kubectl get storageclass`
   - Review storage.tf for configuration problems

4. **Prometheus not scraping**
   - Check service discovery: `kubectl get servicemonitors -A`
   - Verify RBAC: `kubectl get clusterrole prometheus-stack-kube-prom-prometheus`
   - Review monitoring.tf for Helm values

5. **Pi-hole DNS sync not working**
   - Check Pi-hole connectivity: `kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync`
   - Verify service mappings in variables.tf
   - Test Pi-hole API access from cluster
   - Review dns.tf for configuration issues

### Useful Commands

```bash
# Check Terraform state by component
terraform state list | grep namespace                     # All namespaces
terraform state list | grep metallb                       # MetalLB resources
terraform state list | grep longhorn                      # Longhorn resources
terraform state list | grep prometheus                    # Monitoring resources
terraform state list | grep baget                         # Application resources
terraform state list | grep pihole                        # DNS sync resources

# Show specific resource details
terraform state show kubernetes_service.baget
terraform state show helm_release.longhorn
terraform state show kubernetes_namespace.monitoring

# Force recreation of resources by component
terraform taint helm_release.prometheus_stack             # Recreate monitoring
terraform taint helm_release.longhorn                     # Recreate storage
terraform taint kubernetes_deployment.baget               # Recreate application

# Check Helm releases
helm list -A

# Debug specific components
kubectl logs -n metallb-system -l app=metallb,component=speaker      # MetalLB
kubectl logs -n longhorn-system -l app=longhorn-manager             # Longhorn
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus     # Prometheus
kubectl logs -n baget -l app=baget                                  # Baget
kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync # Pi-hole sync
```

## Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `metallb_ip_range` | IP range for LoadBalancers | `["192.168.1.10-192.168.1.250"]` |
| `metallb_asn` | Cluster BGP ASN | `65002` |
| `router_asn` | Router BGP ASN | `65001` |
| `router_ip` | Router IP for BGP | `"192.168.0.1"` |
| `baget_api_key` | Baget API key | `"your-secure-api-key-here"` |
| `grafana_admin_password` | Grafana admin password | `"admin123"` |
| `longhorn_replica_count` | Longhorn replicas | `2` |

See `variables.tf` for complete list and descriptions.

## Security Considerations

1. **Change default passwords** in `terraform.tfvars`
2. **Secure API keys** - Use strong, random keys for Baget
3. **Network policies** - Consider implementing Kubernetes network policies
4. **RBAC** - Review and customize RBAC permissions as needed
5. **TLS** - Consider adding TLS termination for HTTPS access
6. **File Permissions** - Ensure `terraform.tfvars` has restricted permissions (600)
7. **State Security** - Consider using remote state with encryption for production
