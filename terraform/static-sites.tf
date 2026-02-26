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

# Deployment
resource "kubernetes_deployment" "static_sites" {
  count = length(var.static_sites) > 0 ? 1 : 0

  depends_on = [
    kubernetes_config_map.static_sites_config,
  ]

  metadata {
    name      = "static-sites"
    namespace = kubernetes_namespace.static_sites[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "static-sites"
    })
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "static-sites"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "static-sites"
        })
      }

      spec {
        # Init containers — one per site to clone the repo
        dynamic "init_container" {
          for_each = var.static_sites
          content {
            name    = "git-clone-${replace(init_container.value.domain, ".", "-")}"
            image   = var.static_sites_git_image
            command = ["sh", "-c", "git clone --branch ${init_container.value.branch} --single-branch --depth 1 ${init_container.value.repo_url} /sites/${init_container.value.domain}"]

            volume_mount {
              name       = "sites"
              mount_path = "/sites"
            }
          }
        }

        # Nginx container
        container {
          name  = "nginx"
          image = var.static_sites_nginx_image

          port {
            container_port = 80
          }

          volume_mount {
            name       = "sites"
            mount_path = "/sites"
            read_only  = true
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          resources {
            requests = {
              memory = var.static_sites_memory_request
              cpu    = var.static_sites_cpu_request
            }
            limits = {
              memory = var.static_sites_memory_limit
              cpu    = var.static_sites_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        # Git pull sidecar
        container {
          name    = "git-pull"
          image   = var.static_sites_git_image
          command = ["sh", "/scripts/git-pull.sh"]

          volume_mount {
            name       = "sites"
            mount_path = "/sites"
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/scripts/git-pull.sh"
            sub_path   = "git-pull.sh"
          }

          resources {
            requests = {
              memory = "32Mi"
              cpu    = "10m"
            }
            limits = {
              memory = "64Mi"
              cpu    = "50m"
            }
          }
        }

        # Shared volume for site content
        volume {
          name = "sites"
          empty_dir {}
        }

        # Config volume
        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.static_sites_config[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "static_sites" {
  count = length(var.static_sites) > 0 ? 1 : 0

  depends_on = [
    kubernetes_deployment.static_sites,
  ]

  metadata {
    name      = "static-sites-service"
    namespace = kubernetes_namespace.static_sites[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "static-sites"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "static-sites"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }
}

# Outputs
output "static_sites_info" {
  description = "Static sites hosting information"
  value = length(var.static_sites) > 0 ? {
    namespace     = kubernetes_namespace.static_sites[0].metadata[0].name
    service_name  = kubernetes_service.static_sites[0].metadata[0].name
    sites         = { for site in var.static_sites : site.domain => site.repo_url }
    poll_interval = "${var.static_sites_git_poll_interval}s"

    commands = {
      check_pods = "kubectl get pods -n static-sites"
      logs_nginx = "kubectl logs -n static-sites -l app=static-sites -c nginx -f"
      logs_git   = "kubectl logs -n static-sites -l app=static-sites -c git-pull -f"
    }
  } : null
}
