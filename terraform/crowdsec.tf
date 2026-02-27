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

# Register the Traefik bouncer API key with CrowdSec LAPI
# Uses cscli to add the bouncer (idempotent: checks if already registered)
resource "kubernetes_job" "crowdsec_register_bouncer" {
  metadata {
    name      = "crowdsec-register-bouncer"
    namespace = kubernetes_namespace.crowdsec.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    backoff_limit = 5

    template {
      metadata {
        labels = var.common_labels
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name    = "register-bouncer"
          image   = "bitnami/kubectl:latest"
          command = ["/bin/sh", "-c"]
          args = [
            <<-EOT
            # Wait for LAPI to be ready
            echo "Waiting for CrowdSec LAPI to be ready..."
            kubectl wait --for=condition=available deployment/crowdsec-lapi -n crowdsec --timeout=120s

            # Check if bouncer already exists
            EXISTING=$(kubectl exec deploy/crowdsec-lapi -n crowdsec -- cscli bouncers list -o raw 2>/dev/null | grep "traefik-bouncer" || true)
            if [ -n "$EXISTING" ]; then
              echo "Bouncer 'traefik-bouncer' already registered, skipping."
            else
              echo "Registering bouncer 'traefik-bouncer'..."
              kubectl exec deploy/crowdsec-lapi -n crowdsec -- cscli bouncers add traefik-bouncer --key "$BOUNCER_KEY"
              echo "Bouncer registered successfully."
            fi
            EOT
          ]

          env {
            name = "BOUNCER_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.crowdsec_bouncer_secret.metadata[0].name
                key  = "bouncer-key"
              }
            }
          }
        }

        service_account_name = kubernetes_service_account.crowdsec_bouncer_registrar.metadata[0].name
      }
    }
  }

  wait_for_completion = true
  timeouts {
    create = "5m"
  }

  depends_on = [
    helm_release.crowdsec,
    kubernetes_cluster_role_binding.crowdsec_bouncer_registrar,
  ]
}

# Service account for the bouncer registration job
resource "kubernetes_service_account" "crowdsec_bouncer_registrar" {
  metadata {
    name      = "crowdsec-bouncer-registrar"
    namespace = kubernetes_namespace.crowdsec.metadata[0].name
    labels    = var.common_labels
  }
}

# RBAC: allow the job to exec into pods and wait for deployments in the crowdsec namespace
resource "kubernetes_role" "crowdsec_bouncer_registrar" {
  metadata {
    name      = "crowdsec-bouncer-registrar"
    namespace = kubernetes_namespace.crowdsec.metadata[0].name
    labels    = var.common_labels
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/exec"]
    verbs      = ["get", "list", "create"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "crowdsec_bouncer_registrar" {
  metadata {
    name      = "crowdsec-bouncer-registrar"
    namespace = kubernetes_namespace.crowdsec.metadata[0].name
    labels    = var.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.crowdsec_bouncer_registrar.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.crowdsec_bouncer_registrar.metadata[0].name
    namespace = kubernetes_namespace.crowdsec.metadata[0].name
  }
}

# Secret to hold the bouncer API key
resource "kubernetes_secret" "crowdsec_bouncer_secret" {
  metadata {
    name      = "crowdsec-bouncer-key"
    namespace = kubernetes_namespace.crowdsec.metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "bouncer-key" = var.crowdsec_bouncer_key
  }

  type = "Opaque"
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
