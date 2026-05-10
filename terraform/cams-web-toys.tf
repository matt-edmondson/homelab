# =============================================================================
# Cams Web Toys - Self-Contained Module
# =============================================================================
# Cameron's collection of mini web apps (the wheel, quizzifier, planning poker,
# standup, folio, life-checklist). Single Nuxt 3 SPA + socket.io server.
# Stateless — rooms live in process memory.
#
# Each toy gets its own subdomain via per-toy enable/subdomain variables. All
# subdomains route to the same Service; the SPA's `host-redirect.client.js`
# plugin maps the leftmost host label to the matching page on first load.
#
# Distinct from `poker.tf`, which deploys a different (Postgres-backed) planning
# poker app at `poker.${traefik_domain}`.
# =============================================================================

# --- Variables ---

variable "cams_web_toys_enabled" {
  description = "Enable cams-web-toys deployment (Namespace, Deployment, Service)"
  type        = bool
  default     = true
}

variable "cams_web_toys_image" {
  description = "cams-web-toys container image"
  type        = string
  default     = "ghcr.io/matt-edmondson/cams-web-toys:latest"
}

variable "cams_web_toys_image_pull_policy" {
  description = "Image pull policy for the cams-web-toys container"
  type        = string
  default     = "Always"
}

variable "cams_web_toys_memory_request" {
  type    = string
  default = "128Mi"
}

variable "cams_web_toys_memory_limit" {
  type    = string
  default = "512Mi"
}

variable "cams_web_toys_cpu_request" {
  type    = string
  default = "100m"
}

variable "cams_web_toys_cpu_limit" {
  type    = string
  default = "500m"
}

# --- Per-toy subdomain toggles ---
# Each *_enabled flag controls one IngressRoute (in ingress.tf) and one Azure
# DNS A record (in dns.tf). The *_subdomain string is the leftmost host label,
# combined with var.traefik_domain.

# pages/index.vue — landing page listing all toys
variable "cams_web_toys_hub_enabled" {
  type    = bool
  default = false
}
variable "cams_web_toys_hub_subdomain" {
  type    = string
  default = "toys"
}

# /the-wheel
variable "cams_web_toys_wheel_enabled" {
  type    = bool
  default = false
}
variable "cams_web_toys_wheel_subdomain" {
  type    = string
  default = "wheel"
}

# /quizzifier
variable "cams_web_toys_quiz_enabled" {
  type    = bool
  default = false
}
variable "cams_web_toys_quiz_subdomain" {
  type    = string
  default = "quiz"
}

# /planning-poker — the cams-web-toys homemade one. `poker.tf` already owns
# `poker.${traefik_domain}` for the polished planning-poker app, so this
# defaults to `artisanal-poker` to disambiguate.
variable "cams_web_toys_poker_enabled" {
  type    = bool
  default = true
}
variable "cams_web_toys_poker_subdomain" {
  type    = string
  default = "artisanal-poker"
}

# /standup
variable "cams_web_toys_standup_enabled" {
  type    = bool
  default = false
}
variable "cams_web_toys_standup_subdomain" {
  type    = string
  default = "standup"
}

# /folio
variable "cams_web_toys_folio_enabled" {
  type    = bool
  default = false
}
variable "cams_web_toys_folio_subdomain" {
  type    = string
  default = "folio"
}

# /life-checklist (commented out of the hub; off by default)
variable "cams_web_toys_checklist_enabled" {
  type    = bool
  default = false
}
variable "cams_web_toys_checklist_subdomain" {
  type    = string
  default = "checklist"
}

# Map of `<toy-key> => <subdomain>` for enabled toys. Consumed by the
# IngressRoute for_each in ingress.tf and by the dns_records merge in dns.tf
# (via cams_web_toys_dns_records, which prefixes the keys to dodge collision
# with sibling modules in the global merge).
locals {
  cams_web_toys_subdomains = var.cams_web_toys_enabled ? merge(
    var.cams_web_toys_hub_enabled ? { hub = var.cams_web_toys_hub_subdomain } : {},
    var.cams_web_toys_wheel_enabled ? { wheel = var.cams_web_toys_wheel_subdomain } : {},
    var.cams_web_toys_quiz_enabled ? { quiz = var.cams_web_toys_quiz_subdomain } : {},
    var.cams_web_toys_poker_enabled ? { poker = var.cams_web_toys_poker_subdomain } : {},
    var.cams_web_toys_standup_enabled ? { standup = var.cams_web_toys_standup_subdomain } : {},
    var.cams_web_toys_folio_enabled ? { folio = var.cams_web_toys_folio_subdomain } : {},
    var.cams_web_toys_checklist_enabled ? { checklist = var.cams_web_toys_checklist_subdomain } : {},
  ) : {}

  cams_web_toys_dns_records = { for k, v in local.cams_web_toys_subdomains : "cwt_${k}" => v }
}

# --- Namespace ---

resource "kubernetes_namespace" "cams_web_toys" {
  count = var.cams_web_toys_enabled ? 1 : 0

  metadata {
    name = "cams-web-toys"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cams-web-toys"
    })
  }
}

# --- Deployment ---

resource "kubernetes_deployment" "cams_web_toys" {
  count = var.cams_web_toys_enabled ? 1 : 0

  metadata {
    name      = "cams-web-toys"
    namespace = kubernetes_namespace.cams_web_toys[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cams-web-toys"
    })
    annotations = {
      "keel.sh/policy"       = "force"
      "keel.sh/trigger"      = "poll"
      "keel.sh/pollSchedule" = "@every 2m"
    }
  }

  spec {
    replicas               = 1
    revision_history_limit = 0

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "cams-web-toys"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "cams-web-toys"
        })
      }

      spec {
        image_pull_secrets {
          name = "ghcr-pull-secret"
        }

        container {
          name              = "cams-web-toys"
          image             = var.cams_web_toys_image
          image_pull_policy = var.cams_web_toys_image_pull_policy

          port {
            container_port = 3000
          }

          env {
            name  = "NODE_ENV"
            value = "production"
          }

          env {
            name  = "PORT"
            value = "3000"
          }

          env {
            name  = "HOST"
            value = "0.0.0.0"
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
          }

          resources {
            requests = {
              memory = var.cams_web_toys_memory_request
              cpu    = var.cams_web_toys_cpu_request
            }
            limits = {
              memory = var.cams_web_toys_memory_limit
              cpu    = var.cams_web_toys_cpu_limit
            }
          }
        }
      }
    }
  }
}

# --- Service ---

resource "kubernetes_service" "cams_web_toys" {
  count = var.cams_web_toys_enabled ? 1 : 0

  depends_on = [kubernetes_deployment.cams_web_toys]

  metadata {
    name      = "cams-web-toys-service"
    namespace = kubernetes_namespace.cams_web_toys[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cams-web-toys"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "cams-web-toys"
    }
    port {
      protocol    = "TCP"
      port        = 3000
      target_port = 3000
    }
  }
}

# --- Outputs ---

output "cams_web_toys_info" {
  description = "cams-web-toys service information"
  value = var.cams_web_toys_enabled ? {
    namespace    = kubernetes_namespace.cams_web_toys[0].metadata[0].name
    service_name = kubernetes_service.cams_web_toys[0].metadata[0].name
    image        = var.cams_web_toys_image
    subdomains   = { for k, v in local.cams_web_toys_subdomains : k => "https://${v}.${var.traefik_domain}" }
    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.cams_web_toys[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.cams_web_toys[0].metadata[0].name} -l app=cams-web-toys -f"
    }
  } : null
}
