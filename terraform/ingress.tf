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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "basic-auth"
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_basic_auth,
  ]
}

# Grafana
resource "kubernetes_manifest" "ingressroute_grafana" {
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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "prometheus-stack-grafana"
          namespace = kubernetes_namespace.monitoring.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
  ]
}

# Prometheus
resource "kubernetes_manifest" "ingressroute_prometheus" {
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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "basic-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "prometheus-stack-kube-prom-prometheus"
          namespace = kubernetes_namespace.monitoring.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_basic_auth,
  ]
}

# AlertManager
resource "kubernetes_manifest" "ingressroute_alertmanager" {
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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "basic-auth"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = "prometheus-stack-kube-prom-alertmanager"
          namespace = kubernetes_namespace.monitoring.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_basic_auth,
  ]
}

# BaGet
resource "kubernetes_manifest" "ingressroute_baget" {
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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name      = kubernetes_service.baget.metadata[0].name
          namespace = kubernetes_namespace.baget.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
          {
            name      = "basic-auth"
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_basic_auth,
  ]
}

# Kubernetes Dashboard (backend uses HTTPS on port 8443)
resource "kubernetes_manifest" "ingressroute_dashboard" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "kubernetes-dashboard"
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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
        ]
        services = [{
          name             = kubernetes_service.kubernetes_dashboard_lb.metadata[0].name
          namespace        = kubernetes_namespace.kubernetes_dashboard.metadata[0].name
          port             = 443
          scheme           = "https"
          serversTransport = "insecure-skip-verify"
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
    kubernetes_service.kubernetes_dashboard_lb,
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.servers_transport_insecure,
  ]
}
