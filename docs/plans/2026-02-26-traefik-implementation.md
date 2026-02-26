# Traefik Reverse Proxy Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy Traefik as a central reverse proxy, replacing individual LoadBalancer services with hostname-based routing through a single entry point with TLS and middleware.

**Architecture:** Traefik deployed via Helm chart in its own namespace with Let's Encrypt ACME (Azure DNS challenge). All existing LoadBalancer services converted to ClusterIP. Routing handled by Traefik IngressRoute CRDs defined as `kubernetes_manifest` resources in a dedicated `ingress.tf` file. Two-phase deploy: Traefik Helm first (installs CRDs), then IngressRoutes second.

**Tech Stack:** Terraform, Helm (traefik/traefik chart), Traefik v3 CRDs (IngressRoute, Middleware, ServersTransport), Let's Encrypt ACME, Azure DNS

---

## Important Notes

- All commands run from `terraform/` directory
- `kubernetes_manifest` resources require Traefik CRDs to exist at plan time. This means Traefik Helm must be applied before IngressRoutes can be planned/applied. The Makefile component targets handle this ordering.
- For greenfield deploys: `make apply-traefik` first, then `make apply-ingress`
- Basic auth uses htpasswd format. Users generate credentials with: `htpasswd -nb username password`

---

### Task 1: Create `terraform/traefik.tf` — Core Traefik Deployment

**Files:**
- Create: `terraform/traefik.tf`

**Step 1: Write traefik.tf**

This file creates the traefik namespace, an Azure DNS credentials secret, and the Traefik Helm release with ACME configuration and Longhorn persistence.

