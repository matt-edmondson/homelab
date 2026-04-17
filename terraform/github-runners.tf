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
