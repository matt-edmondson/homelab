# =============================================================================
# Debug Escape-Hatch Ingress
# =============================================================================
# Exposes the cluster debug dashboards (Headlamp, Devtron) via NodePort so they
# remain reachable when Traefik is broken. NodePort is independent of Traefik
# and kube-vip — traffic is handled directly by kube-proxy on every node, so as
# long as the API server is up and at least one node is healthy, you can still
# load these UIs in a browser to diagnose the rest of the cluster.
#
# Auth: bypasses the Traefik forward-auth + CrowdSec stack. Each app's native
# auth still applies (Headlamp: admin token, Devtron: admin password). Intended
# for homelab LAN access only — do NOT expose these NodePorts to the internet.
#
# Reach via: http://<any-node-ip>:<nodePort>
#
# The selectors and target ports are read from the chart-installed ClusterIP
# services so this file doesn't drift if the chart changes them.
# =============================================================================

# Variables
variable "debug_ingress_enabled" {
  description = "Expose Headlamp/Devtron via NodePort as a Traefik-independent escape hatch"
  type        = bool
  default     = true
}

variable "debug_ingress_headlamp_nodeport" {
  description = "NodePort for Headlamp escape-hatch service (30000-32767)"
  type        = number
  default     = 30242
}

variable "debug_ingress_devtron_nodeport" {
  description = "NodePort for Devtron escape-hatch service (30000-32767)"
  type        = number
  default     = 30243
}

# --- Headlamp ---

data "kubernetes_service" "headlamp_upstream" {
  count = var.kubernetes_dashboard_enabled && var.debug_ingress_enabled ? 1 : 0

  metadata {
    name      = "headlamp"
    namespace = kubernetes_namespace.headlamp[0].metadata[0].name
  }

  depends_on = [helm_release.headlamp]
}

resource "kubernetes_service" "debug_headlamp" {
  count = var.kubernetes_dashboard_enabled && var.debug_ingress_enabled ? 1 : 0

  metadata {
    name      = "headlamp-debug"
    namespace = kubernetes_namespace.headlamp[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "headlamp"
      "homelab/role"           = "debug-escape-hatch"
    })
  }

  spec {
    type     = "NodePort"
    selector = data.kubernetes_service.headlamp_upstream[0].spec[0].selector

    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = data.kubernetes_service.headlamp_upstream[0].spec[0].port[0].target_port
      node_port   = var.debug_ingress_headlamp_nodeport
    }
  }
}

# --- Devtron ---

data "kubernetes_service" "devtron_upstream" {
  count = var.devtron_enabled && var.debug_ingress_enabled ? 1 : 0

  metadata {
    name      = "devtron-service"
    namespace = kubernetes_namespace.devtron[0].metadata[0].name
  }

  depends_on = [helm_release.devtron]
}

resource "kubernetes_service" "debug_devtron" {
  count = var.devtron_enabled && var.debug_ingress_enabled ? 1 : 0

  metadata {
    name      = "devtron-debug"
    namespace = kubernetes_namespace.devtron[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "devtron"
      "homelab/role"           = "debug-escape-hatch"
    })
  }

  spec {
    type     = "NodePort"
    selector = data.kubernetes_service.devtron_upstream[0].spec[0].selector

    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = data.kubernetes_service.devtron_upstream[0].spec[0].port[0].target_port
      node_port   = var.debug_ingress_devtron_nodeport
    }
  }
}

# Outputs
output "debug_ingress_info" {
  description = "NodePort escape-hatch URLs for debug dashboards (replace <node-ip> with any cluster node IP)"
  value = var.debug_ingress_enabled ? {
    note = "Reachable on every node IP. Bypasses Traefik/oauth — use for incident debugging only."
    headlamp = var.kubernetes_dashboard_enabled ? {
      url       = "http://<node-ip>:${var.debug_ingress_headlamp_nodeport}"
      node_port = var.debug_ingress_headlamp_nodeport
      service   = "${kubernetes_service.debug_headlamp[0].metadata[0].namespace}/${kubernetes_service.debug_headlamp[0].metadata[0].name}"
    } : null
    devtron = var.devtron_enabled ? {
      url       = "http://<node-ip>:${var.debug_ingress_devtron_nodeport}"
      node_port = var.debug_ingress_devtron_nodeport
      service   = "${kubernetes_service.debug_devtron[0].metadata[0].namespace}/${kubernetes_service.debug_devtron[0].metadata[0].name}"
    } : null
    commands = {
      list_node_ips     = "kubectl get nodes -o wide"
      check_headlamp_np = "kubectl get svc -n headlamp headlamp-debug"
      check_devtron_np  = "kubectl get svc -n devtroncd devtron-debug"
    }
  } : null
}