```hcl
# =============================================================================
# Traefik Reverse Proxy
# =============================================================================
# Traefik serves as the single ingress point for all cluster services.
# It provides:
#   - Hostname-based routing via IngressRoute CRDs
#   - Automatic TLS via Let's Encrypt ACME (Azure DNS challenge)
#   - Middleware support (HTTPS redirect, basic auth, rate limiting)
#
# Deployment order: Apply this BEFORE ingress.tf (Traefik installs the CRDs
# that IngressRoute resources depend on).
# =============================================================================

# Variables
variable "traefik_chart_version" {
  description = "Traefik Helm chart version"
  type        = string
  default     = "34.5.0"
}

variable "traefik_domain" {
  description = "Base domain for homelab services (e.g. example.com)"
  type        = string
}

variable "traefik_acme_email" {
  description = "Email address for Let's Encrypt ACME registration"
  type        = string
}

variable "azure_dns_client_id" {
  description = "Azure AD application (client) ID for DNS challenge"
  type        = string
}

variable "azure_dns_client_secret" {
  description = "Azure AD application client secret for DNS challenge"
  type        = string
  sensitive   = true
}

variable "azure_dns_tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "azure_dns_subscription_id" {
  description = "Azure subscription ID containing the DNS zone"
  type        = string
}

variable "azure_dns_resource_group" {
  description = "Azure resource group containing the DNS zone"
  type        = string
}

variable "traefik_log_level" {
  description = "Traefik log level"
  type        = string
  default     = "ERROR"
}

variable "traefik_acme_storage_size" {
  description = "PVC size for ACME certificate storage"
  type        = string
  default     = "1Gi"
}

# Namespace
resource "kubernetes_namespace" "traefik" {
  metadata {
    name   = "traefik"
    labels = var.common_labels
  }
}

# Azure DNS credentials secret (referenced by Traefik env vars)
resource "kubernetes_secret" "traefik_azure_dns" {
  metadata {
    name      = "traefik-azure-dns"
    namespace = kubernetes_namespace.traefik.metadata[0].name
    labels    = var.common_labels
  }

  data = {
    client-secret = var.azure_dns_client_secret
  }
}

# Traefik Helm Release
resource "helm_release" "traefik" {
  name       = "traefik"
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = var.traefik_chart_version
  namespace  = kubernetes_namespace.traefik.metadata[0].name

  values = [
    yamlencode({
      # Global settings
      globalArguments = []

      # Logging
      logs = {
        general = {
          level = var.traefik_log_level
        }
        access = {
          enabled = true
        }
      }

      # Entrypoints
      ports = {
        web = {
          port = 8000
          exposedPort = 80
          protocol = "TCP"
          redirections = {
            entryPoint = {
              to   = "websecure"
              scheme = "https"
            }
          }
        }
        websecure = {
          port = 8443
          exposedPort = 443
          protocol = "TCP"
          tls = {
            enabled = true
            certResolver = "letsencrypt"
            domains = [{
              main = var.traefik_domain
              sans = ["*.${var.traefik_domain}"]
            }]
          }
        }
      }

      # Service configuration — single LoadBalancer via kube-vip DHCP
      service = {
        type = "LoadBalancer"
        spec = {
          loadBalancerIP = "0.0.0.0"
        }
        annotations = {
          "kube-vip.io/loadbalancerHostname" = "traefik"
        }
      }

      # ACME Certificate Resolver — Let's Encrypt via Azure DNS challenge
      certificatesResolvers = {
        letsencrypt = {
          acme = {
            email   = var.traefik_acme_email
            storage = "/data/acme.json"
            dnsChallenge = {
              provider = "azuredns"
            }
          }
        }
      }

      # Azure DNS environment variables
      env = [
        {
          name  = "AZURE_CLIENT_ID"
          value = var.azure_dns_client_id
        },
        {
          name = "AZURE_CLIENT_SECRET"
          valueFrom = {
            secretKeyRef = {
              name = kubernetes_secret.traefik_azure_dns.metadata[0].name
              key  = "client-secret"
            }
          }
        },
        {
          name  = "AZURE_SUBSCRIPTION_ID"
          value = var.azure_dns_subscription_id
        },
        {
          name  = "AZURE_TENANT_ID"
          value = var.azure_dns_tenant_id
        },
        {
          name  = "AZURE_RESOURCE_GROUP"
          value = var.azure_dns_resource_group
        },
      ]

      # Persistence for ACME cert storage on Longhorn
      persistence = {
        enabled      = true
        storageClass = data.kubernetes_storage_class.longhorn.metadata[0].name
        size         = var.traefik_acme_storage_size
        accessMode   = "ReadWriteOnce"
      }

      # Init container to set correct permissions on acme.json
      deployment = {
        initContainers = [{
          name    = "volume-permissions"
          image   = "busybox:latest"
          command = ["sh", "-c", "touch /data/acme.json; chmod -v 600 /data/acme.json"]
          volumeMounts = [{
            mountPath = "/data"
            name      = "data"
          }]
        }]
      }

      # Pod security context
      podSecurityContext = {
        fsGroup            = 65532
        fsGroupChangePolicy = "OnRootMismatch"
      }

      # Enable Traefik dashboard (exposed via IngressRoute in ingress.tf)
      ingressRoute = {
        dashboard = {
          enabled = false  # We create our own IngressRoute with auth in ingress.tf
        }
      }

      # Providers — enable Kubernetes CRD provider
      providers = {
        kubernetesCRD = {
          enabled    = true
          allowCrossNamespace = true
        }
        kubernetesIngress = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.traefik,
    kubernetes_secret.traefik_azure_dns,
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
    kubernetes_daemonset.kube_vip
  ]

  timeout = 300
  wait    = true
}

# Outputs
output "traefik_info" {
  description = "Traefik reverse proxy information"
  value = {
    namespace     = kubernetes_namespace.traefik.metadata[0].name
    chart_version = var.traefik_chart_version
    domain        = var.traefik_domain
    ip_address = try(
      helm_release.traefik.status,
      "pending (check: kubectl get svc -n traefik traefik)"
    )
    access = {
      dashboard = "https://traefik.${var.traefik_domain}"
      grafana   = "https://grafana.${var.traefik_domain}"
      prometheus = "https://prometheus.${var.traefik_domain}"
      alertmanager = "https://alertmanager.${var.traefik_domain}"
      baget     = "https://baget.${var.traefik_domain}"
      longhorn  = "https://longhorn.${var.traefik_domain}"
      dashboard_k8s = "https://dashboard.${var.traefik_domain}"
    }
    commands = {
      get_ip     = "kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
      check_pods = "kubectl get pods -n traefik"
      check_certs = "kubectl get secret -n traefik"
      logs       = "kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f"
    }
  }
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt traefik.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/traefik.tf
git commit -m "feat: add Traefik Helm release with Azure DNS ACME"
```

---

### Task 2: Convert Existing Services to ClusterIP

