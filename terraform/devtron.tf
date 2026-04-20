# =============================================================================
# Devtron — Kubernetes Dashboard (dashboard-only, no CI/CD)
# =============================================================================
# Devtron is an extensible Kubernetes dashboard providing visibility into
# cluster workloads. Installed in dashboard-only mode (installer.modules=[]),
# without the CI/CD module (no Argo CD, Argo Workflows, NATS, MinIO, etc.).
#
# Auth: Devtron does not support disabling its own auth. The ingress is gated
# by oauth-forward-auth + crowdsec-bouncer (see ingress.tf), and users log in
# to Devtron with the admin password auto-generated in devtron-secret.
# Retrieve with: make debug-devtron
#
# Chart: https://helm.devtron.ai (chart name: devtron-operator)
# =============================================================================

# Variables
variable "devtron_enabled" {
  description = "Enable Devtron dashboard deployment"
  type        = bool
  default     = false
}

variable "devtron_chart_version" {
  description = "Version of Devtron Helm chart (devtron-operator)"
  type        = string
  default     = "0.23.2"
}

variable "devtron_postgres_storage_size" {
  description = "Longhorn PVC size for Devtron's bundled Postgres"
  type        = string
  default     = "20Gi"
}

# Namespace
resource "kubernetes_namespace" "devtron" {
  count = var.devtron_enabled ? 1 : 0

  metadata {
    name = "devtroncd"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "devtron"
    })
  }
}

# Devtron Helm Release (dashboard-only mode)
resource "helm_release" "devtron" {
  count = var.devtron_enabled ? 1 : 0

  name       = "devtron"
  repository = "https://helm.devtron.ai"
  chart      = "devtron-operator"
  version    = var.devtron_chart_version
  namespace  = kubernetes_namespace.devtron[0].metadata[0].name

  values = [
    yamlencode({
      installer = {
        modules = []
      }

      global = {
        storageClass = data.kubernetes_storage_class.longhorn.metadata[0].name
      }

      postgres = {
        persistence = {
          storageClass = data.kubernetes_storage_class.longhorn.metadata[0].name
          volumeSize   = var.devtron_postgres_storage_size
        }
      }

      devtron = {
        service = {
          type = "ClusterIP"
          port = 80
        }
        ingress = {
          enabled = false
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.devtron,
    helm_release.longhorn,                  # Ensure storage backend is available
    data.kubernetes_storage_class.longhorn, # Ensure default storage class exists
  ]
}

# Outputs
output "devtron_info" {
  description = "Devtron dashboard information"
  value = var.devtron_enabled ? {
    namespace     = kubernetes_namespace.devtron[0].metadata[0].name
    chart_version = var.devtron_chart_version

    access = {
      web_ui = "https://devtron.${var.traefik_domain}"
    }

    commands = {
      admin_password = "kubectl -n ${kubernetes_namespace.devtron[0].metadata[0].name} get secret devtron-secret -o jsonpath='{.data.ACD_PASSWORD}' | base64 -d"
      check_pods     = "kubectl get pods -n ${kubernetes_namespace.devtron[0].metadata[0].name}"
      check_pvcs     = "kubectl get pvc -n ${kubernetes_namespace.devtron[0].metadata[0].name}"
      check_service  = "kubectl get svc -n ${kubernetes_namespace.devtron[0].metadata[0].name}"
      view_logs      = "kubectl logs -n ${kubernetes_namespace.devtron[0].metadata[0].name} -l app=devtron -f"
    }
  } : null

  sensitive = true
}
