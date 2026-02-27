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
        create = false
      }

      serviceAccount = {
        create = false
        name   = "headlamp-admin"
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
    kubernetes_service_account.headlamp_admin,
    kubernetes_cluster_role_binding.headlamp_admin,
  ]
}

# Admin service account for Headlamp API access
resource "kubernetes_service_account" "headlamp_admin" {
  metadata {
    name      = "headlamp-admin"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
    labels    = var.common_labels
  }
}

# Long-lived token for the admin service account
resource "kubernetes_secret" "headlamp_admin_token" {
  metadata {
    name      = "headlamp-admin-token"
    namespace = kubernetes_namespace.headlamp.metadata[0].name
    labels    = var.common_labels
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.headlamp_admin.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"
}

# Grant cluster-admin to the Headlamp admin service account
resource "kubernetes_cluster_role_binding" "headlamp_admin" {
  metadata {
    name   = "headlamp-admin-terraform"
    labels = var.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.headlamp_admin.metadata[0].name
    namespace = kubernetes_namespace.headlamp.metadata[0].name
  }
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

    admin_token = kubernetes_secret.headlamp_admin_token.data["token"]

    commands = {
      check_pods    = "kubectl get pods -n ${kubernetes_namespace.headlamp.metadata[0].name}"
      check_service = "kubectl get svc -n ${kubernetes_namespace.headlamp.metadata[0].name}"
      view_logs     = "kubectl logs -n ${kubernetes_namespace.headlamp.metadata[0].name} -l app.kubernetes.io/name=headlamp -f"
      get_token     = "kubectl get secret -n ${kubernetes_namespace.headlamp.metadata[0].name} headlamp-admin-token -o jsonpath='{.data.token}' | base64 --decode"
    }
  }

  sensitive = true
}
