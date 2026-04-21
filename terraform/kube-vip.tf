# =============================================================================
# kube-vip Static ARP LoadBalancer - Self-Contained Module
# =============================================================================

# Variables
variable "kube_vip_version" {
  description = "kube-vip container image version"
  type        = string
  default     = "v1.0.0"
}

variable "kube_vip_interface" {
  description = "Network interface for kube-vip to use for LoadBalancer services"
  type        = string
  default     = "eth0"
}

variable "kube_vip_cp_address" {
  description = "Floating VIP for the Kubernetes control-plane API server. k8s.ktsu.dev should resolve to this IP."
  type        = string
  default     = "192.168.0.5"
}

# kube-vip LoadBalancer with static ARP
# Uses statically assigned IPs specified on each LoadBalancer service

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

# =============================================================================
# kube-vip Control-Plane VIP DaemonSet
#
# Runs only on control-plane nodes and claims var.kube_vip_cp_address as a
# floating VIP for the Kubernetes API server. Uses ARP + leader election; on
# failover the surviving CP node takes the VIP. Must use a different Prometheus
# port from the services DS (2112) since both share the host network on CP
# nodes.
# =============================================================================

resource "kubernetes_daemonset" "kube_vip_cp" {
  depends_on = [
    kubernetes_service_account.kube_vip,
    kubernetes_cluster_role.kube_vip,
    kubernetes_cluster_role_binding.kube_vip
  ]

  metadata {
    name      = "kube-vip-cp-ds"
    namespace = "kube-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"    = "kube-vip-cp"
      "app.kubernetes.io/version" = var.kube_vip_version
    })
  }

  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "kube-vip-cp"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          "app.kubernetes.io/name" = "kube-vip-cp"
        })
      }

      spec {
        service_account_name = kubernetes_service_account.kube_vip.metadata[0].name
        host_network         = true
        host_pid             = true

        node_selector = {
          "node-role.kubernetes.io/control-plane" = ""
        }

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
            "--controlplane",
            "--address=${var.kube_vip_cp_address}",
            "--arp",
            "--leaderElection",
            "--leaseDuration=15",
            "--leaseRenewDuration=10",
            "--leaseRetry=2",
            "--log=5",
            "--prometheusHTTPServer=:2113"
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
              port = 2113
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
              port = 2113
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            success_threshold     = 1
            timeout_seconds       = 10
          }
        }
      }
    }
  }
}

# Outputs
output "kube_vip_info" {
  description = "kube-vip Static ARP LoadBalancer information"
  value = {
    version         = var.kube_vip_version
    interface       = var.kube_vip_interface
    mode            = "Static ARP"
    deployment_name = kubernetes_daemonset.kube_vip.metadata[0].name
    namespace       = "kube-system"

    description = "LoadBalancer services use statically assigned IPs via ARP — no DHCP dependency"

    commands = {
      check_pods     = "kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip"
      check_services = "kubectl get services --all-namespaces | grep LoadBalancer"
      view_logs      = "kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip"
      check_config   = "kubectl get configmap -n kube-system kubevip -o yaml"
    }
  }
}

output "kube_vip_cp_info" {
  description = "kube-vip control-plane VIP information"
  value = {
    vip_address     = var.kube_vip_cp_address
    deployment_name = kubernetes_daemonset.kube_vip_cp.metadata[0].name
    namespace       = "kube-system"

    description = "Floating VIP for the Kubernetes API server. DNS record k8s.ktsu.dev should resolve to this IP."

    commands = {
      check_pods = "kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip-cp -o wide"
      view_logs  = "kubectl logs -n kube-system -l app.kubernetes.io/name=kube-vip-cp --tail=50"
      test_vip   = "curl -k https://${var.kube_vip_cp_address}:6443/readyz"
    }
  }
}
