terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

# Create namespaces
resource "kubernetes_namespace" "metallb_system" {
  metadata {
    name = "metallb-system"
  }
}

resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace" "baget" {
  metadata {
    name = "baget"
  }
}

# MetalLB Installation
resource "helm_release" "metallb" {
  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = "0.14.5"
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
    }
    spec = {
      ipAddressPools = ["default-pool"]
    }
  }
  depends_on = [kubernetes_manifest.metallb_ipaddresspool]
}

# Longhorn Installation
resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = "1.6.2"
  namespace  = kubernetes_namespace.longhorn_system.metadata[0].name

  set {
    name  = "defaultSettings.defaultReplicaCount"
    value = "2"
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
  }
  storage_provisioner    = "driver.longhorn.io"
  allow_volume_expansion = true
  reclaim_policy        = "Delete"
  volume_binding_mode   = "Immediate"
  
  parameters = {
    numberOfReplicas       = "2"
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

# Prometheus & Grafana Stack using kube-prometheus-stack
resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "57.2.0"
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
                    storage = "20Gi"
                  }
                }
              }
            }
          }
          retention = "15d"
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
          size             = "10Gi"
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
                    storage = "5Gi"
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

# Baget Secret for API Key
resource "kubernetes_secret" "baget_secrets" {
  metadata {
    name      = "baget-secrets"
    namespace = kubernetes_namespace.baget.metadata[0].name
  }
  
  data = {
    ApiKey = base64encode(var.baget_api_key)
  }
  
  type = "Opaque"
}

# Baget ConfigMap
resource "kubernetes_config_map" "baget_config" {
  metadata {
    name      = "baget-config"
    namespace = kubernetes_namespace.baget.metadata[0].name
  }
  
  data = {
    "appsettings.json" = jsonencode({
      Database = {
        Type             = "Sqlite"
        ConnectionString = "Data Source=/app/data/baget.db"
      }
      Storage = {
        Type = "FileSystem"
        Path = "/app/data/packages"
      }
      Search = {
        Type = "Database"
      }
      Mirror = {
        Enabled = false
      }
      PackageDeletionBehavior = "Unlist"
      AllowPackageOverwrites  = false
      ApiKey                  = ""
    })
  }
}

# Baget PVC
resource "kubernetes_persistent_volume_claim" "baget_data" {
  metadata {
    name      = "baget-data"
    namespace = kubernetes_namespace.baget.metadata[0].name
  }
  
  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
  
  depends_on = [kubernetes_storage_class.longhorn]
}

# Baget Deployment
resource "kubernetes_deployment" "baget" {
  metadata {
    name      = "baget"
    namespace = kubernetes_namespace.baget.metadata[0].name
    labels = {
      app = "baget"
    }
  }
  
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "baget"
      }
    }
    
    template {
      metadata {
        labels = {
          app = "baget"
        }
      }
      
      spec {
        container {
          name  = "baget"
          image = "loicsharma/baget:latest"
          
          port {
            container_port = 80
          }
          
          env {
            name  = "ASPNETCORE_ENVIRONMENT"
            value = "Production"
          }
          
          env {
            name  = "ASPNETCORE_URLS"
            value = "http://+:80"
          }
          
          env {
            name = "ApiKey"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.baget_secrets.metadata[0].name
                key  = "ApiKey"
              }
            }
          }
          
          volume_mount {
            name       = "baget-data"
            mount_path = "/app/data"
          }
          
          volume_mount {
            name       = "baget-config"
            mount_path = "/app/appsettings.json"
            sub_path   = "appsettings.json"
          }
          
          resources {
            requests = {
              memory = "256Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
          
          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          
          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
        
        volume {
          name = "baget-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.baget_data.metadata[0].name
          }
        }
        
        volume {
          name = "baget-config"
          config_map {
            name = kubernetes_config_map.baget_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Baget Service
resource "kubernetes_service" "baget" {
  metadata {
    name      = "baget-service"
    namespace = kubernetes_namespace.baget.metadata[0].name
    labels = {
      app = "baget"
    }
  }
  
  spec {
    selector = {
      app = "baget"
    }
    
    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
    
    type = "LoadBalancer"
  }
}
