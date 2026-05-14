# =============================================================================
# LocalAI Bundled NATS (JetStream)
# =============================================================================
# Real-time coordination plane for LocalAI distributed mode: job queue,
# backend.install events, file-transfer signalling.
# =============================================================================

resource "kubernetes_persistent_volume_claim" "localai_nats" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
  ]

  metadata {
    name      = "localai-nats-data"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.localai_nats_storage_size
      }
    }
  }
}

resource "kubernetes_deployment" "localai_nats" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.localai_nats,
    helm_release.longhorn,
  ]

  metadata {
    name      = "localai-nats"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "localai-nats"
    })
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = { app = "localai-nats" }
    }

    template {
      metadata {
        labels = merge(var.common_labels, { app = "localai-nats" })
      }

      spec {
        container {
          name  = "nats"
          image = "nats:2-alpine"

          args = ["--js", "-m", "8222", "--store_dir", "/data/jetstream"]

          port {
            container_port = 4222
            name           = "client"
          }

          port {
            container_port = 8222
            name           = "monitor"
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          readiness_probe {
            tcp_socket {
              port = 4222
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            tcp_socket {
              port = 4222
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "512Mi"
              cpu    = "500m"
            }
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.localai_nats[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "localai_nats" {
  count = var.localai_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.localai_nats]

  metadata {
    name      = "localai-nats"
    namespace = kubernetes_namespace.localai[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "localai-nats" }

    port {
      name        = "client"
      protocol    = "TCP"
      port        = 4222
      target_port = 4222
    }

    port {
      name        = "monitor"
      protocol    = "TCP"
      port        = 8222
      target_port = 8222
    }
  }
}
