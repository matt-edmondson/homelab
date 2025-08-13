# Create namespaces
resource "kubernetes_namespace" "metallb_system" {
  metadata {
    name = "metallb-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "metallb-system"
    })
  }
}

resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "longhorn-system"
    })
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "monitoring"
    })
  }
}

resource "kubernetes_namespace" "baget" {
  metadata {
    name = "baget"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
  }
}