**Files:**
- Modify: `terraform/baget.tf` (lines 245-275 — service resource, lines 277-308 — output)
- Modify: `terraform/monitoring.tf` (lines 86-92 — Prometheus service, lines 101-107 — Grafana service)
- Modify: `terraform/longhorn.tf` (lines 157-189 — UI LB service, lines 192-210 — output)
- Modify: `terraform/kubernetes-dashboard.tf` (lines 184-216 — LB service, lines 219-261 — output)

**Step 1: Modify baget.tf service**

Replace the `kubernetes_service.baget` resource (lines 245-275). Change type to ClusterIP, remove `load_balancer_ip`, remove kube-vip annotation, remove kube-vip dependency:

```hcl
resource "kubernetes_service" "baget" {
  depends_on = [
    kubernetes_deployment.baget
  ]

  metadata {
    name      = "baget-service"
    namespace = kubernetes_namespace.baget.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "baget"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "baget"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }
}
```

Update the `baget_info` output (lines 277-308). Remove LoadBalancer IP references, update access URLs to use Traefik domain:

```hcl
output "baget_info" {
  description = "Baget NuGet server information"
  value = {
    namespace    = kubernetes_namespace.baget.metadata[0].name
    service_name = kubernetes_service.baget.metadata[0].name
    storage_size = var.baget_storage_size

    access = {
      web_ui    = "https://baget.${var.traefik_domain}"
      nuget_url = "https://baget.${var.traefik_domain}/v3/index.json"
    }

    usage = {
      add_source   = "dotnet nuget add source https://baget.${var.traefik_domain}/v3/index.json -n \"Homelab Baget\""
      push_package = "dotnet nuget push package.nupkg -s https://baget.${var.traefik_domain}/v3/index.json -k <your-api-key>"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.baget.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.baget.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.baget.metadata[0].name} -l app=baget -f"
    }
  }

  sensitive = true
}
```

**Step 2: Modify monitoring.tf Helm values**

In `helm_release.prometheus_stack` values (lines 86-92), change Prometheus service from LoadBalancer to ClusterIP:

```hcl
        service = {
          type = "ClusterIP"
        }
```

(Remove `loadBalancerIP` and kube-vip annotation.)

In the Grafana service section (lines 101-107), change from LoadBalancer to ClusterIP:

```hcl
        service = {
          type = "ClusterIP"
        }
```

(Remove `loadBalancerIP` and kube-vip annotation.)

Remove `kubernetes_daemonset.kube_vip` from the `depends_on` list (line 166).

**Step 3: Modify longhorn.tf UI service**

Replace the `kubernetes_service.longhorn_frontend_lb` resource (lines 157-189). Change to ClusterIP, remove kube-vip references:

```hcl
resource "kubernetes_service" "longhorn_frontend_lb" {
  metadata {
    name      = "longhorn-frontend-lb"
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "longhorn-ui"
      "app.kubernetes.io/component" = "frontend"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "longhorn-ui"
    }
    port {
      name        = "http"
      port        = 80
      target_port = 8000
      protocol    = "TCP"
    }
  }

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]
}
```

Update the `longhorn_info` output (lines 192-210). Replace LoadBalancer IP with Traefik domain URL:

```hcl
output "longhorn_info" {
  description = "Longhorn storage system information"
  value = {
    namespace           = kubernetes_namespace.longhorn_system.metadata[0].name
    chart_version       = var.longhorn_chart_version
    replica_count       = var.longhorn_replica_count
    storage_class       = data.kubernetes_storage_class.longhorn.metadata[0].name
    ui_service         = kubernetes_service.longhorn_frontend_lb.metadata[0].name
    ui_url             = "https://longhorn.${var.traefik_domain}"
    commands = {
      check_pods    = "kubectl get pods -n ${kubernetes_namespace.longhorn_system.metadata[0].name}"
      check_volumes = "kubectl get pv,pvc --all-namespaces"
      ui_access     = "Access Longhorn UI at: https://longhorn.${var.traefik_domain}"
    }
  }
}
```

**Step 4: Modify kubernetes-dashboard.tf LB service**

Replace the `kubernetes_service.kubernetes_dashboard_lb` resource (lines 184-216). Change to ClusterIP:

