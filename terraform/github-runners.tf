# =============================================================================
# GitHub Self-Hosted Runners — Actions Runner Controller (ARC)
# =============================================================================
# Deploys the modern GitHub ARC (gha-runner-scale-set) with:
#   - ktsu-dev-runners   — org-scoped, covers all ktsu-dev/* repos
#   - <repo>-runners     — one repo-scoped scale set per entry in
#                          var.arc_personal_repos (matt-edmondson/<repo>)
#
# GitHub does not support user-account-scoped self-hosted runners — only
# repo, org, or enterprise scopes — so personal repos still need one scale
# set each. The personal scale sets share a single GitHub App installation
# (the App is installed once on the matt-edmondson user account; that one
# install grants access to whichever personal repos are selected in the
# App's repo list), so they share an installation ID and credential secret.
#
# Runners are ephemeral (one pod per job), scale 0→N on demand, and include
# a privileged docker:dind sidecar so workflows can build container images.
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

variable "arc_personal_max_runners" {
  description = "Maximum concurrent runners for each matt-edmondson/<repo> scale set"
  type        = number
  default     = 25
}

variable "arc_personal_repos" {
  description = "Personal repos under matt-edmondson/* that should get a dedicated ARC scale set. GitHub requires one listener per repo (no user-account scope), but every entry shares var.arc_github_app_installation_id_personal and var.arc_personal_runner_label, so workflows in any of these repos can target the same `runs-on:` label."
  type        = list(string)
  default     = ["CardApp", "ClaudeCluster"]
}

variable "arc_personal_runner_label" {
  description = "Shared GitHub-side scale set name (and `runs-on:` label) for every personal repo scale set. Each scale set is still its own listener pinned to its repo, but they all advertise the same label, so workflows in any matt-edmondson/<repo> can target `runs-on: <this label>`."
  type        = string
  default     = "personal-runners"
}

variable "arc_runner_image" {
  description = "Container image for the ARC runner pods. Defaults to the homelab-runner overlay (official actions-runner + gh CLI). Built by .github/workflows/build-runner-image.yml."
  type        = string
  default     = "ghcr.io/matt-edmondson/homelab-runner:2.333.1-2"
}

# GHCR pull credentials for the private arc_runner_image are sourced from the
# shared var.ghcr_username / var.ghcr_token declared in ghcr-pull.tf. The
# arc-runners namespace is auto-included in ghcr-pull.tf's secret targets via
# splat over kubernetes_namespace.arc_runners (gated on var.arc_enabled).

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

variable "arc_github_app_installation_id_personal" {
  description = "GitHub App installation ID for the matt-edmondson user-account install. One install on the personal account covers all selected personal repos, so every entry in var.arc_personal_repos shares this ID."
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

  type = "Opaque"

  data = {
    github_app_id              = var.arc_github_app_id
    github_app_installation_id = var.arc_github_app_installation_id_ktsu_dev
    github_app_private_key     = var.arc_github_app_private_key
  }

  depends_on = [kubernetes_namespace.arc_runners]
}

resource "kubernetes_secret" "arc_personal_github_app" {
  count = var.arc_enabled ? 1 : 0

  metadata {
    name      = "arc-personal-github-app"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
    labels    = var.common_labels
  }

  type = "Opaque"

  data = {
    github_app_id              = var.arc_github_app_id
    github_app_installation_id = var.arc_github_app_installation_id_personal
    github_app_private_key     = var.arc_github_app_private_key
  }

  depends_on = [kubernetes_namespace.arc_runners]
}

# Runner pods pull the private runner image via the shared ghcr-pull-secret
# that ghcr-pull.tf creates in arc-runners (auto-derived from
# kubernetes_namespace.arc_runners).

