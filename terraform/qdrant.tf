# =============================================================================
# Qdrant — Vector Database
# =============================================================================
# Production-grade vector search engine for RAG pipelines and similarity search.
# REST API on port 6333, gRPC on port 6334. CPU-only, no GPU required.
# Longhorn PVC for persistent vector data storage.
# =============================================================================

# Variables
variable "qdrant_storage_size" {
  description = "Storage size for Qdrant data"
  type        = string
  default     = "4Gi"
}

variable "qdrant_memory_request" {
  description = "Memory request for Qdrant container"
  type        = string
  default     = "256Mi"
}

variable "qdrant_memory_limit" {
  description = "Memory limit for Qdrant container"
  type        = string
  default     = "1Gi"
}

variable "qdrant_cpu_request" {
  description = "CPU request for Qdrant container"
  type        = string
  default     = "100m"
}

variable "qdrant_cpu_limit" {
  description = "CPU limit for Qdrant container"
  type        = string
  default     = "1000m"
}

variable "qdrant_image_tag" {
  description = "Qdrant container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "qdrant" {
  metadata {
    name = "qdrant"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qdrant"
    })
  }
}

# Persistent Volume Claim — Data (Longhorn)
resource "kubernetes_persistent_volume_claim" "qdrant_data" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "qdrant-data"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.qdrant_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "qdrant" {
  depends_on = [
    kubernetes_persistent_volume_claim.qdrant_data,
    helm_release.longhorn
  ]

  metadata {
    name      = "qdrant"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qdrant"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "qdrant"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "qdrant"
        })
      }

      spec {
        container {
          name  = "qdrant"
          image = "qdrant/qdrant:${var.qdrant_image_tag}"

          port {
            container_port = 6333
            name           = "rest"
          }

          port {
            container_port = 6334
            name           = "grpc"
          }

          volume_mount {
            name       = "qdrant-data"
            mount_path = "/qdrant/storage"
          }

          resources {
            requests = {
              memory = var.qdrant_memory_request
              cpu    = var.qdrant_cpu_request
            }
            limits = {
              memory = var.qdrant_memory_limit
              cpu    = var.qdrant_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 6333
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = 6333
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "qdrant-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.qdrant_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "qdrant" {
  depends_on = [
    kubernetes_deployment.qdrant
  ]

  metadata {
    name      = "qdrant-service"
    namespace = kubernetes_namespace.qdrant.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "qdrant"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "qdrant"
    }

    port {
      name        = "rest"
      protocol    = "TCP"
      port        = 80
      target_port = 6333
    }

    port {
      name        = "grpc"
      protocol    = "TCP"
      port        = 6334
      target_port = 6334
    }
  }
}

# Outputs
output "qdrant_info" {
  description = "Qdrant vector database information"
  value = {
    namespace    = kubernetes_namespace.qdrant.metadata[0].name
    service_name = kubernetes_service.qdrant.metadata[0].name
    storage_size = var.qdrant_storage_size

    access = {
      web_ui       = "https://qdrant.${var.traefik_domain}"
      cluster_rest = "qdrant-service.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local:80"
      cluster_grpc = "qdrant-service.${kubernetes_namespace.qdrant.metadata[0].name}.svc.cluster.local:6334"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.qdrant.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.qdrant.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.qdrant.metadata[0].name} -l app=qdrant -f"
    }
  }

  sensitive = true
}
