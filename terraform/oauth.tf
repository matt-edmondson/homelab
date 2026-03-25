# =============================================================================
# OAuth2 Proxy — GitHub SSO for Protected Services
# =============================================================================
# Deploys oauth2-proxy as a ForwardAuth middleware for Traefik.
# Users authenticate via GitHub, replacing basic auth on protected routes.
#
# Setup: Create a GitHub OAuth App at https://github.com/settings/developers
#   - Homepage URL: https://auth.<your-domain>
#   - Callback URL: https://auth.<your-domain>/oauth2/callback
# =============================================================================

# Variables
variable "oauth2_proxy_chart_version" {
  description = "OAuth2 Proxy Helm chart version"
  type        = string
  default     = "10.1.4"
}

variable "oauth_github_client_id" {
  description = "GitHub OAuth App client ID"
  type        = string
  sensitive   = true
}

variable "oauth_github_client_secret" {
  description = "GitHub OAuth App client secret"
  type        = string
  sensitive   = true
}

variable "oauth_cookie_secret" {
  description = "Random 32-byte base64 secret for cookie encryption. Generate with: openssl rand -base64 32 | head -c 32"
  type        = string
  sensitive   = true
}

variable "oauth_github_user" {
  description = "GitHub username allowed to authenticate (comma-separated for multiple)"
  type        = string
}

variable "oauth_enabled" {
  description = "Enable OAuth2 proxy deployment"
  type        = bool
  default     = true
}

# Namespace
resource "kubernetes_namespace" "oauth2_proxy" {
  count = var.oauth_enabled ? 1 : 0

  metadata {
    name = "oauth2-proxy"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "oauth2-proxy"
    })
  }
}

# Auth bridge — wraps OAuth2-proxy's /oauth2/auth and returns a 302 redirect
# to the sign-in page instead of a bare 401 for unauthenticated requests
resource "kubernetes_config_map" "oauth2_auth_bridge" {
  count = var.oauth_enabled ? 1 : 0

  metadata {
    name      = "oauth2-auth-bridge"
    namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "default.conf" = <<-EOT
      server {
        listen 8080;

        location = /oauth2/auth {
          internal;
          proxy_pass http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Host $http_x_forwarded_host;
          proxy_set_header X-Forwarded-Uri $http_x_forwarded_uri;
          proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
          proxy_set_header Cookie $http_cookie;

          proxy_intercept_errors on;
          error_page 401 403 = @sign_in;
        }

        location @sign_in {
          return 302 https://auth.${var.traefik_domain}/oauth2/start?rd=$http_x_forwarded_proto://$http_x_forwarded_host$http_x_forwarded_uri;
        }

        location /verify {
          proxy_pass http://oauth2-proxy.oauth2-proxy.svc.cluster.local/oauth2/auth;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header X-Forwarded-For $remote_addr;
          proxy_set_header X-Forwarded-Host $http_x_forwarded_host;
          proxy_set_header X-Forwarded-Uri $http_x_forwarded_uri;
          proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
          proxy_set_header Cookie $http_cookie;

          proxy_intercept_errors on;
          error_page 401 403 = @sign_in;
        }
      }
    EOT
  }
}

resource "kubernetes_deployment" "oauth2_auth_bridge" {
  count = var.oauth_enabled ? 1 : 0

  metadata {
    name      = "oauth2-auth-bridge"
    namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
    labels = merge(var.common_labels, {
      app = "oauth2-auth-bridge"
    })
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "oauth2-auth-bridge"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "oauth2-auth-bridge"
        })
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:alpine"

          port {
            container_port = 8080
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/nginx/conf.d"
            read_only  = true
          }

          resources {
            requests = {
              memory = "16Mi"
              cpu    = "10m"
            }
            limits = {
              memory = "32Mi"
              cpu    = "50m"
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.oauth2_auth_bridge[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "oauth2_auth_bridge" {
  count = var.oauth_enabled ? 1 : 0

  metadata {
    name      = "oauth2-auth-bridge"
    namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "oauth2-auth-bridge"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }
}

# Helm Release — OAuth2 Proxy
resource "helm_release" "oauth2_proxy" {
  count = var.oauth_enabled ? 1 : 0

  name       = "oauth2-proxy"
  repository = "https://oauth2-proxy.github.io/manifests"
  chart      = "oauth2-proxy"
  version    = var.oauth2_proxy_chart_version
  namespace  = kubernetes_namespace.oauth2_proxy[0].metadata[0].name

  values = [
    yamlencode({
      config = {
        clientID     = var.oauth_github_client_id
        clientSecret = var.oauth_github_client_secret
        cookieSecret = var.oauth_cookie_secret
      }

      extraArgs = {
        provider                 = "github"
        github-user              = var.oauth_github_user
        cookie-secure            = "true"
        cookie-domain            = ".${var.traefik_domain}"
        set-xauthrequest         = "true"
        reverse-proxy            = "true"
        set-authorization-header = "true"
        email-domain             = "*"
        whitelist-domain         = ".${var.traefik_domain}"
        cookie-csrf-per-request  = "true"
        skip-provider-button     = "true"
        redirect-url             = "https://auth.${var.traefik_domain}/oauth2/callback"
        upstream                 = "static://202"
      }

      service = {
        type = "ClusterIP"
      }

      resources = {
        requests = {
          memory = "64Mi"
          cpu    = "50m"
        }
        limits = {
          memory = "128Mi"
          cpu    = "200m"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.oauth2_proxy[0],
  ]

  timeout = 300
  wait    = true
}

# Outputs
output "oauth2_proxy_info" {
  description = "OAuth2 Proxy information"
  value = var.oauth_enabled ? {
    namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
    auth_url  = "https://auth.${var.traefik_domain}"

    setup = {
      github_oauth_app = "Create at https://github.com/settings/developers"
      homepage_url     = "https://auth.${var.traefik_domain}"
      callback_url     = "https://auth.${var.traefik_domain}/oauth2/callback"
    }

    commands = {
      check_pods = "kubectl get pods -n oauth2-proxy"
      check_logs = "kubectl logs -n oauth2-proxy -l app.kubernetes.io/name=oauth2-proxy -f"
    }
  } : null

  sensitive = true
}
