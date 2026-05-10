# =============================================================================
# Traefik Ingress Routes & Middleware
# =============================================================================
# All IngressRoute and Middleware CRD resources for routing traffic through
# Traefik to backend services.
#
# IMPORTANT: These resources use Traefik CRDs which are installed by the
# Traefik Helm chart (traefik.tf). You must apply traefik.tf first:
#   make apply-traefik
# Then apply these resources:
#   make apply-ingress
# =============================================================================

# Variables
variable "traefik_basic_auth_users" {
  description = "Basic auth credentials in htpasswd format. Generate with: htpasswd -nb username password"
  type        = string
  sensitive   = true
}

variable "traefik_dashboard_enabled" {
  description = "Enable the Traefik dashboard IngressRoute"
  type        = bool
  default     = true
}

variable "rate_limit_average" {
  description = "Rate limit: average requests per second"
  type        = number
  default     = 100
}

variable "rate_limit_burst" {
  description = "Rate limit: maximum burst size"
  type        = number
  default     = 200
}

# --- Secrets ---

# Basic auth credentials secret (htpasswd format)
resource "kubernetes_secret" "traefik_basic_auth" {
  metadata {
    name      = "traefik-basic-auth"
    namespace = kubernetes_namespace.traefik.metadata[0].name
    labels    = var.common_labels
  }

  data = {
    users = var.traefik_basic_auth_users
  }
}

# --- Middleware ---

# HTTPS Redirect middleware (applied globally via entrypoint, but available explicitly too)
resource "kubernetes_manifest" "middleware_redirect_https" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "redirect-https"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      redirectScheme = {
        scheme    = "https"
        permanent = true
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# Rate limiting middleware
resource "kubernetes_manifest" "middleware_rate_limit" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "rate-limit"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      rateLimit = {
        average = var.rate_limit_average
        burst   = var.rate_limit_burst
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# Strip /s/<name> prefix for ClaudeCluster sandbox IngressRoutes so the
# upstream code-server (port 8080) and agent WebSocket (port 3000) see
# the request at /. The backend creates per-sandbox IngressRoutes in the
# claude-sandboxes namespace and references this middleware by
# `traefik/sandbox-strip-prefix` (cross-namespace reference is allowed).
resource "kubernetes_manifest" "middleware_sandbox_strip_prefix" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "sandbox-strip-prefix"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      stripPrefixRegex = {
        regex = ["^/s/[^/]+"]
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# Basic auth middleware
resource "kubernetes_manifest" "middleware_basic_auth" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "basic-auth"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      basicAuth = {
        secret = kubernetes_secret.traefik_basic_auth.metadata[0].name
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# CrowdSec Bouncer Middleware
resource "kubernetes_manifest" "middleware_crowdsec_bouncer" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "crowdsec-bouncer"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      plugin = {
        bouncer = {
          Enabled               = "true"
          crowdsecMode          = "stream"
          crowdsecLapiHost      = "crowdsec-service.${kubernetes_namespace.crowdsec[0].metadata[0].name}.svc.cluster.local:8080"
          crowdsecLapiScheme    = "http"
          crowdsecLapiKey       = var.crowdsec_bouncer_key
          updateIntervalSeconds = 15
        }
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.crowdsec,
  ]
}

# OAuth2 Proxy ForwardAuth Middleware
resource "kubernetes_manifest" "middleware_oauth_forward_auth" {
  count = var.oauth_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "oauth-forward-auth"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      forwardAuth = {
        address            = "http://oauth2-auth-bridge.${kubernetes_namespace.oauth2_proxy[0].metadata[0].name}.svc.cluster.local/verify"
        trustForwardHeader = true
        authResponseHeaders = [
          "X-Auth-Request-User",
          "X-Auth-Request-Email",
          "X-Auth-Request-Access-Token",
          "Set-Cookie",
        ]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.oauth2_proxy,
  ]
}


# Redirect auth root to homepage
resource "kubernetes_manifest" "middleware_auth_redirect_homepage" {
  count = var.oauth_enabled && var.homepage_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "auth-redirect-homepage"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      redirectRegex = {
        regex       = "^https://auth\\.${replace(var.traefik_domain, ".", "\\.")}/$"
        replacement = "https://homepage.${var.traefik_domain}/"
        permanent   = false
      }
    }
  }

  depends_on = [helm_release.traefik]
}

# OAuth2 Proxy IngressRoute (callback + sign-in)
resource "kubernetes_manifest" "ingressroute_oauth2_proxy" {
  count = var.oauth_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "oauth2-proxy"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`auth.${var.traefik_domain}`) && PathPrefix(`/oauth2`)"
          kind  = "Rule"
          middlewares = [
            {
              name      = "crowdsec-bouncer"
              namespace = kubernetes_namespace.traefik.metadata[0].name
            },
          ]
          services = [{
            name      = "oauth2-proxy"
            namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
            port      = 80
          }]
        },
        {
          match = "Host(`auth.${var.traefik_domain}`)"
          kind  = "Rule"
          middlewares = [
            {
              name      = "auth-redirect-homepage"
              namespace = kubernetes_namespace.traefik.metadata[0].name
            },
          ]
          services = [{
            name      = "oauth2-proxy"
            namespace = kubernetes_namespace.oauth2_proxy[0].metadata[0].name
            port      = 80
          }]
        },
      ]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.oauth2_proxy,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}

