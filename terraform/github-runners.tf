# =============================================================================
# GitHub Self-Hosted Runners — Actions Runner Controller (ARC)
# =============================================================================
# Deploys the modern GitHub ARC (gha-runner-scale-set) with two scale sets:
#   - ktsu-dev-runners   — org-scoped, covers all ktsu-dev/* repos
#   - cardapp-runners    — repo-scoped to matt-edmondson/CardApp
#
# Runners are ephemeral (one pod per job), scale 0→N on demand, and include
# a privileged docker:dind sidecar so workflows can build container images.
#
# Authentication: GitHub App (one App installed on both the ktsu-dev org and
# the CardApp repo). Per-install credentials live in separate K8s secrets.
#
# Spec: docs/superpowers/specs/2026-04-17-github-runners-arc-design.md
# =============================================================================

# Variables — enable flag and chart versions
variable "arc_enabled" {
  description = "Enable Actions Runner Controller and scale sets"
  type        = bool
  default     = true
}

variable "arc_controller_chart_version" {
  description = "Helm chart version for gha-runner-scale-set-controller"
  type        = string
  default     = "0.11.0"
}

variable "arc_runner_set_chart_version" {
  description = "Helm chart version for gha-runner-scale-set (should match controller version)"
  type        = string
  default     = "0.11.0"
}

# Variables — scaling
variable "arc_ktsu_dev_max_runners" {
  description = "Maximum concurrent runners for the ktsu-dev org scale set"
  type        = number
  default     = 25
}

variable "arc_cardapp_max_runners" {
  description = "Maximum concurrent runners for the matt-edmondson/CardApp scale set"
  type        = number
  default     = 25
}

# Variables — GitHub App credentials
variable "arc_github_app_id" {
  description = "GitHub App ID (numeric). Create the App under your personal account with permissions: repo Actions/Administration/Metadata + org Self-hosted runners."
  type        = string
  sensitive   = true
  default     = ""
}

variable "arc_github_app_installation_id_ktsu_dev" {
  description = "GitHub App installation ID for the ktsu-dev organization install"
  type        = string
  sensitive   = true
  default     = ""
}

variable "arc_github_app_installation_id_cardapp" {
  description = "GitHub App installation ID for the matt-edmondson/CardApp install"
  type        = string
  sensitive   = true
  default     = ""
}

variable "arc_github_app_private_key" {
  description = "Contents of the GitHub App private key .pem file (full PEM, including BEGIN/END lines)"
  type        = string
  sensitive   = true
  default     = ""
}

# Namespaces
resource "kubernetes_namespace" "arc_system" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name = "arc-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "arc-system"
    })
  }
}

resource "kubernetes_namespace" "arc_runners" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name = "arc-runners"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "arc-runners"
    })
  }
}

# GitHub App credential secrets — one per scale set
# The gha-runner-scale-set chart reads these three keys: github_app_id,
# github_app_installation_id, github_app_private_key.

resource "kubernetes_secret" "arc_ktsu_dev_github_app" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name      = "arc-ktsu-dev-github-app"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    github_app_id              = var.arc_github_app_id
    github_app_installation_id = var.arc_github_app_installation_id_ktsu_dev
    github_app_private_key     = var.arc_github_app_private_key
  }

  depends_on = [kubernetes_namespace.arc_runners]
}

resource "kubernetes_secret" "arc_cardapp_github_app" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name      = "arc-cardapp-github-app"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    github_app_id              = var.arc_github_app_id
    github_app_installation_id = var.arc_github_app_installation_id_cardapp
    github_app_private_key     = var.arc_github_app_private_key
  }

  depends_on = [kubernetes_namespace.arc_runners]
}

# ARC Controller — singleton, watches AutoscalingRunnerSet CRs cluster-wide
resource "helm_release" "arc_controller" {
  count = var.arc_enabled ? 1 : 0

  name       = "arc"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"
  version    = var.arc_controller_chart_version
  namespace  = kubernetes_namespace.arc_system[0].metadata[0].name

  # Default values are sufficient — controller watches all namespaces by default.
  # Chart docs: https://github.com/actions/actions-runner-controller/blob/master/charts/gha-runner-scale-set-controller/README.md

  depends_on = [kubernetes_namespace.arc_system]
}

# Scale set — ktsu-dev organization
# Workflows target these runners with: runs-on: ktsu-dev-runners
resource "helm_release" "arc_ktsu_dev" {
  count = var.arc_enabled ? 1 : 0

  name       = "ktsu-dev-runners"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.arc_runner_set_chart_version
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name

  values = [
    yamlencode({
      githubConfigUrl    = "https://github.com/ktsu-dev"
      githubConfigSecret = kubernetes_secret.arc_ktsu_dev_github_app[0].metadata[0].name

      runnerScaleSetName = "ktsu-dev-runners"

      minRunners = 0
      maxRunners = var.arc_ktsu_dev_max_runners

      # DinD mode — chart injects a privileged docker:dind sidecar and wires
      # DOCKER_HOST into the runner container. No custom sidecar needed.
      containerMode = {
        type = "dind"
      }

      template = {
        spec = {
          containers = [
            {
              name    = "runner"
              image   = "ghcr.io/actions/actions-runner:latest"
              command = ["/home/runner/run.sh"]
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "4Gi"
                }
              }
            },
          ]
        }
      }
    }),
  ]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.arc_ktsu_dev_github_app,
  ]
}

# Scale set — matt-edmondson/CardApp
# Workflows target these runners with: runs-on: cardapp-runners
resource "helm_release" "arc_cardapp" {
  count = var.arc_enabled ? 1 : 0

  name       = "cardapp-runners"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.arc_runner_set_chart_version
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name

  values = [
    yamlencode({
      githubConfigUrl    = "https://github.com/matt-edmondson/CardApp"
      githubConfigSecret = kubernetes_secret.arc_cardapp_github_app[0].metadata[0].name

      runnerScaleSetName = "cardapp-runners"

      minRunners = 0
      maxRunners = var.arc_cardapp_max_runners

      containerMode = {
        type = "dind"
      }

      template = {
        spec = {
          containers = [
            {
              name    = "runner"
              image   = "ghcr.io/actions/actions-runner:latest"
              command = ["/home/runner/run.sh"]
              resources = {
                requests = {
                  cpu    = "250m"
                  memory = "1Gi"
                }
                limits = {
                  cpu    = "2"
                  memory = "4Gi"
                }
              }
            },
          ]
        }
      }
    }),
  ]

  depends_on = [
    helm_release.arc_controller,
    kubernetes_secret.arc_cardapp_github_app,
  ]
}
