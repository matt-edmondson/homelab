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

variable "grafana_username" {
  description = "Grafana username for Homepage widget"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "grafana_password" {
  description = "Grafana password for Homepage widget"
  type        = string
  default     = ""
  sensitive   = true
}

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

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["traefik.io", "traefik.containo.us"]
    resources  = ["ingressroutes", "middlewares"]
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
          url  = "http://sonarr-service.sonarr.svc.cluster.local:80"
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
          url  = "http://radarr-service.radarr.svc.cluster.local:80"
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
          url  = "http://bazarr-service.bazarr.svc.cluster.local:80"
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
          url  = "http://prowlarr-service.prowlarr.svc.cluster.local:80"
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
          url      = "http://qbittorrent-service.qbittorrent.svc.cluster.local:80"
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
          url  = "http://sabnzbd-service.sabnzbd.svc.cluster.local:80"
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
          url  = "http://emby-service.emby.svc.cluster.local:80"
          key  = "{{HOMEPAGE_VAR_EMBY_KEY}}"
        }
      }
    }] : [],
  )

  homepage_monitoring_services = concat(
    var.monitoring_enabled ? [{
      "Grafana" = {
        href        = "https://grafana.${var.traefik_domain}"
        icon        = "grafana"
        description = "Dashboards"
        widget = {
          type     = "grafana"
          url      = "http://prometheus-stack-grafana.monitoring.svc.cluster.local:80"
          username = "{{HOMEPAGE_VAR_GRAFANA_USER}}"
          password = "{{HOMEPAGE_VAR_GRAFANA_PASS}}"
        }
      }
    }] : [],
    var.monitoring_enabled ? [{
      "Prometheus" = {
        href        = "https://prometheus.${var.traefik_domain}"
        icon        = "prometheus"
        description = "Metrics"
        widget = {
          type = "prometheus"
          url  = "http://prometheus-stack-kube-prom-prometheus.monitoring.svc.cluster.local:9090"
        }
      }
    }] : [],
    var.monitoring_enabled ? [{
      "AlertManager" = {
        href        = "https://alertmanager.${var.traefik_domain}"
        icon        = "alertmanager"
        description = "Alerts"
      }
    }] : [],
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
    var.claudecluster_enabled ? [{
      "ClaudeCluster" = {
        href        = "https://claude.${var.traefik_domain}"
        icon        = "claude"
        description = "Claude Code Sandboxes"
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
    var.devtron_enabled ? [{
      "Devtron" = {
        href        = "https://devtron.${var.traefik_domain}"
        icon        = "devtron"
        description = "K8s Dashboard"
      }
    }] : [],
  )

}

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
    "settings.yaml" = <<-EOT
title: Homelab
theme: dark
color: slate
headerStyle: clean
statusStyle: dot
hideErrors: true
layout:
  Media Management:
    style: row
    columns: 4
  Downloads:
    style: row
    columns: 2
  Media Streaming:
    style: row
    columns: 1
  Monitoring:
    style: row
    columns: 3
  AI / ML:
    style: row
    columns: 4
  Infrastructure:
    style: row
    columns: 3
EOT

    "services.yaml" = join("\n", compact([
      length(local.homepage_media_services) > 0 ? join("\n", concat(
        ["- Media Management:"],
        flatten([for s in local.homepage_media_services : concat(
          ["    - ${keys(s)[0]}:"],
          [for k, v in values(s)[0] : "        ${k}: ${v}" if k != "widget"],
          lookup(values(s)[0], "widget", null) != null ? concat(
            ["        widget:"],
            [for wk, wv in values(s)[0]["widget"] : "          ${wk}: ${wv}"]
          ) : []
        )])
      )) : "",
      length(local.homepage_download_services) > 0 ? join("\n", concat(
        ["- Downloads:"],
        flatten([for s in local.homepage_download_services : concat(
          ["    - ${keys(s)[0]}:"],
          [for k, v in values(s)[0] : "        ${k}: ${v}" if k != "widget"],
          lookup(values(s)[0], "widget", null) != null ? concat(
            ["        widget:"],
            [for wk, wv in values(s)[0]["widget"] : "          ${wk}: ${wv}"]
          ) : []
        )])
      )) : "",
      length(local.homepage_streaming_services) > 0 ? join("\n", concat(
        ["- Media Streaming:"],
        flatten([for s in local.homepage_streaming_services : concat(
          ["    - ${keys(s)[0]}:"],
          [for k, v in values(s)[0] : "        ${k}: ${v}" if k != "widget"],
          lookup(values(s)[0], "widget", null) != null ? concat(
            ["        widget:"],
            [for wk, wv in values(s)[0]["widget"] : "          ${wk}: ${wv}"]
          ) : []
        )])
      )) : "",
      length(local.homepage_monitoring_services) > 0 ? join("\n", concat(
        ["- Monitoring:"],
        flatten([for s in local.homepage_monitoring_services : concat(
          ["    - ${keys(s)[0]}:"],
          [for k, v in values(s)[0] : "        ${k}: ${v}" if k != "widget"],
          lookup(values(s)[0], "widget", null) != null ? concat(
            ["        widget:"],
            [for wk, wv in values(s)[0]["widget"] : "          ${wk}: ${wv}"]
          ) : []
        )])
      )) : "",
      length(local.homepage_ai_services) > 0 ? join("\n", concat(
        ["- AI / ML:"],
        flatten([for s in local.homepage_ai_services : concat(
          ["    - ${keys(s)[0]}:"],
          [for k, v in values(s)[0] : "        ${k}: ${v}" if k != "widget"],
          lookup(values(s)[0], "widget", null) != null ? concat(
            ["        widget:"],
            [for wk, wv in values(s)[0]["widget"] : "          ${wk}: ${wv}"]
          ) : []
        )])
      )) : "",
      length(local.homepage_infra_services) > 0 ? join("\n", concat(
        ["- Infrastructure:"],
        flatten([for s in local.homepage_infra_services : concat(
          ["    - ${keys(s)[0]}:"],
          [for k, v in values(s)[0] : "        ${k}: ${v}" if k != "widget"],
          lookup(values(s)[0], "widget", null) != null ? concat(
            ["        widget:"],
            [for wk, wv in values(s)[0]["widget"] : "          ${wk}: ${wv}"]
          ) : []
        )])
      )) : "",
    ]))

    "widgets.yaml" = <<-EOT
- kubernetes:
    cluster:
      show: true
      cpu: true
      memory: true
      showLabel: true
      label: "cluster"
    nodes:
      show: true
      cpu: true
      memory: true
      showLabel: true
- search:
    provider: duckduckgo
    target: _blank
EOT

    "kubernetes.yaml" = <<-EOT
mode: cluster
EOT

    "bookmarks.yaml" = ""
    "docker.yaml"    = ""
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
    HOMEPAGE_VAR_GRAFANA_USER = var.grafana_username
    HOMEPAGE_VAR_GRAFANA_PASS = var.grafana_password
  }
}

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

          env {
            name = "MY_POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          env {
            name  = "HOMEPAGE_ALLOWED_HOSTS"
            value = "homepage.${var.traefik_domain},homepage-service.homepage.svc.cluster.local,$(MY_POD_IP):3000"
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.homepage_secrets[0].metadata[0].name
            }
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/settings.yaml"
            sub_path   = "settings.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/services.yaml"
            sub_path   = "services.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/widgets.yaml"
            sub_path   = "widgets.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/kubernetes.yaml"
            sub_path   = "kubernetes.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/bookmarks.yaml"
            sub_path   = "bookmarks.yaml"
          }

          volume_mount {
            name       = "homepage-config"
            mount_path = "/app/config/docker.yaml"
            sub_path   = "docker.yaml"
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
