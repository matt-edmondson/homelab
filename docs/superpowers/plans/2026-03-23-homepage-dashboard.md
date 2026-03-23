# Homepage Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Homepage (gethomepage.dev) as the homelab application portal with live service widgets, grouped by function, fully managed via Terraform.

**Architecture:** Single new file `homepage.tf` containing all resources (namespace, RBAC, ConfigMaps, Secret, Deployment, Service). Config is declarative via ConfigMaps — no persistent storage. Services list is dynamically built from `*_enabled` flags using Terraform locals and `yamlencode()`. IngressRoute and DNS record added to existing files.

**Tech Stack:** Terraform, Kubernetes, Homepage (ghcr.io/gethomepage/homepage), Traefik IngressRoute, Azure DNS

**Spec:** `docs/superpowers/specs/2026-03-23-homepage-dashboard-design.md`

---

### Task 1: Variables and Feature Flag

**Files:**
- Create: `terraform/homepage.tf` (variables section only — will be extended in subsequent tasks)

- [ ] **Step 1: Create `homepage.tf` with all variables**

```hcl
# =============================================================================
# Homepage Dashboard - Application Portal
# =============================================================================
# Homepage (gethomepage.dev) provides a modern dashboard with categorized links
# to all homelab services and live API-driven widgets.
# =============================================================================

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "homepage_enabled" {
  description = "Enable Homepage dashboard"
  type        = bool
  default     = false
}

variable "homepage_image" {
  description = "Homepage container image"
  type        = string
  default     = "ghcr.io/gethomepage/homepage"
}

variable "homepage_image_tag" {
  description = "Homepage container image tag"
  type        = string
  default     = "latest"
}

variable "homepage_memory_request" {
  description = "Memory request for Homepage container"
  type        = string
  default     = "128Mi"
}

variable "homepage_memory_limit" {
  description = "Memory limit for Homepage container"
  type        = string
  default     = "256Mi"
}

variable "homepage_cpu_request" {
  description = "CPU request for Homepage container"
  type        = string
  default     = "50m"
}

variable "homepage_cpu_limit" {
  description = "CPU limit for Homepage container"
  type        = string
  default     = "200m"
}

# Widget API keys (all optional — widgets degrade gracefully without them)

variable "sonarr_api_key" {
  description = "Sonarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "radarr_api_key" {
  description = "Radarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "prowlarr_api_key" {
  description = "Prowlarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "bazarr_api_key" {
  description = "Bazarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "jackett_api_key" {
  description = "Jackett API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "huntarr_api_key" {
  description = "Huntarr API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sabnzbd_api_key" {
  description = "SABnzbd API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "qbittorrent_username" {
  description = "qBittorrent username for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "qbittorrent_password" {
  description = "qBittorrent password for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

variable "emby_api_key" {
  description = "Emby API key for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}
```

- [ ] **Step 2: Validate**

Run: `cd terraform && make validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add terraform/homepage.tf
git commit -m "feat: add Homepage dashboard variables and feature flag"
```

---

### Task 2: Namespace, RBAC, and Service Account

**Files:**
- Modify: `terraform/homepage.tf` (append after variables)

- [ ] **Step 1: Add namespace and RBAC resources to `homepage.tf`**

Append after the variables section:

```hcl
# -----------------------------------------------------------------------------
# Namespace
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "homepage" {
  count = var.homepage_enabled ? 1 : 0

  metadata {
    name = "homepage"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "homepage"
    })
  }
}

# -----------------------------------------------------------------------------
# RBAC (for Kubernetes system widget — read-only cluster access)
# -----------------------------------------------------------------------------

resource "kubernetes_service_account" "homepage" {
  count = var.homepage_enabled ? 1 : 0

  metadata {
    name      = "homepage"
    namespace = kubernetes_namespace.homepage[0].metadata[0].name
    labels    = var.common_labels
  }
}

resource "kubernetes_cluster_role" "homepage" {
  count = var.homepage_enabled ? 1 : 0

  metadata {
    name   = "homepage-reader"
    labels = var.common_labels
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "pods", "namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["metrics.k8s.io"]
    resources  = ["nodes", "pods"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "homepage" {
  count = var.homepage_enabled ? 1 : 0

  metadata {
    name   = "homepage-reader"
    labels = var.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.homepage[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.homepage[0].metadata[0].name
    namespace = kubernetes_namespace.homepage[0].metadata[0].name
  }
}
```

- [ ] **Step 2: Validate**

Run: `cd terraform && make validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add terraform/homepage.tf
git commit -m "feat: add Homepage namespace and RBAC for Kubernetes widget"
```

