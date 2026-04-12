# =============================================================================
# ClaudeCluster — Self-Hosted Claude Code Sandbox Platform
# =============================================================================
# Static infrastructure for the ClaudeCluster management backend.
# Sandbox pods and their per-sandbox resources (PVCs, Services, IngressRoutes)
# are created dynamically by the backend at runtime — not here.
# =============================================================================

# Variables
variable "claudecluster_enabled" {
  description = "Enable ClaudeCluster sandbox platform"
  type        = bool
  default     = true
}

variable "anthropic_api_key" {
  description = "Anthropic API key injected into sandbox pods as a Secret"
  type        = string
  sensitive   = true
  default     = ""
}

variable "claudecluster_backend_image_tag" {
  description = "Image tag for the ClaudeCluster backend"
  type        = string
  default     = "latest"
}

variable "claudecluster_sandbox_image_tag" {
  description = "Image tag for the ClaudeCluster sandbox container"
  type        = string
  default     = "latest"
}

variable "claudecluster_agent_image_tag" {
  description = "Image tag for the ClaudeCluster agent sidecar"
  type        = string
  default     = "latest"
}

# Namespace — management backend lives here
resource "kubernetes_namespace" "claude_sandbox" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name = "claude-sandbox"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "claude-sandbox"
    })
  }
}

# Namespace — sandbox pods, PVCs, Services, and IngressRoutes live here
resource "kubernetes_namespace" "claude_sandboxes" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name = "claude-sandboxes"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "claude-sandboxes"
    })
  }
}

# ServiceAccount for the backend pod
resource "kubernetes_service_account" "claudecluster_backend" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name      = "claudecluster-backend"
    namespace = kubernetes_namespace.claude_sandbox[0].metadata[0].name
    labels    = var.common_labels
  }

  depends_on = [kubernetes_namespace.claude_sandbox]
}

# Role — namespace-scoped to claude-sandboxes (backend only manages resources there)
resource "kubernetes_role" "claudecluster_backend" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name      = "claudecluster-backend"
    namespace = kubernetes_namespace.claude_sandboxes[0].metadata[0].name
    labels    = var.common_labels
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["persistentvolumeclaims", "services"]
    verbs      = ["get", "list", "create", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "create", "update"]
  }

  rule {
    api_groups = ["traefik.io"]
    resources  = ["ingressroutes"]
    verbs      = ["get", "list", "create", "delete"]
  }

  depends_on = [kubernetes_namespace.claude_sandboxes]
}

resource "kubernetes_role_binding" "claudecluster_backend" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name      = "claudecluster-backend"
    namespace = kubernetes_namespace.claude_sandboxes[0].metadata[0].name
    labels    = var.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.claudecluster_backend[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.claudecluster_backend[0].metadata[0].name
    namespace = kubernetes_namespace.claude_sandbox[0].metadata[0].name
  }

  depends_on = [
    kubernetes_role.claudecluster_backend,
    kubernetes_service_account.claudecluster_backend,
  ]
}

# Anthropic API key secret — referenced by sandbox and agent containers
resource "kubernetes_secret" "anthropic_api_key" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name      = "anthropic-api-key"
    namespace = kubernetes_namespace.claude_sandboxes[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    key = var.anthropic_api_key
  }

  depends_on = [kubernetes_namespace.claude_sandboxes]
}

# Backend Deployment — management API + React SPA
resource "kubernetes_deployment" "claudecluster_backend" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name      = "claudecluster-backend"
    namespace = kubernetes_namespace.claude_sandbox[0].metadata[0].name
    labels = merge(var.common_labels, {
      app = "claudecluster-backend"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "RollingUpdate"
    }

    selector {
      match_labels = {
        app = "claudecluster-backend"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "claudecluster-backend"
        })
      }

      spec {
        service_account_name = kubernetes_service_account.claudecluster_backend[0].metadata[0].name

        container {
          name  = "backend"
          image = "ghcr.io/matt-edmondson/claudecluster/backend:${var.claudecluster_backend_image_tag}"

          port {
            container_port = 8080
          }

          env {
            name  = "PORT"
            value = "8080"
          }

          env {
            name  = "DOMAIN"
            value = var.traefik_domain
          }

          env {
            name  = "SANDBOXES_NAMESPACE"
            value = "claude-sandboxes"
          }

          env {
            name  = "SANDBOX_IMAGE"
            value = "ghcr.io/matt-edmondson/claudecluster/sandbox:${var.claudecluster_sandbox_image_tag}"
          }

          env {
            name  = "AGENT_IMAGE"
            value = "ghcr.io/matt-edmondson/claudecluster/agent:${var.claudecluster_agent_image_tag}"
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 15
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          resources {
            requests = {
              memory = "128Mi"
              cpu    = "50m"
            }
            limits = {
              memory = "256Mi"
              cpu    = "200m"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.claude_sandbox,
    kubernetes_service_account.claudecluster_backend,
    kubernetes_role_binding.claudecluster_backend,
  ]
}

# Service — ClusterIP; Traefik IngressRoute routes to port 80 → 8080
resource "kubernetes_service" "claudecluster_backend" {
  count = var.claudecluster_enabled ? 1 : 0

  metadata {
    name      = "claudecluster-backend"
    namespace = kubernetes_namespace.claude_sandbox[0].metadata[0].name
    labels = merge(var.common_labels, {
      app = "claudecluster-backend"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "claudecluster-backend"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
  }

  depends_on = [kubernetes_deployment.claudecluster_backend]
}
