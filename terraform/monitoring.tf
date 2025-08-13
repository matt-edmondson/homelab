# =============================================================================
# Prometheus & Grafana Monitoring Stack - Self-Contained Module
# =============================================================================

# Variables
variable "prometheus_stack_chart_version" {
  description = "Version of kube-prometheus-stack Helm chart"
  type        = string
  default     = "76.3.0"
}

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus data"
  type        = string
  default     = "20Gi"
}

variable "prometheus_retention" {
  description = "Data retention period for Prometheus"
  type        = string
  default     = "15d"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana data"
  type        = string
  default     = "10Gi"
}

variable "alertmanager_storage_size" {
  description = "Storage size for AlertManager data"
  type        = string
  default     = "5Gi"
}

variable "enable_storage_dashboards" {
  description = "Enable storage system dashboards (e.g., Longhorn)"
  type        = bool
  default     = true
}

# Namespace
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "monitoring"
    })
  }
}

# Prometheus & Grafana Stack using kube-prometheus-stack
resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes      = ["ReadWriteOnce"]
                storageClassName = kubernetes_storage_class.longhorn.metadata[0].name
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }
          retention = var.prometheus_retention
        }
        service = {
          type           = "LoadBalancer"
          loadBalancerIP = "0.0.0.0"  # Trigger kube-vip DHCP behavior
          annotations = {
            "kube-vip.io/loadbalancerHostname" = "prometheus"
          }
        }
      }
      grafana = {
        adminPassword = var.grafana_admin_password
        persistence = {
          enabled          = true
          storageClassName = kubernetes_storage_class.longhorn.metadata[0].name
          size             = var.grafana_storage_size
        }
        service = {
          type           = "LoadBalancer"
          loadBalancerIP = "0.0.0.0"  # Trigger kube-vip DHCP behavior
          annotations = {
            "kube-vip.io/loadbalancerHostname" = "grafana"
          }
        }
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [{
              name            = "default"
              orgId           = 1
              folder          = ""
              type            = "file"
              disableDeletion = false
              editable        = true
              options = {
                path = "/var/lib/grafana/dashboards/default"
              }
            }]
          }
        }
        dashboards = {
          default = merge({
            "kubernetes-cluster-monitoring" = {
              gnetId     = 7249
              datasource = "Prometheus"
            }
            "node-exporter-full" = {
              gnetId     = 1860
              datasource = "Prometheus"
            }
          }, var.enable_storage_dashboards ? {
            "storage-system" = {
              gnetId     = 13032  # Generic storage dashboard (works with Longhorn, etc.)
              datasource = "Prometheus"
            }
          } : {})
        }
      }
      alertmanager = {
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                accessModes      = ["ReadWriteOnce"]
                storageClassName = kubernetes_storage_class.longhorn.metadata[0].name
                resources = {
                  requests = {
                    storage = var.alertmanager_storage_size
                  }
                }
              }
            }
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    helm_release.longhorn,  # Ensure storage backend is available
    kubernetes_storage_class.longhorn,  # Ensure default storage class exists
    kubernetes_daemonset.kube_vip  # Ensure LoadBalancer support is available
  ]
}

# Outputs
output "monitoring_info" {
  description = "Monitoring stack information"
  value = {
    namespace          = kubernetes_namespace.monitoring.metadata[0].name
    chart_version      = var.prometheus_stack_chart_version
    prometheus_storage = var.prometheus_storage_size
    grafana_storage    = var.grafana_storage_size
    retention_period   = var.prometheus_retention
    
    services = {
      prometheus = "${helm_release.prometheus_stack.name}-kube-prom-prometheus"
      grafana    = "${helm_release.prometheus_stack.name}-grafana"
    }
    
    access = {
      prometheus = "Access Prometheus at: http://<dhcp-assigned-ip>:9090"
      grafana    = "Access Grafana at: http://<dhcp-assigned-ip> (admin/${var.grafana_admin_password})"
    }
    
    commands = {
      check_pods     = "kubectl get pods -n ${kubernetes_namespace.monitoring.metadata[0].name}"
      check_services = "kubectl get svc -n ${kubernetes_namespace.monitoring.metadata[0].name}"
      get_grafana_ip = "kubectl get svc -n ${kubernetes_namespace.monitoring.metadata[0].name} ${helm_release.prometheus_stack.name}-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
      get_prometheus_ip = "kubectl get svc -n ${kubernetes_namespace.monitoring.metadata[0].name} ${helm_release.prometheus_stack.name}-kube-prom-prometheus -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
    }
  }
  
  sensitive = true  # Contains password
}