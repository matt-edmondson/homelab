output "metrics_server" {
  description = "Metrics Server configuration and usage information"
  value = var.metrics_server_enabled ? {
    enabled = true
    message = "Metrics Server is installed and configured for your homelab"
    usage = [
      "Test resource metrics:",
      "  kubectl top nodes",
      "  kubectl top pods --all-namespaces",
      "",
      "Ready for Horizontal Pod Autoscaler (HPA) when needed",
      "Kubernetes Dashboard will show resource usage graphs"
    ]
    configuration = {
      chart_version = "3.12.1"
      namespace     = "kube-system"
      kubelet_tls   = "insecure (--kubelet-insecure-tls) - suitable for homelab"
    }
    note = ""
  } : {
    enabled = false
    message = "Metrics Server is disabled. Enable it by setting metrics_server_enabled = true"
    usage = []
    configuration = {
      chart_version = ""
      namespace     = ""
      kubelet_tls   = ""
    }
    note = "Without metrics-server, 'kubectl top' commands won't work and HPA is unavailable"
  }
}

output "metallb_ip_pool" {
  description = "IP address pool configured for MetalLB"
  value       = var.metallb_ip_range
}

output "bgp_configuration" {
  description = "BGP configuration for MetalLB"
  value = {
    metallb_asn = var.metallb_asn
    router_asn  = var.router_asn
    router_ip   = var.router_ip
  }
}

output "longhorn_storageclass" {
  description = "Longhorn storage class name"
  value       = kubernetes_storage_class.longhorn.metadata[0].name
}

output "longhorn_frontend_service" {
  description = "Longhorn frontend LoadBalancer service details"
  value = {
    name      = kubernetes_service.longhorn_frontend_lb.metadata[0].name
    namespace = kubernetes_service.longhorn_frontend_lb.metadata[0].namespace
  }
}

output "prometheus_service" {
  description = "Prometheus service details"
  value = {
    name      = "${helm_release.prometheus_stack.name}-kube-prom-prometheus"
    namespace = helm_release.prometheus_stack.namespace
    port      = 9090
  }
}

output "grafana_service" {
  description = "Grafana service details"
  value = {
    name      = "${helm_release.prometheus_stack.name}-grafana"
    namespace = helm_release.prometheus_stack.namespace
    port      = 80
  }
}

output "baget_service" {
  description = "Baget service details"
  value = {
    name      = kubernetes_service.baget.metadata[0].name
    namespace = kubernetes_service.baget.metadata[0].namespace
    port      = 80
  }
}

output "application_urls" {
  description = "URLs for accessing applications (will show LoadBalancer IPs after deployment)"
  sensitive   = true
  value = {
    longhorn_ui = "Access Longhorn UI at: http://<longhorn-frontend-lb-ip>"
    prometheus  = "Access Prometheus at: http://<prometheus-lb-ip>:9090"
    grafana     = "Access Grafana at: http://<grafana-lb-ip> (admin/${var.grafana_admin_password})"
    baget      = "Access Baget at: http://<baget-lb-ip>"
  }
}

output "deployment_commands" {
  description = "Commands to check deployment status"
  value = {
    check_pods           = "kubectl get pods --all-namespaces"
    check_services      = "kubectl get services --all-namespaces"
    check_loadbalancers = "kubectl get services --all-namespaces | grep LoadBalancer"
    longhorn_pods       = "kubectl get pods -n longhorn-system"
    metallb_pods        = "kubectl get pods -n metallb-system"
    monitoring_pods     = "kubectl get pods -n monitoring"
    baget_pods         = "kubectl get pods -n baget"
  }
}

output "bgp_router_config" {
  description = "BGP configuration for your router (UDM Pro)"
  value = <<-EOT
    # Add this to your UDM Pro BGP configuration:
    router bgp ${var.router_asn}
     bgp router-id ${var.router_ip}
     no bgp ebgp-requires-policy
     neighbor K8S-PEERS peer-group
     neighbor K8S-PEERS remote-as ${var.metallb_asn}
     neighbor K8S-PEERS bfd
     bgp listen range 192.168.0.0/24 peer-group K8S-PEERS
     !
     address-family ipv4 unicast
      neighbor K8S-PEERS activate
     exit-address-family
  EOT
}

output "storage_info" {
  description = "Storage configuration information"
  value = {
    longhorn_replicas    = var.longhorn_replica_count
    baget_storage       = var.baget_storage_size
    prometheus_storage  = var.prometheus_storage_size
    grafana_storage     = var.grafana_storage_size
  }
}

output "pihole_integration" {
  description = "Pi-hole DNS integration information"
  value = var.pihole_enabled ? {
    enabled             = true
    pihole_host        = var.pihole_host
    domain             = var.homelab_domain
    deployment_name    = "pihole-dns-sync"
    namespace          = "kube-system"
    authentication     = var.pihole_webpassword != "" ? "enabled" : "disabled"
    message            = "Pi-hole integration is enabled and configured"
    
    # DNS names that will be created (dynamically generated from service mappings)
    dns_records = {
      for service, hostname in var.pihole_service_mappings : 
      hostname => "${hostname}.${var.homelab_domain}"
    }
    
    # Monitoring commands
    monitoring_commands = [
      "# Check Pi-hole sync pod status:",
      "kubectl get pods -n kube-system -l app.kubernetes.io/name=pihole-dns-sync",
      "",
      "# View sync logs:",
      "kubectl logs -n kube-system -l app.kubernetes.io/name=pihole-dns-sync -f",
      "",
      "# Check service status:",
      "kubectl describe deployment -n kube-system pihole-dns-sync"
    ]
    
    # Test commands (dynamically generated)
    test_commands = concat([
      "# Test Pi-hole API connection:",
      "curl -s http://${var.pihole_host}/admin/api.php?status",
      "",
      "# Test DNS resolution for your configured services:"
    ], [
      for service, hostname in var.pihole_service_mappings :
      "nslookup ${hostname}.${var.homelab_domain} ${var.pihole_host}"
    ])
    
    # Usage information (dynamically generated)
    usage = concat([
      "The Pi-hole sync runs automatically in your Kubernetes cluster.",
      "It will continuously monitor LoadBalancer services and update Pi-hole DNS records.",
      "No manual intervention required - everything is automated!",
      "",
      "Your configured services will be available at:"
    ], [
      for service, hostname in var.pihole_service_mappings :
      "- http://${hostname}.${var.homelab_domain}"
    ], [
      "",
      "Note: Actual ports depend on your service configurations.",
      "Use 'kubectl get services --all-namespaces | grep LoadBalancer' to see port mappings."
    ])
    
    setup_required = []
  } : {
    enabled             = false
    pihole_host        = ""
    domain             = ""
    deployment_name    = ""
    namespace          = ""
    authentication     = "disabled"
    message            = "Enable Pi-hole integration by setting pihole_enabled = true in terraform.tfvars"
    dns_records        = {}
    monitoring_commands = []
    test_commands      = []
    usage              = []
    setup_required = [
      "1. Set pihole_enabled = true",
      "2. Set pihole_host to your Pi-hole IP address", 
      "3. Set pihole_webpassword to your Pi-hole admin password (leave empty if no auth required)",
      "4. Configure pihole_service_mappings with your LoadBalancer services",
      "5. Use ./nginx-sync/find-services.sh to discover your services",
      "6. Run: terraform apply"
    ]
  }
}
