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