```hcl
resource "kubernetes_service" "kubernetes_dashboard_lb" {
  metadata {
    name      = "kubernetes-dashboard-lb"
    namespace = kubernetes_namespace.kubernetes_dashboard.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "kubernetes-dashboard"
      "app.kubernetes.io/component" = "kubernetes-dashboard"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      "app.kubernetes.io/name"      = "kong"
      "app.kubernetes.io/component" = "app"
    }
    port {
      name        = "https"
      port        = 443
      target_port = 8443
      protocol    = "TCP"
    }
  }

  depends_on = [
    helm_release.kubernetes_dashboard
  ]
}
```

Update the `kubernetes_dashboard_info` output to use Traefik domain URL instead of LoadBalancer IP.

**Step 5: Validate**

Run: `cd terraform && terraform fmt -recursive && terraform validate`
Expected: "Success! The configuration is valid."

**Step 6: Commit**

```bash
git add terraform/baget.tf terraform/monitoring.tf terraform/longhorn.tf terraform/kubernetes-dashboard.tf
git commit -m "refactor: convert all services from LoadBalancer to ClusterIP for Traefik routing"
```

---

### Task 3: Create `terraform/ingress.tf` — Middleware and IngressRoutes

**Files:**
- Create: `terraform/ingress.tf`

**Step 1: Write ingress.tf**

This file defines all Traefik middleware and IngressRoute resources using `kubernetes_manifest`. These require Traefik CRDs to exist (installed by the Helm chart in Task 1).

```hcl
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
        match = "Host(`baget.${var.traefik_domain}`)"
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
          name            = kubernetes_service.kubernetes_dashboard_lb.metadata[0].name
          namespace       = kubernetes_namespace.kubernetes_dashboard.metadata[0].name
          port            = 443
          scheme          = "https"
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
```

**Step 2: Validate** (requires Traefik CRDs — skip if not yet deployed)

Run: `cd terraform && terraform fmt ingress.tf && terraform validate`
Note: `terraform validate` will fail if Traefik CRDs don't exist yet. This is expected for greenfield deploys.

**Step 3: Commit**

```bash
git add terraform/ingress.tf
git commit -m "feat: add IngressRoute and Middleware definitions for all services"
```

---

### Task 4: Update `terraform/terraform.tfvars.example`

**Files:**
- Modify: `terraform/terraform.tfvars.example`

**Step 1: Add Traefik variables to terraform.tfvars.example**

Add the following section after the "Kubernetes Dashboard Configuration" section (after line 43):

```hcl
# Traefik Reverse Proxy Configuration
traefik_chart_version     = "34.5.0"
traefik_domain            = "example.com"            # Your domain (services will be at grafana.example.com, etc.)
traefik_acme_email        = "admin@example.com"      # Let's Encrypt registration email
traefik_log_level         = "ERROR"
traefik_acme_storage_size = "1Gi"

# Azure DNS Challenge Credentials (for Let's Encrypt ACME)
azure_dns_client_id       = "your-azure-app-client-id"
azure_dns_client_secret   = "your-azure-app-client-secret"
azure_dns_tenant_id       = "your-azure-tenant-id"
azure_dns_subscription_id = "your-azure-subscription-id"
azure_dns_resource_group  = "your-dns-zone-resource-group"

# Traefik Basic Auth (htpasswd format — generate with: htpasswd -nb username password)
traefik_basic_auth_users  = "admin:$apr1$xyz$hashedpassword"

# Traefik Rate Limiting
rate_limit_average = 100    # Requests per second
rate_limit_burst   = 200    # Maximum burst size
```

Update the "Router DNS Setup" comment section (lines 45-53) to reflect the new Traefik-based setup:

```hcl
# DNS Setup (after deployment):
# 1. Deploy Traefik: make apply-traefik
# 2. Get Traefik IP: kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# 3. Create a wildcard DNS A record: *.example.com -> <traefik-ip>
#    Or create individual A records for each service subdomain
```

**Step 2: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "docs: add Traefik and Azure DNS variables to tfvars example"
```

---

### Task 5: Update `terraform/Makefile`

**Files:**
- Modify: `terraform/Makefile`

**Step 1: Add traefik and ingress to .PHONY declaration**

Add to the `.PHONY` line (line 4-10):
- `plan-traefik apply-traefik debug-traefik status-traefik`
- `plan-ingress apply-ingress debug-ingress status-ingress`

**Step 2: Add component plan targets**

After `plan-dns` target (around line 456), add:

```makefile
plan-traefik: check-vars check-init ## Plan Traefik reverse proxy
	@echo "Planning Traefik components..."
	terraform plan \
		-target=kubernetes_namespace.traefik \
		-target=kubernetes_secret.traefik_azure_dns \
		-target=helm_release.traefik

