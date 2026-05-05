# =============================================================================
# Flaresolverr — CAPTCHA/Cloudflare Bypass Proxy
# =============================================================================
# Runs a headless Chromium instance to solve CAPTCHAs for Prowlarr indexers.
# Internal-only: no IngressRoute or DNS record.
# Prowlarr connects via: flaresolverr-service.flaresolverr.svc.cluster.local:8191
# =============================================================================

# Variables
variable "flaresolverr_enabled" {
  description = "Enable Flaresolverr deployment"
  type        = bool
  default     = true
}

variable "flaresolverr_memory_request" {
  description = "Memory request for Flaresolverr container"
  type        = string
  default     = "256Mi"
}

variable "flaresolverr_memory_limit" {
  description = "Memory limit for Flaresolverr container"
  type        = string
  default     = "1Gi"
}

variable "flaresolverr_cpu_request" {
  description = "CPU request for Flaresolverr container"
  type        = string
  default     = "100m"
}

variable "flaresolverr_cpu_limit" {
  description = "CPU limit for Flaresolverr container"
  type        = string
  default     = "1000m"
}

variable "flaresolverr_image_tag" {
  description = "Flaresolverr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "flaresolverr" {
  count = var.flaresolverr_enabled ? 1 : 0

  metadata {
    name = "flaresolverr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flaresolverr"
    })
  }
}

# Deployment (stateless — no PVC)
resource "kubernetes_deployment" "flaresolverr" {
  count = var.flaresolverr_enabled ? 1 : 0

  metadata {
    name      = "flaresolverr"
    namespace = kubernetes_namespace.flaresolverr[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flaresolverr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "flaresolverr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "flaresolverr"
        })
      }

      spec {
        container {
          name  = "flaresolverr"
          image = "ghcr.io/flaresolverr/flaresolverr:${var.flaresolverr_image_tag}"

          port {
            container_port = 8191
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          env {
            name  = "LOG_LEVEL"
            value = "info"
          }

          resources {
            requests = {
              memory = var.flaresolverr_memory_request
              cpu    = var.flaresolverr_cpu_request
            }
            limits = {
              memory = var.flaresolverr_memory_limit
              cpu    = var.flaresolverr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8191
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8191
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# Service (internal-only — no IngressRoute)
resource "kubernetes_service" "flaresolverr" {
  count = var.flaresolverr_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.flaresolverr
  ]

  metadata {
    name      = "flaresolverr-service"
    namespace = kubernetes_namespace.flaresolverr[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flaresolverr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "flaresolverr"
    }

    port {
      protocol    = "TCP"
      port        = 8191
      target_port = 8191
    }
  }
}

# Outputs
output "flaresolverr_info" {
  description = "Flaresolverr CAPTCHA solver information"
  value = var.flaresolverr_enabled ? {
    namespace     = kubernetes_namespace.flaresolverr[0].metadata[0].name
    service_name  = kubernetes_service.flaresolverr[0].metadata[0].name
    cluster_dns   = "flaresolverr-service.${kubernetes_namespace.flaresolverr[0].metadata[0].name}.svc.cluster.local:8191"
    internal_only = true

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.flaresolverr[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.flaresolverr[0].metadata[0].name} -l app=flaresolverr -f"
      test       = "kubectl exec -n ${kubernetes_namespace.flaresolverr[0].metadata[0].name} -it deploy/flaresolverr -- wget -qO- http://localhost:8191/health"
    }
  } : null
}