# DinD MTU patch — the chart's dind container runs dockerd with default MTU
# 1500, but flannel's VXLAN overlay caps pod eth0 at MTU 1450. Small packets
# work, but TLS handshakes stall forever when cert frames exceed the path
# MTU and PMTUD blackholes (symptom: `wget` to external HTTPS hangs ~15m on
# "Unable to establish SSL connection" during container builds).
#
# The chart's dind container is hardcoded (see `non-runner-non-dind-containers`
# in the chart's _helpers.tpl, which filters out any user-supplied `dind`
# entry), so we can't configure --mtu via helm values. Instead we patch the
# AutoscalingRunnerSet after helm apply via a kubectl JSON-patch append.
# Runner pods are templated from this set, so every new runner inherits the
# fix. The trigger is keyed on helm release ID + patch payload so it re-runs
# when either the release or the MTU value changes.
# JSON Patch that REPLACES the dind container's args list with the chart's
# default plus --mtu=1450. Replace (not append) so re-applying is idempotent
# and doesn't accumulate duplicate flags. The default args have been stable
# across gha-runner-scale-set 0.9–0.14; if a future chart version changes
# them, bump this too.
locals {
  arc_dind_mtu = "1450"
  arc_dind_patched_args = [
    "dockerd",
    "--host=unix:///var/run/docker.sock",
    "--group=$(DOCKER_GROUP_GID)",
    "--mtu=${local.arc_dind_mtu}",
  ]
  arc_dind_patch_json = jsonencode([{
    op    = "replace"
    path  = "/spec/template/spec/containers/1/args" # dind sidecar is containers[1]
    value = local.arc_dind_patched_args
  }])
}

resource "null_resource" "arc_dind_mtu_patch_ktsu_dev" {
  count = var.arc_enabled ? 1 : 0

  triggers = {
    helm_revision = helm_release.arc_ktsu_dev[0].metadata.revision
    patch_sha     = sha256(local.arc_dind_patch_json)
  }

  provisioner "local-exec" {
    command     = "kubectl -n ${kubernetes_namespace.arc_runners[0].metadata[0].name} patch autoscalingrunnerset.actions.github.com ktsu-dev-runners --type=json -p '${local.arc_dind_patch_json}'"
    interpreter = ["bash", "-c"]
    # Git Bash / MSYS rewrites arguments that start with `/` into Windows
    # paths, which mangles JSON Pointer paths like /spec/template/... .
    environment = { MSYS_NO_PATHCONV = "1" }
  }
}

