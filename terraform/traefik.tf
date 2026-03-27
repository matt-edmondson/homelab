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

      # Transport timeouts — prevent premature disconnects for
      # long-polling (socket.io) and slow backend responses
      additionalArguments = [
        "--entryPoints.websecure.transport.respondingTimeouts.readTimeout=0",
        "--entryPoints.websecure.transport.respondingTimeouts.idleTimeout=600",
        "--serversTransport.forwardingTimeouts.dialTimeout=30s",
        "--serversTransport.forwardingTimeouts.responseHeaderTimeout=0s",
        "--serversTransport.forwardingTimeouts.idleConnTimeout=300s",
        "--serversTransport.maxIdleConnsPerHost=32",
      ]

      # CrowdSec Bouncer Plugin
      experimental = {
        plugins = {
          bouncer = {
            moduleName = "github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin"
            version    = "v1.5.1"
          }
        }
      }

      # Logging
      logs = {
        general = {
          level = var.traefik_log_level
        }
        access = {
          enabled = true
          format  = "json"
        }
      }

      # API — expose internally so Homepage widget can reach it
      api = {
        dashboard = true
        insecure  = true
      }

      # Entrypoints
      ports = {
        traefik = {
          expose = {
            default = true
          }
        }
        web = {
          port        = 8000
          exposedPort = 80
          protocol    = "TCP"
          redirections = {
            entryPoint = {
              to     = "websecure"
              scheme = "https"
            }
          }
        }
        websecure = {
          port        = 8443
          exposedPort = 443
          protocol    = "TCP"
          tls = {
            enabled      = true
            certResolver = "letsencrypt"
            domains = [{
              main = var.traefik_domain
              sans = ["*.${var.traefik_domain}"]
            }]
          }
        }
      }

      # Service configuration — single LoadBalancer via kube-vip static ARP
      service = {
        type = "LoadBalancer"
        spec = {
          loadBalancerIP = "192.168.0.238"
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
              provider         = "azuredns"
              delayBeforeCheck = "30"
              resolvers        = ["1.1.1.1:53", "8.8.8.8:53"]
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
        {
          name  = "AZURE_ZONE_NAME"
          value = var.traefik_domain
        },
        {
          name  = "AZURE_PROPAGATION_TIMEOUT"
          value = "300"
        },
        {
          name  = "AZURE_POLLING_INTERVAL"
          value = "10"
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
        fsGroup             = 65532
        fsGroupChangePolicy = "OnRootMismatch"
      }

      # Enable Traefik dashboard (exposed via IngressRoute in ingress.tf)
      ingressRoute = {
        dashboard = {
          enabled = false # We create our own IngressRoute with auth in ingress.tf
        }
      }

      # Providers — enable Kubernetes CRD provider
      providers = {
        kubernetesCRD = {
          enabled             = true
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
    kubernetes_daemonset.kube_vip,
    helm_release.crowdsec,
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
      dashboard     = "https://traefik.${var.traefik_domain}"
      grafana       = "https://grafana.${var.traefik_domain}"
      prometheus    = "https://prometheus.${var.traefik_domain}"
      alertmanager  = "https://alertmanager.${var.traefik_domain}"
      baget         = "https://packages.${var.traefik_domain}"
      longhorn      = "https://longhorn.${var.traefik_domain}"
      dashboard_k8s = "https://dashboard.${var.traefik_domain}"
    }
    commands = {
      get_ip      = "kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
      check_pods  = "kubectl get pods -n traefik"
      check_certs = "kubectl get secret -n traefik"
      logs        = "kubectl logs -n traefik -l app.kubernetes.io/name=traefik -f"
    }
  }
}
