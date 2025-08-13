# =============================================================================
# kube-vip DHCP LoadBalancer - Self-Contained Module
# =============================================================================

# Variables
variable "kube_vip_version" {
  description = "kube-vip container image version"
  type        = string
  default     = "v0.6.4"
}

variable "kube_vip_interface" {
  description = "Network interface for kube-vip to use for LoadBalancer services"
  type        = string
  default     = "eth0"
}

# kube-vip LoadBalancer with DHCP support
# Uses your router's DHCP server for automatic IP allocation

# kube-vip RBAC
resource "kubernetes_service_account" "kube_vip" {
  metadata {
    name      = "kube-vip"
    namespace = "kube-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "kube-vip"
    })
  }
}

resource "kubernetes_cluster_role" "kube_vip" {
  metadata {
    name = "system:kube-vip-role"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "kube-vip"
    })
  }

  rule {
    api_groups = [""]
    resources  = ["services"]
    verbs      = ["list", "get", "watch", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["services/status"]
    verbs      = ["update"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["list", "get", "watch", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list", "get", "watch", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints", "endpointslices"]
    verbs      = ["list", "get", "watch", "update"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create"]
  }

  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["list", "get", "watch", "update", "create"]
  }
}

resource "kubernetes_cluster_role_binding" "kube_vip" {
  metadata {
    name = "system:kube-vip-binding"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "kube-vip"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.kube_vip.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.kube_vip.metadata[0].name
    namespace = kubernetes_service_account.kube_vip.metadata[0].namespace
  }
}

# kube-vip uses command-line arguments instead of config file

# kube-vip DaemonSet
resource "kubernetes_daemonset" "kube_vip" {
  # Explicit dependencies to ensure proper creation order
  depends_on = [
    kubernetes_service_account.kube_vip,
    kubernetes_cluster_role.kube_vip,
    kubernetes_cluster_role_binding.kube_vip
  ]

  metadata {
    name      = "kube-vip-ds"
    namespace = "kube-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"    = "kube-vip"
      "app.kubernetes.io/version" = var.kube_vip_version
    })
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "kube-vip"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name" = "kube-vip"
        })
      }

      spec {
        service_account_name = kubernetes_service_account.kube_vip.metadata[0].name
        host_network         = true
        host_pid             = true
        
        toleration {
          effect = "NoSchedule"
          key    = "node-role.kubernetes.io/master"
        }
        
        toleration {
          effect = "NoSchedule" 
          key    = "node-role.kubernetes.io/control-plane"
        }

        container {
          name  = "kube-vip"
          image = "ghcr.io/kube-vip/kube-vip:${var.kube_vip_version}"
          
          args = [
            "manager",
            "--interface=${var.kube_vip_interface}",
            "--serviceInterface=${var.kube_vip_interface}",
            "--services",
            "--enableLoadBalancer",
            "--arp",
            "--leaderElection",
            "--leaseDuration=15",
            "--leaseRenewDuration=10",
            "--leaseRetry=2",
            "--log=5",
            "--prometheusHTTPServer=:2112"
          ]

          image_pull_policy = "Always"

          security_context {
            privileged = true
            capabilities {
              add = ["NET_ADMIN", "NET_RAW", "SYS_TIME"]
            }
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          liveness_probe {
            failure_threshold = 5
            http_get {
              host = "localhost"
              path = "/metrics"
              port = 2112
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            success_threshold     = 1
            timeout_seconds       = 10
          }

          readiness_probe {
            failure_threshold = 3
            http_get {
              host = "localhost" 
              path = "/metrics"
              port = 2112
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            success_threshold     = 1
            timeout_seconds       = 10
          }
        }

        # No config volume needed - using command line args

        node_selector = {
          "kubernetes.io/os" = "linux"
        }
      }
    }
  }
}

# Outputs
output "kube_vip_info" {
  description = "kube-vip DHCP LoadBalancer information"
  value = {
    version          = var.kube_vip_version
    interface        = var.kube_vip_interface
    mode            = "DHCP"
    deployment_name = kubernetes_daemonset.kube_vip.metadata[0].name
    namespace       = "kube-system"
    
    description = "LoadBalancer services get IPs dynamically from your router's DHCP server"
    
    router_benefits = [
      "LoadBalancer services get real DHCP IPs from your router",
      "You can pin/reserve these IPs in your router's DHCP settings",
      "Add DNS A records directly on your router for each service",
      "No IP range conflicts - router DHCP handles all assignment"
    ]
    
    workflow = [
      "1. kube-vip requests DHCP IP for each LoadBalancer service",
      "2. Router assigns IP from DHCP pool to kube-vip",
      "3. Check router's DHCP client list to see assigned IPs",
      "4. Pin/reserve IPs in router DHCP settings",
      "5. Add DNS A records on router (e.g., grafana.k8s.home -> IP)"
    ]
    
    commands = {
      check_pods     = "kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip"
      check_services = "kubectl get services --all-namespaces | grep LoadBalancer"
      view_logs      = "kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip"
      check_config   = "kubectl get configmap -n kube-system kubevip -o yaml"
    }
  }
}