# ServersTransport for backends with self-signed TLS (e.g. K8s Dashboard)
resource "kubernetes_manifest" "servers_transport_insecure" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "ServersTransport"
    metadata = {
      name      = "insecure-skip-verify"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      insecureSkipVerify = true
    }
  }

  depends_on = [helm_release.traefik]
}

# --- IngressRoutes ---

# Traefik Dashboard
resource "kubernetes_manifest" "ingressroute_traefik_dashboard" {
  count = var.traefik_dashboard_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`traefik.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name = "api@internal"
          kind = "TraefikService"
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Grafana
resource "kubernetes_manifest" "ingressroute_grafana" {
  count = var.monitoring_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "grafana"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`grafana.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "prometheus-stack-grafana"
          namespace = kubernetes_namespace.monitoring[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.prometheus_stack,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}

# Prometheus
resource "kubernetes_manifest" "ingressroute_prometheus" {
  count = var.monitoring_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "prometheus"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`prometheus.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "prometheus-stack-kube-prom-prometheus"
          namespace = kubernetes_namespace.monitoring[0].metadata[0].name
          port      = 9090
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.prometheus_stack,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# AlertManager
resource "kubernetes_manifest" "ingressroute_alertmanager" {
  count = var.monitoring_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "alertmanager"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`alertmanager.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "prometheus-stack-kube-prom-alertmanager"
          namespace = kubernetes_namespace.monitoring[0].metadata[0].name
          port      = 9093
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.prometheus_stack,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# BaGet
resource "kubernetes_manifest" "ingressroute_baget" {
  count = var.baget_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "baget"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`packages.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.baget[0].metadata[0].name
          namespace = kubernetes_namespace.baget[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.baget,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}

# Longhorn UI
resource "kubernetes_manifest" "ingressroute_longhorn" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "longhorn"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`longhorn.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.longhorn_frontend_lb.metadata[0].name
          namespace = kubernetes_namespace.longhorn_system.metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.longhorn_frontend_lb,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Headlamp Dashboard
resource "kubernetes_manifest" "ingressroute_dashboard" {
  count = var.kubernetes_dashboard_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "headlamp"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`dashboard.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "headlamp"
          namespace = kubernetes_namespace.headlamp[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.headlamp,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# n8n
resource "kubernetes_manifest" "ingressroute_n8n" {
  count = var.n8n_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "n8n"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        # Webhook & OAuth-callback paths bypass the forward-auth wall so
        # external systems (and n8n's own credential OAuth flows) can reach
        # n8n without an SSO session. Longer rule wins by Traefik priority.
        {
          match = "Host(`n8n.${var.traefik_domain}`) && (PathPrefix(`/webhook`) || PathPrefix(`/webhook-test`) || PathPrefix(`/webhook-waiting`) || PathPrefix(`/form`) || PathPrefix(`/form-test`) || PathPrefix(`/form-waiting`) || PathPrefix(`/rest/oauth2-credential/callback`))"
          kind  = "Rule"
          middlewares = [
            {
              name      = "crowdsec-bouncer"
              namespace = kubernetes_namespace.traefik.metadata[0].name
            },
          ]
          services = [{
            name      = kubernetes_service.n8n[0].metadata[0].name
            namespace = kubernetes_namespace.n8n[0].metadata[0].name
            port      = 80
          }]
        },
        {
          match = "Host(`n8n.${var.traefik_domain}`)"
          kind  = "Rule"
          middlewares = [
            {
              name      = "crowdsec-bouncer"
              namespace = kubernetes_namespace.traefik.metadata[0].name
            },
            {
              name      = "oauth-forward-auth"
              namespace = kubernetes_namespace.traefik.metadata[0].name
            },
          ]
          services = [{
            name      = kubernetes_service.n8n[0].metadata[0].name
            namespace = kubernetes_namespace.n8n[0].metadata[0].name
            port      = 80
          }]
        },
      ]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.n8n,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Prowlarr
resource "kubernetes_manifest" "ingressroute_prowlarr" {
  count = var.prowlarr_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "prowlarr"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`prowlarr.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.prowlarr[0].metadata[0].name
          namespace = kubernetes_namespace.prowlarr[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.prowlarr,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Sonarr
resource "kubernetes_manifest" "ingressroute_sonarr" {
  count = var.sonarr_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "sonarr"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`sonarr.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.sonarr[0].metadata[0].name
          namespace = kubernetes_namespace.sonarr[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.sonarr,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Radarr
resource "kubernetes_manifest" "ingressroute_radarr" {
  count = var.radarr_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "radarr"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`radarr.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.radarr[0].metadata[0].name
          namespace = kubernetes_namespace.radarr[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.radarr,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# qBittorrent
resource "kubernetes_manifest" "ingressroute_qbittorrent" {
  count = var.qbittorrent_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "qbittorrent"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`qbit.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.qbittorrent[0].metadata[0].name
          namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.qbittorrent,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Emby
resource "kubernetes_manifest" "ingressroute_emby" {
  count = var.emby_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "emby"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`emby.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.emby[0].metadata[0].name
          namespace = kubernetes_namespace.emby[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.emby,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}

# Bazarr
resource "kubernetes_manifest" "ingressroute_bazarr" {
  count = var.bazarr_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "bazarr"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`bazarr.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.bazarr[0].metadata[0].name
          namespace = kubernetes_namespace.bazarr[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.bazarr,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Jackett
resource "kubernetes_manifest" "ingressroute_jackett" {
  count = var.jackett_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "jackett"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`jackett.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.jackett[0].metadata[0].name
          namespace = kubernetes_namespace.jackett[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.jackett,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}


# Cleanuparr
resource "kubernetes_manifest" "ingressroute_cleanuparr" {
  count = var.cleanuparr_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "cleanuparr"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`cleanuparr.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.cleanuparr[0].metadata[0].name
          namespace = kubernetes_namespace.cleanuparr[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.cleanuparr,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# SABnzbd
resource "kubernetes_manifest" "ingressroute_sabnzbd" {
  count = var.sabnzbd_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "sabnzbd"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`sabnzbd.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.sabnzbd[0].metadata[0].name
          namespace = kubernetes_namespace.sabnzbd[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.sabnzbd,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Notifiarr
resource "kubernetes_manifest" "ingressroute_notifiarr" {
  count = var.notifiarr_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "notifiarr"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`notifiarr.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.notifiarr[0].metadata[0].name
          namespace = kubernetes_namespace.notifiarr[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.notifiarr,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# --- Wave 5: AI/ML Stack ---

resource "kubernetes_manifest" "ingressroute_ollama" {
  count = var.ollama_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "ollama"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`ollama.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.ollama[0].metadata[0].name
          namespace = kubernetes_namespace.ollama[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.ollama,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

resource "kubernetes_manifest" "ingressroute_localai" {
  count = var.localai_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "localai"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`localai.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "localai"
          namespace = kubernetes_namespace.localai[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.localai,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

resource "kubernetes_manifest" "ingressroute_qdrant" {
  count = var.qdrant_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "qdrant"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`qdrant.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.qdrant[0].metadata[0].name
          namespace = kubernetes_namespace.qdrant[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.qdrant,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

resource "kubernetes_manifest" "ingressroute_chromadb" {
  count = var.chromadb_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "chromadb"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`chromadb.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.chromadb[0].metadata[0].name
          namespace = kubernetes_namespace.chromadb[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.chromadb,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

resource "kubernetes_manifest" "ingressroute_comfyui" {
  count = var.comfyui_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "comfyui"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`comfyui.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.comfyui[0].metadata[0].name
          namespace = kubernetes_namespace.comfyui[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.comfyui,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Homepage Dashboard
resource "kubernetes_manifest" "ingressroute_homepage" {
  count = var.homepage_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "homepage"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`homepage.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.homepage[0].metadata[0].name
          namespace = kubernetes_namespace.homepage[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.homepage,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Devtron Dashboard
resource "kubernetes_manifest" "ingressroute_devtron" {
  count = var.devtron_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "devtron"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`devtron.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "devtron-service"
          namespace = kubernetes_namespace.devtron[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    helm_release.devtron,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# --- Static Sites ---

# IngressRoute per static site (each on its own primary domain)
resource "kubernetes_manifest" "ingressroute_static_site" {
  for_each = var.static_sites_enabled ? { for site in var.static_sites : site.domain => site } : {}

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "static-site-${replace(each.key, ".", "-")}"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`${each.key}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.static_sites[0].metadata[0].name
          namespace = kubernetes_namespace.static_sites[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = each.key
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.static_sites,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}

# Planning Poker
resource "kubernetes_manifest" "ingressroute_poker" {
  count = var.poker_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "poker"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`poker.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.poker[0].metadata[0].name
          namespace = kubernetes_namespace.poker[0].metadata[0].name
          port      = 3000
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.poker,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}

# ClaudeCluster — Management UI, Chat UI, and API
# Sandbox-specific routes (/s/{name}/) are created dynamically by the backend.
# Traefik resolves rule conflicts by specificity: PathPrefix('/s/name/') beats Host-only.
resource "kubernetes_manifest" "ingressroute_claudecluster" {
  count = var.claudecluster_enabled ? 1 : 0

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "claudecluster"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`claude.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "oauth-forward-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.claudecluster_backend[0].metadata[0].name
          namespace = kubernetes_namespace.claude_sandbox[0].metadata[0].name
          port      = 80
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.claudecluster_backend,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Cams Web Toys — one IngressRoute per enabled toy subdomain. All routes target
# the same Service; the SPA's host-redirect plugin maps the leftmost host label
# to the matching page on first load. Public auth, matching the existing poker
# IngressRoute (crowdsec-bouncer only, no oauth-forward-auth) so guests can
# join standup/poker rooms without a login.
resource "kubernetes_manifest" "ingressroute_cams_web_toys" {
  for_each = local.cams_web_toys_subdomains

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "cams-web-toys-${each.key}"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`${each.value}.${var.traefik_domain}`)"
        kind  = "Rule"
        middlewares = [
          {
            name      = "crowdsec-bouncer"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.cams_web_toys[0].metadata[0].name
          namespace = kubernetes_namespace.cams_web_toys[0].metadata[0].name
          port      = 3000
        }]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = var.traefik_domain
          sans = ["*.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [
    helm_release.traefik,
    kubernetes_service.cams_web_toys,
    kubernetes_manifest.middleware_crowdsec_bouncer,
  ]
}
