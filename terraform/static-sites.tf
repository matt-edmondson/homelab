# =============================================================================
# Static Sites - Nginx-based static site hosting with git-based content
# =============================================================================

# Variables
variable "static_sites" {
  description = "List of static sites to host. Each site needs a domain, git repo URL, and branch."
  type = list(object({
    domain   = string
    repo_url = string
    branch   = string
  }))
  default = []
}

variable "static_sites_git_poll_interval" {
  description = "Interval in seconds between git pull operations for content updates"
  type        = string
  default     = "60"
}

variable "static_sites_nginx_image" {
  description = "Nginx container image for serving static sites"
  type        = string
  default     = "nginx:alpine"
}

variable "static_sites_git_image" {
  description = "Git container image for cloning and pulling repos"
  type        = string
  default     = "alpine/git:latest"
}

variable "static_sites_memory_request" {
  description = "Memory request for the nginx container"
  type        = string
  default     = "64Mi"
}

variable "static_sites_memory_limit" {
  description = "Memory limit for the nginx container"
  type        = string
  default     = "128Mi"
}

variable "static_sites_cpu_request" {
  description = "CPU request for the nginx container"
  type        = string
  default     = "50m"
}

variable "static_sites_cpu_limit" {
  description = "CPU limit for the nginx container"
  type        = string
  default     = "200m"
}

variable "static_sites_git_credentials" {
  description = "Optional git credentials URL (e.g. https://user:token@github.com) for private repos"
  type        = string
  sensitive   = true
  default     = ""
}

# Namespace
resource "kubernetes_namespace" "static_sites" {
  count = length(var.static_sites) > 0 ? 1 : 0

  metadata {
    name = "static-sites"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "static-sites"
    })
  }
}

# Nginx virtual host configuration (generated from static_sites list)
resource "kubernetes_config_map" "static_sites_config" {
  count = length(var.static_sites) > 0 ? 1 : 0

  metadata {
    name      = "static-sites-config"
    namespace = kubernetes_namespace.static_sites[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "nginx.conf" = templatefile("${path.module}/templates/static-sites-nginx.conf.tpl", {
      sites = var.static_sites
    })

    "git-pull.sh" = templatefile("${path.module}/templates/static-sites-git-pull.sh.tpl", {
      sites    = var.static_sites
      interval = var.static_sites_git_poll_interval
    })
  }
}
