# =============================================================================
# LocalAI Bundled Postgres (pgvector)
# =============================================================================
# Required by LocalAI distributed mode for: node registry, job store, auth,
# and agent-pool vector engine. The image is Mudler's pgvector-enabled build
# (pinned tag from upstream docker-compose.distributed.yaml).
# =============================================================================

resource "kubernetes_secret" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  metadata {
    name      = "localai-postgres"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    POSTGRES_USER     = "localai"
    POSTGRES_DB       = "localai"
    POSTGRES_PASSWORD = var.localai_postgres_password
    DATABASE_URL      = "postgresql://localai:${var.localai_postgres_password}@localai-postgres:5432/localai?sslmode=disable"
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
  ]

  metadata {
    name      = "localai-postgres-data"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.localai_postgres_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.localai_postgres,
    kubernetes_secret.localai_postgres,
    helm_release.longhorn,
  ]

  metadata {
    name      = "localai-postgres"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-postgres"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "localai-postgres" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai-postgres" })
      }

      spec {
        security_context {
          run_as_user  = 999
          run_as_group = 999
          fs_group     = 999
        }

        container {
          name  = "postgres"
          image = "quay.io/mudler/localrecall:v0.5.5-postgresql"

          port {
            container_port = 5432
            name           = "postgres"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.localai_postgres[0].metadata[0].name
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql"
            sub_path   = "pgdata"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "localai"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "localai"]
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = "256Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_postgres[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "localai_postgres" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.localai_postgres]

  metadata {
    name      = "localai-postgres"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "localai-postgres" }

    port {
      protocol    = "TCP"
      port        = 5432
      target_port = 5432
    }
  }
}
