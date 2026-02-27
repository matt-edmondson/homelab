# =============================================================================
# Headlamp — Kubernetes Web Dashboard
# =============================================================================
# Replaces the retired kubernetes-dashboard project.
# Headlamp is the officially recommended successor, maintained under
# kubernetes-sigs. https://headlamp.dev/
# =============================================================================

# Variables
variable "headlamp_chart_version" {
  description = "Version of Headlamp Helm chart"
  type        = string
  default     = "0.40.0"
}

# Namespace
resource "kubernetes_namespace" "headlamp" {
  metadata {
    name = "headlamp"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "headlamp"
    })
  }
}

# Headlamp Helm Release
resource "helm_release" "headlamp" {
  name       = "headlamp"
  repository = "https://kubernetes-sigs.github.io/headlamp/"
  chart      = "headlamp"
  version    = var.headlamp_chart_version
  namespace  = kubernetes_namespace.headlamp.metadata[0].name

  values = [
    yamlencode({
      replicaCount = 1

      config = {
        baseURL = ""
      }

      clusterRoleBinding = {
        create     = true
        annotations = {}
      }

      serviceAccount = {
        create = true
      }

      service = {
        type = "ClusterIP"
        port = 80
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "256Mi"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.headlamp,
  ]
}

# Outputs
output "headlamp_info" {
  description = "Headlamp dashboard information"
  value = {
    namespace     = kubernetes_namespace.headlamp.metadata[0].name
    chart_version = var.headlamp_chart_version

    access = {
      web_ui = "https://dashboard.${var.traefik_domain}"
    }

    commands = {
      check_pods    = "kubectl get pods -n ${kubernetes_namespace.headlamp.metadata[0].name}"
      check_service = "kubectl get svc -n ${kubernetes_namespace.headlamp.metadata[0].name}"
      view_logs     = "kubectl logs -n ${kubernetes_namespace.headlamp.metadata[0].name} -l app.kubernetes.io/name=headlamp -f"
    }
  }
}
