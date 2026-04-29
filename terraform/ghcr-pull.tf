# =============================================================================
# Shared GHCR image pull secret
#
# Single source of truth for ghcr.io pull credentials across namespaces that
# need them. Each target namespace gets an identical Secret named
# `ghcr-pull-secret`, seeded from var.ghcr_username + var.ghcr_token. Pods
# reference it by a stable name regardless of namespace.
#
# Targets are auto-derived from feature-flag-gated namespace resources via
# splat (kubernetes_namespace.<x>[*].metadata[0].name): disabling a feature
# automatically drops its ghcr-pull-secret, and Terraform infers the
# namespace -> secret dependency without an explicit depends_on. Add
# extra namespaces (e.g. ones declared outside this repo) via
# var.ghcr_pull_extra_namespaces.
# =============================================================================

variable "ghcr_username" {
  description = "GitHub username paired with ghcr_token for ghcr.io image pulls."
  type        = string
  default     = "matt-edmondson"
}

variable "ghcr_token" {
  description = "GitHub PAT with read:packages scope. Used as the source for every per-namespace ghcr-pull-secret. Leave empty to disable (no secrets will be created)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "ghcr_pull_extra_namespaces" {
  description = "Additional namespaces beyond the auto-derived feature-gated ones (arc-runners, claude-sandbox, claude-sandboxes, poker) that should receive a ghcr-pull-secret. Use this for namespaces declared outside this repo."
  type        = set(string)
  default     = []
}

locals {
  # Auto-derived from the namespace resources themselves: when a feature is
  # disabled (count = 0), its splat returns []; when enabled, it returns the
  # one-element name list. Referencing the resource attributes also gives us
  # an implicit dependency, so the secret can't apply before its namespace.
  ghcr_pull_namespaces = toset(concat(
    tolist(var.ghcr_pull_extra_namespaces),
    kubernetes_namespace.arc_runners[*].metadata[0].name,
    kubernetes_namespace.claude_sandbox[*].metadata[0].name,
    kubernetes_namespace.claude_sandboxes[*].metadata[0].name,
    kubernetes_namespace.poker[*].metadata[0].name,
  ))
}

resource "kubernetes_secret" "ghcr_pull" {
  # A sensitive-variable gate (e.g. on ghcr_token) can't be used here because
  # Terraform refuses to derive resource keys from sensitive values.
  for_each = local.ghcr_pull_namespaces

  metadata {
    name      = "ghcr-pull-secret"
    namespace = each.value
    labels    = var.common_labels
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          auth = base64encode("${var.ghcr_username}:${var.ghcr_token}")
        }
      }
    })
  }
}