resource "null_resource" "arc_dind_mtu_patch_personal" {
  for_each = var.arc_enabled ? toset(var.arc_personal_repos) : toset([])

  triggers = {
    helm_revision = helm_release.arc_personal[each.key].metadata.revision
    patch_sha     = sha256(local.arc_dind_patch_json)
  }

  provisioner "local-exec" {
    command     = "kubectl -n ${kubernetes_namespace.arc_runners[0].metadata[0].name} patch autoscalingrunnerset.actions.github.com ${lower(each.key)}-runners --type=json -p '${local.arc_dind_patch_json}'"
    interpreter = ["bash", "-c"]
    environment = { MSYS_NO_PATHCONV = "1" }
  }
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
      # DOCKER_HOST into the runner container. The chart hardcodes the dind
      # container with no MTU override; see the null_resource.arc_dind_mtu_*
      # patches below that inject --mtu=1450 post-install.
      containerMode = {
        type = "dind"
      }

      template = {
        spec = {
          imagePullSecrets = var.ghcr_token != "" ? [{ name = "ghcr-pull-secret" }] : []
          containers = [
            {
              name    = "runner"
              image   = var.arc_runner_image
              command = ["/home/runner/run.sh"]
              # Claude Code invokes bwrap for Bash tool calls in SDK/headless
              # mode. Ubuntu 24.04+ host kernel restricts unprivileged user
              # namespaces (kernel.apparmor_restrict_unprivileged_userns=1),
              # and container-scoped AppArmor/seccomp/SYS_ADMIN aren't enough
              # because bwrap runs as non-root (UID 1001) and needs effective
              # caps. privileged gives effective caps to the runner user.
              # The DinD sidecar is already privileged, so this doesn't widen
              # the pod's overall trust boundary.
              securityContext = {
                privileged = true
              }
              resources = {
                requests = {
                  cpu    = "500m"
                  memory = "2Gi"
                }
                limits = {
                  cpu    = "4"
                  memory = "8Gi"
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
    kubernetes_secret.ghcr_pull,
  ]
}

# Scale sets — matt-edmondson/<repo> (one per entry in var.arc_personal_repos)
# Workflows target each set with: runs-on: <lower(repo)>-runners
#
# All instances depend on helm_release.arc_ktsu_dev so the OCI chart is fully
# downloaded and cached before any of these run. The hashicorp/helm 3.x
# provider on Windows hits a temp-file rename race when multiple installs
# download the same OCI chart in parallel; once ktsu-dev's apply has
# populated the local Helm OCI cache, subsequent installs reuse it and the
# race window closes. The for_each instances themselves still apply in
# parallel, but they hit the warm cache rather than re-downloading.
# Shared no-permission ServiceAccount for the personal scale sets. The chart
# (gha-runner-scale-set) auto-creates a `<runnerScaleSetName>-gha-rs-no-permission`
# SA whenever `template.spec.serviceAccountName` is unset and containerMode is
# not `kubernetes`. With multiple releases sharing the same runnerScaleSetName,
# all of them fight over that one auto-named SA — only the first to install
# wins, the rest fail with a Helm ownership-annotation conflict. We sidestep
# that by pre-creating one SA and pointing every release at it via
# template.spec.serviceAccountName, which causes the chart's auto-creation
# branch to skip entirely. The SA is intentionally permissionless (no role
# bindings) — runners use DinD for isolation and don't need K8s API access.
resource "kubernetes_service_account" "arc_personal_runner" {
  count = var.arc_enabled && length(var.arc_personal_repos) > 0 ? 1 : 0

  metadata {
    name      = "arc-personal-runner"
    namespace = kubernetes_namespace.arc_runners[0].metadata[0].name
    labels    = var.common_labels
  }
}

resource "helm_release" "arc_personal" {
  for_each = var.arc_enabled ? toset(var.arc_personal_repos) : toset([])

  name       = "${lower(each.key)}-runners"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"
  version    = var.arc_runner_set_chart_version
  namespace  = kubernetes_namespace.arc_runners[0].metadata[0].name

  values = [
    yamlencode({
      githubConfigUrl    = "https://github.com/matt-edmondson/${each.key}"
      githubConfigSecret = kubernetes_secret.arc_personal_github_app[0].metadata[0].name

      # Shared GitHub-side name + `runs-on:` label across every personal-repo
      # scale set. Each scale set is still a distinct listener pinned to one
      # repo (GitHub allows no other scope for personal repos), but they all
      # advertise the same label so workflows can use one `runs-on:` value.
      # The Helm release / AutoscalingRunnerSet K8s name above stays per-repo
      # so the arc-runners namespace doesn't collide.
      runnerScaleSetName = var.arc_personal_runner_label

      minRunners = 0
      maxRunners = var.arc_personal_max_runners

      containerMode = {
        type = "dind"
      }

      template = {
        spec = {
          # See kubernetes_service_account.arc_personal_runner above. Setting
          # this skips the chart's auto-created no-permission SA, which would
          # otherwise collide between releases that share runnerScaleSetName.
          serviceAccountName = kubernetes_service_account.arc_personal_runner[0].metadata[0].name
          imagePullSecrets   = var.ghcr_token != "" ? [{ name = "ghcr-pull-secret" }] : []
          containers = [
            {
              name    = "runner"
              image   = var.arc_runner_image
              command = ["/home/runner/run.sh"]
              # See ktsu-dev scale set above for rationale.
              securityContext = {
                privileged = true
              }
              resources = {
                requests = {
                  cpu    = "500m"
                  memory = "2Gi"
                }
                limits = {
                  cpu    = "4"
                  memory = "8Gi"
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
    kubernetes_secret.arc_personal_github_app,
    kubernetes_secret.ghcr_pull,
    helm_release.arc_ktsu_dev,
    kubernetes_service_account.arc_personal_runner,
  ]
}
