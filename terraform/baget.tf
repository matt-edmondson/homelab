# =============================================================================
# Baget NuGet Server - Self-Contained Module
# =============================================================================

# Variables
variable "baget_enabled" {
  description = "Enable BaGet NuGet server deployment"
  type        = bool
  default     = true
}

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
  default     = "384Mi"
}

variable "baget_memory_limit" {
  description = "Memory limit for Baget container"
  type        = string
  default     = "1Gi"
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
  count = var.baget_enabled ? 1 : 0

  metadata {
    name = "baget"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
  }
}

# Baget Secret for API Key
resource "kubernetes_secret" "baget_secrets" {
  count = var.baget_enabled ? 1 : 0

  metadata {
    name      = "baget-secrets"
    namespace = kubernetes_namespace.baget[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    ApiKey = var.baget_api_key
  }

  type = "Opaque"
}

# Baget ConfigMap
resource "kubernetes_config_map" "baget_config" {
  count = var.baget_enabled ? 1 : 0

  metadata {
    name      = "baget-config"
    namespace = kubernetes_namespace.baget[0].metadata[0].name
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
      ApiKey                  = "" # Set via environment variable
    })
  }
}

# Baget Persistent Volume Claim
resource "kubernetes_persistent_volume_claim" "baget_data" {
  count = var.baget_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,                 # Ensure storage backend is available
    data.kubernetes_storage_class.longhorn # Ensure default storage class exists
  ]

  metadata {
    name      = "baget-data"
    namespace = kubernetes_namespace.baget[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.baget_storage_size
      }
    }
  }
}

# Baget Deployment
resource "kubernetes_deployment" "baget" {
  count = var.baget_enabled ? 1 : 0

  # Ensure storage, secrets, and config are ready
  depends_on = [
    kubernetes_persistent_volume_claim.baget_data,
    kubernetes_secret.baget_secrets,
    kubernetes_config_map.baget_config,
    helm_release.longhorn # Ensure storage backend is available
  ]

  metadata {
    name      = "baget"
    namespace = kubernetes_namespace.baget[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

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
                name = kubernetes_secret.baget_secrets[0].metadata[0].name
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
              path = "/v3/index.json"
              port = 80
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 15
            failure_threshold     = 6
          }

          readiness_probe {
            http_get {
              path = "/v3/index.json"
              port = 80
            }
            initial_delay_seconds = 15
            period_seconds        = 30
            timeout_seconds       = 15
            failure_threshold     = 6
          }
        }

        volume {
          name = "baget-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.baget_data[0].metadata[0].name
          }
        }

        volume {
          name = "baget-config"
          config_map {
            name = kubernetes_config_map.baget_config[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Baget Service
resource "kubernetes_service" "baget" {
  count = var.baget_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.baget
  ]

  metadata {
    name      = "baget-service"
    namespace = kubernetes_namespace.baget[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "baget"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }
}

# Outputs
output "baget_info" {
  description = "Baget NuGet server information"
  value = var.baget_enabled ? {
    namespace    = kubernetes_namespace.baget[0].metadata[0].name
    service_name = kubernetes_service.baget[0].metadata[0].name
    storage_size = var.baget_storage_size

    access = {
      web_ui    = "https://packages.${var.traefik_domain}"
      nuget_url = "https://packages.${var.traefik_domain}/v3/index.json"
    }

    usage = {
      add_source   = "dotnet nuget add source https://packages.${var.traefik_domain}/v3/index.json -n \"Homelab Baget\""
      push_package = "dotnet nuget push package.nupkg -s https://packages.${var.traefik_domain}/v3/index.json -k <your-api-key>"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.baget[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.baget[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.baget[0].metadata[0].name} -l app=baget -f"
    }
  } : null

  sensitive = true
}