plan-ingress: check-vars check-init ## Plan ingress routes and middleware
	@echo "Planning ingress components..."
	terraform plan \
		-target=kubernetes_secret.traefik_basic_auth \
		-target=kubernetes_manifest.middleware_redirect_https \
		-target=kubernetes_manifest.middleware_rate_limit \
		-target=kubernetes_manifest.middleware_basic_auth \
		-target=kubernetes_manifest.servers_transport_insecure \
		-target=kubernetes_manifest.ingressroute_traefik_dashboard \
		-target=kubernetes_manifest.ingressroute_grafana \
		-target=kubernetes_manifest.ingressroute_prometheus \
		-target=kubernetes_manifest.ingressroute_alertmanager \
		-target=kubernetes_manifest.ingressroute_baget \
		-target=kubernetes_manifest.ingressroute_longhorn \
		-target=kubernetes_manifest.ingressroute_dashboard
```

**Step 3: Add component apply targets**

After `apply-dns` target (around line 505), add:

```makefile
apply-traefik: check-vars check-init ## Deploy Traefik reverse proxy
	@echo "Deploying Traefik..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.traefik \
		-target=kubernetes_secret.traefik_azure_dns \
		-target=helm_release.traefik

apply-ingress: check-vars check-init ## Deploy ingress routes and middleware
	@echo "Deploying ingress routes..."
	terraform apply -auto-approve \
		-target=kubernetes_secret.traefik_basic_auth \
		-target=kubernetes_manifest.middleware_redirect_https \
		-target=kubernetes_manifest.middleware_rate_limit \
		-target=kubernetes_manifest.middleware_basic_auth \
		-target=kubernetes_manifest.servers_transport_insecure \
		-target=kubernetes_manifest.ingressroute_traefik_dashboard \
		-target=kubernetes_manifest.ingressroute_grafana \
		-target=kubernetes_manifest.ingressroute_prometheus \
		-target=kubernetes_manifest.ingressroute_alertmanager \
		-target=kubernetes_manifest.ingressroute_baget \
		-target=kubernetes_manifest.ingressroute_longhorn \
		-target=kubernetes_manifest.ingressroute_dashboard
```

**Step 4: Add debug targets**

After the last `debug-*` target, add:

```makefile
debug-traefik: ## Debug Traefik reverse proxy
	@echo "=== Traefik Debug ==="
	@echo "Terraform Resources:"
	@terraform state list | grep traefik || echo "No Traefik resources found in state"
	@echo ""
	@echo "Traefik Pods:"
	@kubectl get pods -n traefik -o wide 2>/dev/null || echo "Traefik namespace not found"
	@echo ""
	@echo "Traefik Service:"
	@kubectl get svc -n traefik 2>/dev/null || echo "No Traefik services found"
	@echo ""
	@echo "IngressRoutes:"
	@kubectl get ingressroutes -A 2>/dev/null || echo "No IngressRoutes found"
	@echo ""
	@echo "Middleware:"
	@kubectl get middlewares -A 2>/dev/null || echo "No Middleware found"
	@echo ""
	@echo "Certificates:"
	@kubectl get certificates -A 2>/dev/null || echo "No certificates found"

debug-ingress: ## Debug ingress routes
	@echo "=== Ingress Routes Debug ==="
	@echo "IngressRoutes:"
	@kubectl get ingressroutes -A -o wide 2>/dev/null || echo "No IngressRoutes found"
	@echo ""
	@echo "Middleware:"
	@kubectl get middlewares -A -o wide 2>/dev/null || echo "No Middleware found"
	@echo ""
	@echo "ServersTransports:"
	@kubectl get serverstransports -A 2>/dev/null || echo "No ServersTransports found"
```

**Step 5: Add status targets**

After the last `status-*` target, add:

```makefile
status-traefik: ## Show Traefik status
	@echo "=== Traefik Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get pods -n traefik 2>nul || echo "Traefik not deployed"
	@kubectl get svc -n traefik 2>nul || echo "Traefik service not found"
