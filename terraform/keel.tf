# =============================================================================
# Keel - Cluster-wide image auto-update controller
#
# Polls container registries on a schedule and rolls deployments forward when a
# watched tag (e.g. :latest) points at a new digest. Watches every namespace,
# acting only on Deployments that opt in via `keel.sh/*` annotations.
#
# Registry auth: Keel reads each watched Deployment's imagePullSecrets to
# authenticate registry polls, so no Keel-side dockerRegistrySecret is needed
# as long as the watched Deployments already reference a working pull secret.
# =============================================================================

variable "keel_enabled" {
  description = "Enable cluster-wide Keel image auto-update controller"
  type        = bool
  default     = true
}

variable "keel_chart_version" {
  description = "Keel Helm chart version"
  type        = string
  default     = "1.0.3"
}

variable "keel_poll_schedule" {
  description = "Default poll schedule for Deployments that don't set keel.sh/pollSchedule themselves"
  type        = string
  default     = "@every 2m"
}

resource "kubernetes_namespace" "keel" {
  count = var.keel_enabled ? 1 : 0

  metadata {
    name = "keel"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "keel"
    })
  }
}

resource "helm_release" "keel" {
  count = var.keel_enabled ? 1 : 0

  name       = "keel"
  repository = "https://charts.keel.sh"
  chart      = "keel"
  version    = var.keel_chart_version
  namespace  = kubernetes_namespace.keel[0].metadata[0].name

  values = [
    yamlencode({
      # Controller-only — no Helm release tracking dashboard, no Service.
      helmProvider = {
        enabled = false
      }
      service = {
        enabled = false
      }
      polling = {
        enabled         = true
        defaultSchedule = var.keel_poll_schedule
      }
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
    })
  ]
}