---

### Task 3: ConfigMap and Secret

**Files:**
- Modify: `terraform/homepage.tf` (append locals + ConfigMap + Secret)

This is the largest task — it builds the dynamic service config using Terraform locals and `yamlencode()`.

- [ ] **Step 1: Add locals for dynamic service lists**

Append to `homepage.tf`:

```hcl
# -----------------------------------------------------------------------------
# Dynamic service configuration (conditional on *_enabled flags)
# -----------------------------------------------------------------------------

locals {
  homepage_media_services = concat(
    var.sonarr_enabled ? [{
      "Sonarr" = {
        href        = "https://sonarr.${var.traefik_domain}"
        icon        = "sonarr"
        description = "TV Shows"
        widget = {
          type = "sonarr"
          url  = "http://sonarr-service.sonarr.svc.cluster.local:8989"
          key  = "{{HOMEPAGE_VAR_SONARR_KEY}}"
        }
      }
    }] : [],
    var.radarr_enabled ? [{
      "Radarr" = {
        href        = "https://radarr.${var.traefik_domain}"
        icon        = "radarr"
        description = "Movies"
        widget = {
          type = "radarr"
          url  = "http://radarr-service.radarr.svc.cluster.local:7878"
          key  = "{{HOMEPAGE_VAR_RADARR_KEY}}"
        }
      }
    }] : [],
    var.bazarr_enabled ? [{
      "Bazarr" = {
        href        = "https://bazarr.${var.traefik_domain}"
        icon        = "bazarr"
        description = "Subtitles"
        widget = {
          type = "bazarr"
          url  = "http://bazarr-service.bazarr.svc.cluster.local:6767"
          key  = "{{HOMEPAGE_VAR_BAZARR_KEY}}"
        }
      }
    }] : [],
    var.prowlarr_enabled ? [{
      "Prowlarr" = {
        href        = "https://prowlarr.${var.traefik_domain}"
        icon        = "prowlarr"
        description = "Indexers"
        widget = {
          type = "prowlarr"
          url  = "http://prowlarr-service.prowlarr.svc.cluster.local:9696"
          key  = "{{HOMEPAGE_VAR_PROWLARR_KEY}}"
        }
      }
    }] : [],
    var.jackett_enabled ? [{
      "Jackett" = {
        href        = "https://jackett.${var.traefik_domain}"
        icon        = "jackett"
        description = "Indexer Proxy"
      }
    }] : [],
    var.huntarr_enabled ? [{
      "Huntarr" = {
        href        = "https://huntarr.${var.traefik_domain}"
        icon        = "huntarr"
        description = "Missing Media"
      }
    }] : [],
    var.cleanuparr_enabled ? [{
      "Cleanuparr" = {
        href        = "https://cleanuparr.${var.traefik_domain}"
        icon        = "cleanuparr"
        description = "Library Cleanup"
      }
    }] : [],
    var.notifiarr_enabled ? [{
      "Notifiarr" = {
        href        = "https://notifiarr.${var.traefik_domain}"
        icon        = "notifiarr"
        description = "Notifications"
      }
    }] : [],
  )

  homepage_download_services = concat(
    var.qbittorrent_enabled ? [{
      "qBittorrent" = {
        href        = "https://qbit.${var.traefik_domain}"
        icon        = "qbittorrent"
        description = "Torrents"
        widget = {
          type     = "qbittorrent"
          url      = "http://qbittorrent-service.qbittorrent.svc.cluster.local:8080"
          username = "{{HOMEPAGE_VAR_QBIT_USER}}"
          password = "{{HOMEPAGE_VAR_QBIT_PASS}}"
        }
      }
    }] : [],
    var.sabnzbd_enabled ? [{
      "SABnzbd" = {
        href        = "https://sabnzbd.${var.traefik_domain}"
        icon        = "sabnzbd"
        description = "Usenet"
        widget = {
          type = "sabnzbd"
          url  = "http://sabnzbd-service.sabnzbd.svc.cluster.local:8080"
          key  = "{{HOMEPAGE_VAR_SABNZBD_KEY}}"
        }
      }
    }] : [],
  )

  homepage_streaming_services = concat(
    var.emby_enabled ? [{
      "Emby" = {
        href        = "https://emby.${var.traefik_domain}"
        icon        = "emby"
        description = "Media Server"
        widget = {
          type = "emby"
          url  = "http://emby-service.emby.svc.cluster.local:8096"
          key  = "{{HOMEPAGE_VAR_EMBY_KEY}}"
        }
      }
    }] : [],
  )

  homepage_monitoring_services = concat(
    var.monitoring_enabled ? [
      {
        "Grafana" = {
          href        = "https://grafana.${var.traefik_domain}"
          icon        = "grafana"
          description = "Dashboards"
          widget = {
            type = "grafana"
            url  = "http://prometheus-stack-grafana.monitoring.svc.cluster.local:80"
          }
        }
      },
      {
        "Prometheus" = {
          href        = "https://prometheus.${var.traefik_domain}"
          icon        = "prometheus"
          description = "Metrics"
          widget = {
            type = "prometheus"
            url  = "http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090"
          }
        }
      },
      {
        "AlertManager" = {
          href        = "https://alertmanager.${var.traefik_domain}"
          icon        = "alertmanager"
          description = "Alerts"
        }
      },
    ] : [],
  )

  homepage_ai_services = concat(
    var.ollama_enabled ? [{
      "Ollama" = {
        href        = "https://ollama.${var.traefik_domain}"
        icon        = "ollama"
        description = "LLM Inference"
      }
    }] : [],
    var.qdrant_enabled ? [{
      "Qdrant" = {
        href        = "https://qdrant.${var.traefik_domain}"
        icon        = "qdrant"
        description = "Vector Database"
      }
    }] : [],
    var.chromadb_enabled ? [{
      "ChromaDB" = {
        href        = "https://chromadb.${var.traefik_domain}"
        icon        = "chromadb"
        description = "Vector Database"
      }
    }] : [],
    var.comfyui_enabled ? [{
      "ComfyUI" = {
        href        = "https://comfyui.${var.traefik_domain}"
        icon        = "comfyui"
        description = "Image Generation"
      }
    }] : [],
  )

  homepage_infra_services = concat(
    [{
      "Traefik" = {
        href        = "https://traefik.${var.traefik_domain}"
        icon        = "traefik"
        description = "Reverse Proxy"
        widget = {
          type = "traefik"
          url  = "http://traefik.traefik.svc.cluster.local:9000"
        }
      }
    }],
    [{
      "Longhorn" = {
        href        = "https://longhorn.${var.traefik_domain}"
        icon        = "longhorn"
        description = "Storage"
        widget = {
          type = "longhorn"
          url  = "http://longhorn-frontend-lb.longhorn-system.svc.cluster.local:80"
        }
      }
    }],
    var.kubernetes_dashboard_enabled ? [{
      "Headlamp" = {
        href        = "https://dashboard.${var.traefik_domain}"
        icon        = "headlamp"
        description = "K8s Dashboard"
      }
    }] : [],
    var.baget_enabled ? [{
      "BaGet" = {
        href        = "https://packages.${var.traefik_domain}"
        icon        = "nuget"
        description = "NuGet Packages"
      }
    }] : [],
    var.n8n_enabled ? [{
      "n8n" = {
        href        = "https://n8n.${var.traefik_domain}"
        icon        = "n8n"
        description = "Workflow Automation"
      }
    }] : [],
  )

  # Build final services list, filtering out empty groups
  homepage_services = concat(
    length(local.homepage_media_services) > 0 ? [{ "Media Management" = local.homepage_media_services }] : [],
    length(local.homepage_download_services) > 0 ? [{ "Downloads" = local.homepage_download_services }] : [],
    length(local.homepage_streaming_services) > 0 ? [{ "Media Streaming" = local.homepage_streaming_services }] : [],
    length(local.homepage_monitoring_services) > 0 ? [{ "Monitoring" = local.homepage_monitoring_services }] : [],
    length(local.homepage_ai_services) > 0 ? [{ "AI / ML" = local.homepage_ai_services }] : [],
    length(local.homepage_infra_services) > 0 ? [{ "Infrastructure" = local.homepage_infra_services }] : [],
  )
}
```