else
	@kubectl get pods -n traefik 2>/dev/null || echo "Traefik not deployed"
	@kubectl get svc -n traefik 2>/dev/null || echo "Traefik service not found"
endif

status-ingress: ## Show ingress routes status
	@echo "=== Ingress Status ==="
ifeq ($(OS),Windows_NT)
	@kubectl get ingressroutes -A 2>nul || echo "No IngressRoutes found"
else
	@kubectl get ingressroutes -A 2>/dev/null || echo "No IngressRoutes found"
endif
```

**Step 6: Update deploy-core and deploy-apps**

Update `deploy-core` (around line 697) to include Traefik:

```makefile
deploy-core: ## Deploy core infrastructure (networking + storage + traefik)
	@echo "Deploying core infrastructure (networking + storage + traefik)..."
	$(MAKE) apply-networking
	$(MAKE) apply-storage
	$(MAKE) apply-traefik
	$(MAKE) apply-ingress
```

**Step 7: Update list-components**

Add Traefik and Ingress lines to the `list-components` target (around line 396-407):

```
@echo "🔀 Reverse Proxy -> traefik.tf          (Traefik ingress controller)"
@echo "🔗 Ingress       -> ingress.tf          (IngressRoutes and middleware)"
```

**Step 8: Update generate-secrets**

Add htpasswd generation to `generate-secrets` target (around line 386-393):

```makefile
	@echo "traefik_basic_auth_users = \"$$(htpasswd -nb admin $$(openssl rand -base64 16))\"" 2>/dev/null || echo "# traefik_basic_auth_users requires htpasswd tool (apache2-utils)"
```

**Step 9: Commit**

```bash
git add terraform/Makefile
git commit -m "feat: add Traefik and ingress Makefile targets"
```

---

### Task 6: Update `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update CLAUDE.md**

Add to the Architecture > File Organization section:
- `traefik.tf` — Traefik reverse proxy via Helm (ACME Let's Encrypt, Azure DNS challenge, Longhorn persistence)
- `ingress.tf` — IngressRoute and Middleware CRD resources for all services

Add to the Networking Model section:
- Traefik serves as the single ingress entry point. It receives a LoadBalancer IP from kube-vip and routes traffic to backend services by hostname via IngressRoute CRDs.
- All services are ClusterIP; external access is through Traefik only.

Add to Common Commands section:
```
make plan-traefik / make apply-traefik
make plan-ingress / make apply-ingress
```

Add to Key Patterns section:
- **Traefik CRD ordering** — Traefik Helm chart must be applied before IngressRoute resources (`make apply-traefik` then `make apply-ingress`). The CRDs don't exist until the Helm chart is installed.

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Traefik architecture"
```

---

### Task 7: Validate Full Configuration

**Step 1: Format all files**

Run: `cd terraform && terraform fmt -recursive`
Expected: Lists any files that were reformatted (or no output if already formatted)

**Step 2: Validate configuration**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."
Note: If Traefik CRDs don't exist yet, `kubernetes_manifest` resources may cause validation warnings. This is expected.

**Step 3: Plan (targeted — Traefik core only)**

Run: `cd terraform && make plan-traefik`
Expected: Shows plan to create namespace, secret, and Helm release. Review the plan output for correctness.

**Step 4: Commit final state**

```bash
git add -A
git commit -m "chore: final formatting and validation pass"
```

---

## Deployment Order (for reference)

For a fresh deployment with Traefik:

```bash
cd terraform
make init
make apply-networking    # flannel, kube-vip, metrics-server
make apply-storage       # longhorn
make apply-traefik       # traefik helm release (installs CRDs)
make apply-ingress       # IngressRoutes and middleware
make apply-monitoring    # prometheus-stack (now ClusterIP)
make apply-applications  # baget, dashboard (now ClusterIP)
```

For an existing deployment migration:

```bash
cd terraform
make apply-traefik       # deploy traefik first
make apply               # apply all changes (services become ClusterIP, IngressRoutes created)
```

After deployment:
1. Get Traefik IP: `kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'`
2. Create DNS: wildcard `*.yourdomain.com` A record pointing to the Traefik IP
3. Verify: `curl -k https://grafana.yourdomain.com` should reach Grafana
