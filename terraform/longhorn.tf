# =============================================================================
# Longhorn Distributed Storage - Self-Contained Module
# =============================================================================

# Variables
variable "longhorn_chart_version" {
  description = "Version of Longhorn Helm chart"
  type        = string
  default     = "1.6.2"
}

variable "longhorn_replica_count" {
  description = "Number of replicas for Longhorn storage"
  type        = number
  default     = 2
}

# Namespace
resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "longhorn-system"
    })
  }
}

# Longhorn Installation
resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = var.longhorn_chart_version
  namespace  = kubernetes_namespace.longhorn_system.metadata[0].name

  set {
    name  = "defaultSettings.defaultReplicaCount"
    value = var.longhorn_replica_count
  }

  set {
    name  = "defaultSettings.staleReplicaTimeout"
    value = "30"
  }

  depends_on = [kubernetes_namespace.longhorn_system]
}

# Longhorn StorageClass (set as default)
resource "kubernetes_storage_class" "longhorn" {
  metadata {
    name = "longhorn"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
    labels = var.common_labels
  }
  storage_provisioner    = "driver.longhorn.io"
  allow_volume_expansion = true
  reclaim_policy        = "Delete"
  volume_binding_mode   = "Immediate"
  
  parameters = {
    numberOfReplicas       = var.longhorn_replica_count
    staleReplicaTimeout    = "30"
    fsType                 = "ext4"
  }

  depends_on = [helm_release.longhorn]
}

# Longhorn UI LoadBalancer Service (gets DHCP IP from kube-vip)
resource "kubernetes_service" "longhorn_frontend_lb" {
  metadata {
    name      = "longhorn-frontend-lb"
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "longhorn-ui"
      "app.kubernetes.io/component" = "frontend"
    })
  }
  
  spec {
    type = "LoadBalancer"
    selector = {
      app = "longhorn-ui"
    }
    port {
      name        = "http"
      port        = 80
      target_port = 8000
      protocol    = "TCP"
    }
  }
  
  depends_on = [helm_release.longhorn]
}

# Outputs
output "longhorn_info" {
  description = "Longhorn storage system information"
  value = {
    namespace           = kubernetes_namespace.longhorn_system.metadata[0].name
    chart_version       = var.longhorn_chart_version
    replica_count       = var.longhorn_replica_count
    storage_class       = kubernetes_storage_class.longhorn.metadata[0].name
    ui_service         = kubernetes_service.longhorn_frontend_lb.metadata[0].name
    ui_ip              = try(
      kubernetes_service.longhorn_frontend_lb.status[0].load_balancer[0].ingress[0].ip,
      "pending (will be assigned by router DHCP)"
    )
    commands = {
      check_pods    = "kubectl get pods -n ${kubernetes_namespace.longhorn_system.metadata[0].name}"
      check_volumes = "kubectl get pv,pvc --all-namespaces"
      ui_access     = "Access Longhorn UI at: http://<dhcp-assigned-ip>"
    }
  }
}