- [ ] **Step 2: Add ConfigMap and Secret**

Append to `homepage.tf`:

```hcl
# -----------------------------------------------------------------------------
# ConfigMap (Homepage YAML configuration)
# -----------------------------------------------------------------------------

resource "kubernetes_config_map" "homepage_config" {
  count = var.homepage_enabled ? 1 : 0

  metadata {
    name      = "homepage-config"
    namespace = kubernetes_namespace.homepage[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "settings.yaml" = yamlencode({
      title       = "Homelab"
      theme       = "dark"
      color       = "slate"
      headerStyle = "clean"
      layout = {
        "Media Management" = { style = "row", columns = 4 }
        "Downloads"        = { style = "row", columns = 2 }
        "Media Streaming"  = { style = "row", columns = 1 }
        "Monitoring"       = { style = "row", columns = 3 }
        "AI / ML"          = { style = "row", columns = 4 }
        "Infrastructure"   = { style = "row", columns = 3 }
      }
    })

    "services.yaml" = yamlencode(local.homepage_services)

    "widgets.yaml" = yamlencode([
      { kubernetes = {
        cluster = {
          show       = true
          cpu        = true
          memory     = true
          showLabel  = true
          label      = "cluster"
        }
      }},
      { search = {
        provider = "duckduckgo"
        target   = "_blank"
      }},
    ])
  }
}

# -----------------------------------------------------------------------------
# Secret (API keys for widget integrations)
# -----------------------------------------------------------------------------

resource "kubernetes_secret" "homepage_secrets" {
  count = var.homepage_enabled ? 1 : 0

  metadata {
    name      = "homepage-secrets"
    namespace = kubernetes_namespace.homepage[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    HOMEPAGE_VAR_SONARR_KEY   = var.sonarr_api_key
    HOMEPAGE_VAR_RADARR_KEY   = var.radarr_api_key
    HOMEPAGE_VAR_PROWLARR_KEY = var.prowlarr_api_key
    HOMEPAGE_VAR_BAZARR_KEY   = var.bazarr_api_key
    HOMEPAGE_VAR_SABNZBD_KEY  = var.sabnzbd_api_key
    HOMEPAGE_VAR_EMBY_KEY     = var.emby_api_key
    HOMEPAGE_VAR_QBIT_USER    = var.qbittorrent_username
    HOMEPAGE_VAR_QBIT_PASS    = var.qbittorrent_password
  }
}
```

