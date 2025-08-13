# =============================================================================
# Flannel CNI Network Plugin - Infrastructure as Code
# =============================================================================

# Variables
variable "flannel_version" {
  description = "Version of Flannel CNI plugin"
  type        = string
  default     = "v0.27.2"
}

variable "flannel_cni_plugin_version" {
  description = "Version of Flannel CNI plugin binary"
  type        = string
  default     = "v1.7.1-flannel2"
}

variable "flannel_network_cidr" {
  description = "Pod network CIDR for Flannel"
  type        = string
  default     = "10.244.0.0/16"
}

# Flannel Namespace
resource "kubernetes_namespace" "flannel" {
  metadata {
    name = "kube-flannel"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flannel"
      "pod-security.kubernetes.io/enforce" = "privileged"
    })
  }
}

# Flannel ServiceAccount
resource "kubernetes_service_account" "flannel" {
  metadata {
    name      = "flannel"
    namespace = kubernetes_namespace.flannel.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flannel"
    })
  }
}

# Flannel ClusterRole
resource "kubernetes_cluster_role" "flannel" {
  metadata {
    name = "flannel"
    labels = var.common_labels
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["nodes/status"]
    verbs      = ["patch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["clustercidrs"]
    verbs      = ["list", "watch"]
  }
}

# Flannel ClusterRoleBinding
resource "kubernetes_cluster_role_binding" "flannel" {
  metadata {
    name = "flannel"
    labels = var.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.flannel.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.flannel.metadata[0].name
    namespace = kubernetes_namespace.flannel.metadata[0].name
  }
}

# Flannel ConfigMap
resource "kubernetes_config_map" "flannel_cfg" {
  metadata {
    name      = "kube-flannel-cfg"
    namespace = kubernetes_namespace.flannel.metadata[0].name
    labels = merge(var.common_labels, {
      "app"  = "flannel"
      "tier" = "node"
    })
  }

  data = {
    "cni-conf.json" = jsonencode({
      name       = "cbr0"
      cniVersion = "1.0.0"
      plugins = [
        {
          type   = "flannel"
          delegate = {
            hairpinMode   = true
            isDefaultGateway = true
          }
        },
        {
          type = "portmap"
          capabilities = {
            portMappings = true
          }
        }
      ]
    })

    "net-conf.json" = jsonencode({
      Network   = var.flannel_network_cidr
      Backend = {
        Type = "vxlan"
      }
    })
  }
}

# Flannel DaemonSet
resource "kubernetes_daemonset" "flannel" {
  metadata {
    name      = "kube-flannel-ds"
    namespace = kubernetes_namespace.flannel.metadata[0].name
    labels = merge(var.common_labels, {
      "app"  = "flannel"
      "tier" = "node"
    })
  }

  spec {
    selector {
      match_labels = {
        app = "flannel"
      }
    }

    template {
      metadata {
        labels = {
          app  = "flannel"
          tier = "node"
        }
      }

      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "kubernetes.io/os"
                  operator = "In"
                  values   = ["linux"]
                }
              }
            }
          }
        }

        host_network                     = true
        priority_class_name              = "system-node-critical"
        service_account_name             = kubernetes_service_account.flannel.metadata[0].name
        termination_grace_period_seconds = 5

        toleration {
          operator = "Exists"
          effect   = "NoSchedule"
        }

        container {
          name  = "kube-flannel"
          image = "docker.io/flannel/flannel:${var.flannel_version}"

          command = ["/opt/bin/flanneld"]
          args = [
            "--ip-masq",
            "--kube-subnet-mgr"
          ]

          resources {
            requests = {
              cpu    = "100m"
              memory = "50Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "200Mi"
            }
          }

          security_context {
            privileged                 = true
            capabilities {
              add = ["NET_ADMIN", "NET_RAW"]
            }
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }

          env {
            name = "EVENT_QUEUE_DEPTH"
            value = "5000"
          }

          volume_mount {
            name       = "run"
            mount_path = "/run/flannel"
          }

          volume_mount {
            name       = "flannel-cfg"
            mount_path = "/etc/kube-flannel/"
          }

          volume_mount {
            name       = "xtables-lock"
            mount_path = "/run/xtables.lock"
          }
        }

        init_container {
          name  = "install-cni-plugin"
          image = "docker.io/flannel/flannel-cni-plugin:${var.flannel_cni_plugin_version}"

          command = ["cp"]
          args = [
            "-f",
            "/flannel",
            "/opt/cni/bin/flannel"
          ]

          volume_mount {
            name       = "cni-plugin"
            mount_path = "/opt/cni/bin"
          }
        }

        init_container {
          name  = "install-cni"
          image = "docker.io/flannel/flannel:${var.flannel_version}"

          command = ["cp"]
          args = [
            "-f",
            "/etc/kube-flannel/cni-conf.json",
            "/etc/cni/net.d/10-flannel.conflist"
          ]

          volume_mount {
            name       = "cni"
            mount_path = "/etc/cni/net.d"
          }

          volume_mount {
            name       = "flannel-cfg"
            mount_path = "/etc/kube-flannel/"
          }
        }

        volume {
          name = "run"
          host_path {
            path = "/run/flannel"
          }
        }

        volume {
          name = "cni-plugin"
          host_path {
            path = "/opt/cni/bin"
          }
        }

        volume {
          name = "cni"
          host_path {
            path = "/etc/cni/net.d"
          }
        }

        volume {
          name = "flannel-cfg"
          config_map {
            name = kubernetes_config_map.flannel_cfg.metadata[0].name
          }
        }

        volume {
          name = "xtables-lock"
          host_path {
            path = "/run/xtables.lock"
            type = "FileOrCreate"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.flannel,
    kubernetes_service_account.flannel,
    kubernetes_cluster_role.flannel,
    kubernetes_cluster_role_binding.flannel,
    kubernetes_config_map.flannel_cfg
  ]
}

# Outputs
output "flannel_info" {
  description = "Flannel CNI network plugin information"
  value = {
    namespace         = kubernetes_namespace.flannel.metadata[0].name
    service_account   = kubernetes_service_account.flannel.metadata[0].name
    daemonset         = kubernetes_daemonset.flannel.metadata[0].name
    network_cidr      = var.flannel_network_cidr
    flannel_version   = var.flannel_version
    cni_plugin_version = var.flannel_cni_plugin_version
    backend_type      = "vxlan"
    commands = {
      check_pods     = "kubectl get pods -n ${kubernetes_namespace.flannel.metadata[0].name}"
      check_nodes    = "kubectl get nodes -o wide"
      flannel_logs   = "kubectl logs -n ${kubernetes_namespace.flannel.metadata[0].name} -l app=flannel"
    }
  }
}
