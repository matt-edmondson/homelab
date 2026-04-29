# =============================================================================
# Shared GHCR image pull secret
#
# Single source of truth for ghcr.io pull credentials across namespaces that
# need them. Each listed namespace gets an identical Secret named
# `ghcr-pull-secret`, seeded from var.ghcr_username + var.ghcr_token. Pods
# reference it by a stable name regardless of namespace.
#
# To grant a new namespace access to private GHCR images: add it to
# var.ghcr_pull_namespaces (defaults cover the current consumers).
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

variable "ghcr_pull_namespaces" {
  description = "Namespaces that need a ghcr-pull-secret. Each gets an identically-named Secret seeded from ghcr_token."
  type        = set(string)
  default     = ["arc-runners", "claude-sandbox", "claude-sandboxes", "poker"]
}

resource "kubernetes_secret" "ghcr_pull" {
  # To disable creation entirely, set var.ghcr_pull_namespaces = []. A
  # sensitive-variable gate (e.g. on ghcr_token) can't be used here because
  # Terraform refuses to derive resource keys from sensitive values.
  for_each = var.ghcr_pull_namespaces

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