- [ ] **Step 3: Validate**

Run: `cd terraform && make validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add terraform/homepage.tf
git commit -m "feat: add Homepage ConfigMap with dynamic service groups and Secret"
```

---

### Task 4: Deployment and Service

**Files:**
- Modify: `terraform/homepage.tf` (append Deployment + Service + Output)

- [ ] **Step 1: Add Deployment, Service, and Output**

Append to `homepage.tf`:

```hcl
# -----------------------------------------------------------------------------
# Deployment
# -----------------------------------------------------------------------------

resource "kubernetes_deployment" "homepage" {
  count = var.homepage_enabled ? 1 : 0

  depends_on = [
    kubernetes_config_map.homepage_config,
    kubernetes_secret.homepage_secrets,
  ]

  metadata {
    name      = "homepage"
    namespace = kubernetes_namespace.homepage[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "homepage"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "homepage"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "homepage"
        })
      }

      spec {
        service_account_name = kubernetes_service_account.homepage[0].metadata[0].name

        container {
          name  = "homepage"
          image = "${var.homepage_image}:${var.homepage_image_tag}"

          port {
            container_port = 3000
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.homepage_secrets[0].metadata[0].name
            }
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config"
          }

          resources {
            requests = {
              memory = var.homepage_memory_request
              cpu    = var.homepage_cpu_request
            }
            limits = {
              memory = var.homepage_memory_limit
              cpu    = var.homepage_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/api/healthcheck"
              port = 3000
            }
            initial_delay_seconds = 15
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/api/healthcheck"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "homepage-config"
          config_map {
            name = kubernetes_config_map.homepage_config[0].metadata[0].name
          }
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Service
# -----------------------------------------------------------------------------

resource "kubernetes_service" "homepage" {
  count = var.homepage_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.homepage
  ]

  metadata {
    name      = "homepage-service"
    namespace = kubernetes_namespace.homepage[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "homepage"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "homepage"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 3000
    }
  }
}

# -----------------------------------------------------------------------------
# Output
# -----------------------------------------------------------------------------

output "homepage_info" {
  description = "Homepage dashboard information"
  value = var.homepage_enabled ? {
    namespace    = kubernetes_namespace.homepage[0].metadata[0].name
    service_name = kubernetes_service.homepage[0].metadata[0].name

    access = {
      web_ui = "https://homepage.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.homepage[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.homepage[0].metadata[0].name} -l app=homepage -f"
    }
  } : null

  sensitive = true
}
```

- [ ] **Step 2: Validate**

Run: `cd terraform && make validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add terraform/homepage.tf
git commit -m "feat: add Homepage Deployment, Service, and output"
```

---

### Task 5: IngressRoute and DNS Record

**Files:**
- Modify: `terraform/ingress.tf` (add IngressRoute)
- Modify: `terraform/dns.tf` (add DNS entry to `local.dns_records`)

- [ ] **Step 1: Add IngressRoute to `ingress.tf`**

Add the following at an appropriate location in `ingress.tf` (near other application IngressRoutes):

