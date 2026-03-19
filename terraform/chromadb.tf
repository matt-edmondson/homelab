# =============================================================================
# ChromaDB — Vector Database
# =============================================================================
# Python-native vector database for RAG prototyping and experimentation.
# REST API on port 8000. CPU-only, no GPU required.
# Longhorn PVC for persistent vector data storage.
# =============================================================================

# Variables
variable "chromadb_enabled" {
  description = "Enable ChromaDB deployment"
  type        = bool
  default     = true
}

variable "chromadb_storage_size" {
  description = "Storage size for ChromaDB data"
  type        = string
  default     = "4Gi"
}

variable "chromadb_memory_request" {
  description = "Memory request for ChromaDB container"
  type        = string
  default     = "256Mi"
}

variable "chromadb_memory_limit" {
  description = "Memory limit for ChromaDB container"
  type        = string
  default     = "1Gi"
}

variable "chromadb_cpu_request" {
  description = "CPU request for ChromaDB container"
  type        = string
  default     = "100m"
}

variable "chromadb_cpu_limit" {
  description = "CPU limit for ChromaDB container"
  type        = string
  default     = "1000m"
}

variable "chromadb_image_tag" {
  description = "ChromaDB container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "chromadb" {
  count = var.chromadb_enabled ? 1 : 0

  metadata {
    name = "chromadb"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "chromadb"
    })
  }
}

# Persistent Volume Claim — Data (Longhorn)
resource "kubernetes_persistent_volume_claim" "chromadb_data" {
  count = var.chromadb_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "chromadb-data"
    namespace = kubernetes_namespace.chromadb[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.chromadb_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "chromadb" {
  count = var.chromadb_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.chromadb_data,
    helm_release.longhorn
  ]

  metadata {
    name      = "chromadb"
    namespace = kubernetes_namespace.chromadb[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "chromadb"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "chromadb"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "chromadb"
        })
      }

      spec {
        container {
          name  = "chromadb"
          image = "chromadb/chroma:${var.chromadb_image_tag}"

          port {
            container_port = 8000
            name           = "http"
          }

          env {
            name  = "IS_PERSISTENT"
            value = "TRUE"
          }

          env {
            name  = "PERSIST_DIRECTORY"
            value = "/chroma/chroma"
          }

          env {
            name  = "ANONYMIZED_TELEMETRY"
            value = "FALSE"
          }

          volume_mount {
            name       = "chromadb-data"
            mount_path = "/chroma/chroma"
          }

          resources {
            requests = {
              memory = var.chromadb_memory_request
              cpu    = var.chromadb_cpu_request
            }
            limits = {
              memory = var.chromadb_memory_limit
              cpu    = var.chromadb_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/api/v2/heartbeat"
              port = 8000
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            failure_threshold     = 5
          }

          readiness_probe {
            http_get {
              path = "/api/v2/heartbeat"
              port = 8000
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "chromadb-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.chromadb_data[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "chromadb" {
  count = var.chromadb_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.chromadb
  ]

  metadata {
    name      = "chromadb-service"
    namespace = kubernetes_namespace.chromadb[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "chromadb"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "chromadb"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8000
    }
  }
}

# Outputs
output "chromadb_info" {
  description = "ChromaDB vector database information"
  value = var.chromadb_enabled ? {
    namespace    = kubernetes_namespace.chromadb[0].metadata[0].name
    service_name = kubernetes_service.chromadb[0].metadata[0].name
    storage_size = var.chromadb_storage_size

    access = {
      web_ui      = "https://chromadb.${var.traefik_domain}"
      cluster_api = "chromadb-service.${kubernetes_namespace.chromadb[0].metadata[0].name}.svc.cluster.local:80"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.chromadb[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.chromadb[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.chromadb[0].metadata[0].name} -l app=chromadb -f"
    }
  } : null

  sensitive = true
}
