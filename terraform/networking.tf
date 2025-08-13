# MetalLB Installation
resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = var.metallb_chart_version
  namespace  = kubernetes_namespace.metallb_system.metadata[0].name

  depends_on = [kubernetes_namespace.metallb_system]
}

# MetalLB Configuration - IP Address Pool
resource "kubernetes_manifest" "metallb_ipaddresspool" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "default-pool"
      namespace = kubernetes_namespace.metallb_system.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      addresses = var.metallb_ip_range
    }
  }
  depends_on = [helm_release.metallb]
}

# MetalLB BFD Profile for fast failover
resource "kubernetes_manifest" "metallb_bfd_profile" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "BFDProfile"
    metadata = {
      name      = "fast-failover"
      namespace = kubernetes_namespace.metallb_system.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      receiveInterval   = 300
      transmitInterval  = 300
      detectMultiplier  = 3
      echoMode         = true
      passiveMode      = false
      minimumTtl       = 254
    }
  }
  depends_on = [helm_release.metallb]
}

# MetalLB BGP Peer Configuration
resource "kubernetes_manifest" "metallb_bgp_peer" {
  manifest = {
    apiVersion = "metallb.io/v1beta2"
    kind       = "BGPPeer"
    metadata = {
      name      = "router"
      namespace = kubernetes_namespace.metallb_system.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      myASN       = var.metallb_asn
      peerASN     = var.router_asn
      peerAddress = var.router_ip
      bfdProfile  = "fast-failover"
    }
  }
  depends_on = [kubernetes_manifest.metallb_bfd_profile]
}

# MetalLB BGP Advertisement
resource "kubernetes_manifest" "metallb_bgp_advertisement" {
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "BGPAdvertisement"
    metadata = {
      name      = "default-adv"
      namespace = kubernetes_namespace.metallb_system.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      ipAddressPools = ["default-pool"]
    }
  }
  depends_on = [kubernetes_manifest.metallb_ipaddresspool]
}

# Metrics Server Installation
resource "helm_release" "metrics_server" {
  count = var.metrics_server_enabled ? 1 : 0
  
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.1"
  namespace  = "kube-system"

  set {
    name  = "args"
    value = "{--cert-dir=/tmp,--secure-port=4443,--kubelet-preferred-address-types=InternalIP\\,ExternalIP\\,Hostname,--kubelet-use-node-status-port,--metric-resolution=15s,--kubelet-insecure-tls}"
  }

  set {
    name  = "metrics.enabled"
    value = "false"
  }

  set {
    name  = "serviceMonitor.enabled"
    value = "false"
  }
}
