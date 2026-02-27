# =============================================================================
# CrowdSec Security Engine
# =============================================================================
# CrowdSec provides intrusion detection using community threat intelligence.
# Deploys as:
#   - LAPI (Local API): Central decision engine (Deployment)
#   - Agent: Log processor on each node (DaemonSet)
#
# The Traefik Bouncer plugin (configured in traefik.tf) queries LAPI to
# block malicious IPs at the ingress level.
# =============================================================================

# Variables
variable "crowdsec_chart_version" {
  description = "CrowdSec Helm chart version"
  type        = string
  default     = "0.22.0"
}

variable "crowdsec_bouncer_key" {
  description = "API key for the Traefik bouncer to authenticate with CrowdSec LAPI. Generate with: openssl rand -hex 32"
  type        = string
  sensitive   = true
}

variable "crowdsec_enroll_key" {
  description = "CrowdSec console enrollment key (optional, from app.crowdsec.net)"
  type        = string
  default     = ""
}

# Namespace
resource "kubernetes_namespace" "crowdsec" {
  metadata {
    name = "crowdsec"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "crowdsec"
    })
  }
}

# Helm Release — CrowdSec
resource "helm_release" "crowdsec" {
  name       = "crowdsec"
  repository = "https://crowdsecurity.github.io/helm-charts"
  chart      = "crowdsec"
  version    = var.crowdsec_chart_version
  namespace  = kubernetes_namespace.crowdsec.metadata[0].name

  values = [
    yamlencode({
      container_runtime = "containerd"

      lapi = {
        bouncers = {
          "traefik-bouncer" = {
            key = var.crowdsec_bouncer_key
          }
        }

        env = concat(
          var.crowdsec_enroll_key != "" ? [
            {
              name  = "ENROLL_KEY"
              value = var.crowdsec_enroll_key
            },
            {
              name  = "ENROLL_INSTANCE_NAME"
              value = "homelab-k8s"
            },
          ] : [],
          []
        )

        persistentVolume = {
          data = {
            enabled          = true
            accessModes      = ["ReadWriteOnce"]
            storageClassName = data.kubernetes_storage_class.longhorn.metadata[0].name
            size             = "1Gi"
          }
          config = {
            enabled          = true
            accessModes      = ["ReadWriteOnce"]
            storageClassName = data.kubernetes_storage_class.longhorn.metadata[0].name
            size             = "100Mi"
          }
        }

        resources = {
          requests = {
            memory = "256Mi"
            cpu    = "100m"
          }
          limits = {
            memory = "512Mi"
            cpu    = "500m"
          }
        }
      }

      agent = {
        acquisition = [
          {
            namespace = "traefik"
            podName   = "traefik-*"
            program   = "traefik"
          },
        ]

        resources = {
          requests = {
            memory = "128Mi"
            cpu    = "100m"
          }
          limits = {
            memory = "256Mi"
            cpu    = "500m"
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.crowdsec,
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
  ]

  timeout = 300
  wait    = true
}

# Outputs
output "crowdsec_info" {
  description = "CrowdSec security engine information"
  value = {
    namespace    = kubernetes_namespace.crowdsec.metadata[0].name
    lapi_service = "crowdsec-service.${kubernetes_namespace.crowdsec.metadata[0].name}.svc.cluster.local:8080"

    commands = {
      check_pods    = "kubectl get pods -n ${kubernetes_namespace.crowdsec.metadata[0].name}"
      check_lapi    = "kubectl exec -n ${kubernetes_namespace.crowdsec.metadata[0].name} -it deploy/crowdsec-lapi -- cscli decisions list"
      list_bouncers = "kubectl exec -n ${kubernetes_namespace.crowdsec.metadata[0].name} -it deploy/crowdsec-lapi -- cscli bouncers list"
      add_bouncer   = "kubectl exec -n ${kubernetes_namespace.crowdsec.metadata[0].name} -it deploy/crowdsec-lapi -- cscli bouncers add traefik-bouncer"
    }
  }
}