```hcl
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
            name      = "rate-limit"
            namespace = kubernetes_namespace.traefik.metadata[0].name
          },
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}
```

- [ ] **Step 2: Add DNS entry to `dns.tf`**

In the `local.dns_records` merge block in `dns.tf`, add this line alongside the other application entries:

```hcl
var.homepage_enabled ? { homepage = "homepage" } : {},
```

- [ ] **Step 3: Validate**

Run: `cd terraform && make validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add terraform/ingress.tf terraform/dns.tf
git commit -m "feat: add Homepage IngressRoute and DNS record"
```

---

### Task 6: Makefile Targets and tfvars Example

**Files:**
- Modify: `terraform/Makefile` (.PHONY, plan-homepage, apply-homepage, apply-applications)
- Modify: `terraform/terraform.tfvars.example` (add Homepage section)

- [ ] **Step 1: Add to `.PHONY` declaration in Makefile**

Add `plan-homepage apply-homepage` to the `.PHONY` line. Find the line containing `plan-comfyui apply-comfyui` and add after it:

```makefile
	plan-homepage apply-homepage \
```

- [ ] **Step 2: Add `plan-homepage` and `apply-homepage` targets**

Add near the other individual service targets:

```makefile
plan-homepage: check-vars check-init ## Plan Homepage dashboard
	@echo "Planning Homepage..."
	terraform plan \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage

apply-homepage: check-vars check-init ## Deploy Homepage dashboard
	@echo "Deploying Homepage..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage
```

- [ ] **Step 3: Add Homepage resources to `apply-applications` and `plan-applications` targets**

Add these `-target` lines to both the `plan-applications` and `apply-applications` targets:

```
		-target=kubernetes_namespace.homepage \
		-target=kubernetes_service_account.homepage \
		-target=kubernetes_cluster_role.homepage \
		-target=kubernetes_cluster_role_binding.homepage \
		-target=kubernetes_config_map.homepage_config \
		-target=kubernetes_secret.homepage_secrets \
		-target=kubernetes_deployment.homepage \
		-target=kubernetes_service.homepage
```

- [ ] **Step 4: Add Homepage section to `terraform.tfvars.example`**

Add a new section:

```hcl
# Homepage Dashboard (Application Portal)
#homepage_enabled        = true     # Set to false to disable Homepage
#homepage_image_tag      = "latest"
#homepage_memory_request = "128Mi"
#homepage_memory_limit   = "256Mi"
#homepage_cpu_request    = "50m"
#homepage_cpu_limit      = "200m"

# Widget API Keys (optional — widgets degrade gracefully without them)
#sonarr_api_key       = ""
#radarr_api_key       = ""
#prowlarr_api_key     = ""
#bazarr_api_key       = ""
#jackett_api_key      = ""
#huntarr_api_key      = ""
#sabnzbd_api_key      = ""
#qbittorrent_username = ""
#qbittorrent_password = ""
#emby_api_key         = ""
```

- [ ] **Step 5: Validate**

Run: `cd terraform && make validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add terraform/Makefile terraform/terraform.tfvars.example
git commit -m "feat: add Homepage Makefile targets and tfvars example"
```

---

### Task 7: Deploy and Verify

**Files:** None (operational task)

**Prerequisites:** User must set `homepage_enabled = true` in `terraform.tfvars` and optionally add API keys.

- [ ] **Step 1: Enable Homepage in tfvars**

Ask user to add `homepage_enabled = true` to their `terraform.tfvars` (and any API keys they want).

- [ ] **Step 2: Plan**

Run: `cd terraform && make plan-homepage`
Expected: Plan shows creation of ~8 resources (namespace, service account, cluster role, cluster role binding, configmap, secret, deployment, service).

- [ ] **Step 3: Apply Homepage**

Run: `cd terraform && make apply-homepage`
Expected: `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.`

- [ ] **Step 4: Apply Ingress**

Run: `cd terraform && make apply-ingress`
Expected: IngressRoute for homepage created.

- [ ] **Step 5: Apply DNS**

Run: `cd terraform && make apply-azure-dns`
Expected: DNS A record for homepage subdomain created.

- [ ] **Step 6: Verify pod is healthy**

Run: `kubectl get pods -n homepage`
Expected: `homepage-xxxx   1/1   Running   0   <age>`

- [ ] **Step 7: Verify access**

Run: `kubectl logs -n homepage -l app=homepage --tail=20`
Expected: Logs show Homepage started and serving on port 3000.

Open `https://homepage.{domain}` in browser — should show the dashboard with all enabled service groups.
