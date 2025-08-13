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

# Longhorn StorageClass
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

# Longhorn Frontend LoadBalancer Service
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
