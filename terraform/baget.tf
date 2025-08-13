# =============================================================================
# Baget NuGet Server - Self-Contained Module  
# =============================================================================

# Variables
variable "baget_api_key" {
  description = "API key for Baget NuGet server (generate a secure random key)"
  type        = string
  sensitive   = true
  default     = "your-secure-api-key-here"
}

variable "baget_storage_size" {
  description = "Storage size for Baget data"
  type        = string
  default     = "10Gi"
}

variable "baget_memory_request" {
  description = "Memory request for Baget container"
  type        = string
  default     = "256Mi"
}

variable "baget_memory_limit" {
  description = "Memory limit for Baget container"
  type        = string
  default     = "512Mi"
}

variable "baget_cpu_request" {
  description = "CPU request for Baget container"
  type        = string
  default     = "250m"
}

variable "baget_cpu_limit" {
  description = "CPU limit for Baget container"
  type        = string
  default     = "500m"
}

# Namespace
resource "kubernetes_namespace" "baget" {
  metadata {
    name = "baget"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
  }
}

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
      ApiKey                  = ""  # Set via environment variable
    })
  }
}

# Baget Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "baget_data" {
  metadata {
    name      = "baget-data"
    namespace = kubernetes_namespace.baget.metadata[0].name
    labels    = var.common_labels
  }
  
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.baget_storage_size
      }
    }
  }
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
            name  = "ASPNETCORE_URLS"
            value = "http://+:80"
          }
          
          env {
            name  = "ASPNETCORE_ENVIRONMENT"
            value = "Production"
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

# Baget LoadBalancer Service (gets DHCP IP from kube-vip)
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

# Outputs
output "baget_info" {
  description = "Baget NuGet server information"
  value = {
    namespace     = kubernetes_namespace.baget.metadata[0].name
    service_name  = kubernetes_service.baget.metadata[0].name
    storage_size  = var.baget_storage_size
    ip_address    = try(
      kubernetes_service.baget.status[0].load_balancer[0].ingress[0].ip,
      "pending (will be assigned by router DHCP)"
    )
    
    access = {
      web_ui = "Access Baget at: http://<dhcp-assigned-ip>"
      nuget_url = "http://<dhcp-assigned-ip>/v3/index.json"
    }
    
    usage = {
      add_source = "dotnet nuget add source http://<dhcp-assigned-ip>/v3/index.json -n \"Homelab Baget\""
      push_package = "dotnet nuget push package.nupkg -s http://<dhcp-assigned-ip>/v3/index.json -k <your-api-key>"
    }
    
    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.baget.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.baget.metadata[0].name}"
      get_ip     = "kubectl get svc -n ${kubernetes_namespace.baget.metadata[0].name} baget-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
      logs       = "kubectl logs -n ${kubernetes_namespace.baget.metadata[0].name} -l app=baget -f"
    }
  }
  
  sensitive = true  # Contains API key info
}
