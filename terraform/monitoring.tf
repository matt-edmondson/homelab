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
                storageClassName = "longhorn"
                accessModes      = ["ReadWriteOnce"]
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
          type = "LoadBalancer"
        }
      }
      grafana = {
        adminPassword = var.grafana_admin_password
        persistence = {
          enabled          = true
          storageClassName = "longhorn"
          size             = var.grafana_storage_size
        }
        service = {
          type = "LoadBalancer"
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
          default = {
            "kubernetes-cluster-monitoring" = {
              gnetId     = 7249
              datasource = "Prometheus"
            }
            "node-exporter-full" = {
              gnetId     = 1860
              datasource = "Prometheus"
            }
            "longhorn" = {
              gnetId     = 13032
              datasource = "Prometheus"
            }
          }
        }
      }
      alertmanager = {
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "longhorn"
                accessModes      = ["ReadWriteOnce"]
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

  depends_on = [kubernetes_storage_class.longhorn]
}
