# Baget Secret for API Key
resource "kubernetes_secret" "baget_secrets" {
  metadata {
    name      = "baget-secrets"
    namespace = kubernetes_namespace.baget.metadata[0].name
    labels    = var.common_labels
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
    labels    = var.common_labels
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
    labels    = var.common_labels
  }
  
  spec {
    access_modes = ["ReadWriteOnce"]
    storage_class_name = "longhorn"
    resources {
      requests = {
        storage = var.baget_storage_size
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
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
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
        labels = merge(var.common_labels, {
          app = "baget"
        })
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
              memory = var.baget_memory_request
              cpu    = var.baget_cpu_request
            }
            limits = {
              memory = var.baget_memory_limit
              cpu    = var.baget_cpu_limit
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
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
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
