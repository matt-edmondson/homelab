# =============================================================================
# Planning Poker - Self-Contained Module
# =============================================================================

# --- Variables ---

variable "poker_enabled" {
  description = "Enable Planning Poker deployment"
  type        = bool
  default     = true
}

variable "poker_image" {
  description = "Planning Poker container image"
  type        = string
  default     = "ghcr.io/matt-edmondson/planning-poker:latest"
}

variable "poker_image_pull_policy" {
  description = "Image pull policy for the Planning Poker container"
  type        = string
  default     = "Always"
}

variable "poker_postgres_storage_size" {
  description = "Persistent storage size for Planning Poker Postgres"
  type        = string
  default     = "2Gi"
}

variable "poker_postgres_password" {
  description = "Password for the bundled Planning Poker Postgres"
  type        = string
  sensitive   = true
}

variable "poker_admin_password" {
  description = "Admin password for Planning Poker (/admin login). Leave empty to disable the admin page."
  type        = string
  sensitive   = true
  default     = ""
}

variable "poker_memory_request" {
  type    = string
  default = "128Mi"
}

variable "poker_memory_limit" {
  type    = string
  default = "512Mi"
}

variable "poker_cpu_request" {
  type    = string
  default = "100m"
}

variable "poker_cpu_limit" {
  type    = string
  default = "500m"
}

# --- Namespace ---

resource "kubernetes_namespace" "poker" {
  count = var.poker_enabled ? 1 : 0

  metadata {
    name = "poker"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "poker"
    })
  }
}

# --- Postgres (bundled) ---

resource "kubernetes_secret" "poker_postgres" {
  count = var.poker_enabled ? 1 : 0

  metadata {
    name      = "poker-postgres"
    namespace = kubernetes_namespace.poker[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    POSTGRES_USER     = "poker"
    POSTGRES_DB       = "poker"
    POSTGRES_PASSWORD = var.poker_postgres_password
    DATABASE_URL      = "postgresql://poker:${var.poker_postgres_password}@poker-postgres:5432/poker"
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim" "poker_postgres" {
  count = var.poker_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
  ]

  metadata {
    name      = "poker-postgres-data"
    namespace = kubernetes_namespace.poker[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.poker_postgres_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "poker_postgres" {
  count = var.poker_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.poker_postgres,
    kubernetes_secret.poker_postgres,
    helm_release.longhorn,
  ]

  metadata {
    name      = "poker-postgres"
    namespace = kubernetes_namespace.poker[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "poker-postgres"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "poker-postgres"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "poker-postgres"
        })
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          port {
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.poker_postgres[0].metadata[0].name
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "poker"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "poker"]
            }
            initial_delay_seconds = 15
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.poker_postgres[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "poker_postgres" {
  count = var.poker_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.poker_postgres]

  metadata {
    name      = "poker-postgres"
    namespace = kubernetes_namespace.poker[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "poker-postgres"
    }
    port {
      protocol    = "TCP"
      port        = 5432
      target_port = 5432
    }
  }
}

# --- Application ---

resource "kubernetes_secret" "poker_admin" {
  count = var.poker_enabled && var.poker_admin_password != "" ? 1 : 0

  metadata {
    name      = "poker-admin"
    namespace = kubernetes_namespace.poker[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    ADMIN_PASSWORD = var.poker_admin_password
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "poker" {
  count = var.poker_enabled ? 1 : 0

  depends_on = [
    kubernetes_service.poker_postgres,
    kubernetes_secret.poker_postgres,
    kubernetes_secret.poker_admin,
  ]

  metadata {
    name      = "poker"
    namespace = kubernetes_namespace.poker[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "poker"
    })
    annotations = {
      "keel.sh/policy"       = "force"
      "keel.sh/trigger"      = "poll"
      "keel.sh/pollSchedule" = "@every 2m"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "poker"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "poker"
        })
      }

      spec {
        image_pull_secrets {
          name = "ghcr-pull-secret"
        }

        container {
          name              = "poker"
          image             = var.poker_image
          image_pull_policy = var.poker_image_pull_policy

          port {
            container_port = 3000
          }

          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.poker_postgres[0].metadata[0].name
                key  = "DATABASE_URL"
              }
            }
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "PORT"
            value = "3000"
          }

          dynamic "env" {
            for_each = var.poker_admin_password != "" ? [1] : []
            content {
              name = "ADMIN_PASSWORD"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.poker_admin[0].metadata[0].name
                  key  = "ADMIN_PASSWORD"
                }
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = var.poker_memory_request
              cpu    = var.poker_cpu_request
            }
            limits = {
              memory = var.poker_memory_limit
              cpu    = var.poker_cpu_limit
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "poker" {
  count = var.poker_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.poker]

  metadata {
    name      = "poker-service"
    namespace = kubernetes_namespace.poker[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "poker"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "poker"
    }
    port {
      protocol    = "TCP"
      port        = 3000
      target_port = 3000
    }
  }
}

# --- Outputs ---

output "poker_info" {
  description = "Planning Poker service information"
  value = var.poker_enabled ? {
    namespace    = kubernetes_namespace.poker[0].metadata[0].name
    service_name = kubernetes_service.poker[0].metadata[0].name
    access = {
      url = "https://poker.${var.traefik_domain}"
    }
    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.poker[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.poker[0].metadata[0].name} -l app=poker -f"
      db_shell   = "kubectl -n ${kubernetes_namespace.poker[0].metadata[0].name} exec -it deploy/poker-postgres -- psql -U poker"
    }
  } : null
  sensitive = true
}
