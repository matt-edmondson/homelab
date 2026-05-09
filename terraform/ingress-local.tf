# =============================================================================
# Traefik Local-Only Bypass IngressRoutes
# =============================================================================
# For every public service that gets an Azure DNS A record under ktsu.dev,
# this file creates a parallel <svc>.local.ktsu.dev IngressRoute that:
#   - Points to the same backend Service
#   - Has NO middleware (no OAuth, no CrowdSec, no rate-limit) — full bypass
#   - Serves a Let's Encrypt cert for local.ktsu.dev + *.local.ktsu.dev,
#     issued via the same Azure DNS-01 challenge configured in traefik.tf
#
# DNS A records for these hostnames live in dns.tf
# (azurerm_dns_a_record.local_services, target var.traefik_local_ip).
#
# IMPORTANT: This file uses Traefik CRDs installed by the Traefik Helm chart
# (traefik.tf). Apply order is unchanged: traefik first, then ingress.
# =============================================================================

locals {
  # One entry per <svc>.local.ktsu.dev hostname. Schema:
  #   host_prefix        - leftmost label (e.g. "grafana")
  #   service_name       - backend Service name (or "api@internal" for Traefik)
  #   service_namespace  - optional; omitted for api@internal
  #   service_port       - optional; defaults to 80
  #   service_kind       - optional; defaults to "Service"; use "TraefikService"
  #                        for api@internal
  local_routes = merge(
    {
      traefik = {
        host_prefix  = "traefik"
        service_name = "api@internal"
        service_kind = "TraefikService"
      }
      longhorn = {
        host_prefix       = "longhorn"
        service_name      = kubernetes_service.longhorn_frontend_lb.metadata[0].name
        service_namespace = kubernetes_namespace.longhorn_system.metadata[0].name
        service_port      = 80
      }
    },
    var.monitoring_enabled ? {
      grafana = {
        host_prefix       = "grafana"
        service_name      = "prometheus-stack-grafana"
        service_namespace = kubernetes_namespace.monitoring[0].metadata[0].name
        service_port      = 80
      }
      prometheus = {
        host_prefix       = "prometheus"
        service_name      = "prometheus-stack-kube-prom-prometheus"
        service_namespace = kubernetes_namespace.monitoring[0].metadata[0].name
        service_port      = 9090
      }
      alertmanager = {
        host_prefix       = "alertmanager"
        service_name      = "prometheus-stack-kube-prom-alertmanager"
        service_namespace = kubernetes_namespace.monitoring[0].metadata[0].name
        service_port      = 9093
      }
    } : {},
    var.kubernetes_dashboard_enabled ? {
      dashboard = {
        host_prefix       = "dashboard"
        service_name      = "headlamp"
        service_namespace = kubernetes_namespace.headlamp[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.devtron_enabled ? {
      devtron = {
        host_prefix       = "devtron"
        service_name      = "devtron-service"
        service_namespace = kubernetes_namespace.devtron[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.baget_enabled ? {
      packages = {
        host_prefix       = "packages"
        service_name      = kubernetes_service.baget[0].metadata[0].name
        service_namespace = kubernetes_namespace.baget[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.n8n_enabled ? {
      n8n = {
        host_prefix       = "n8n"
        service_name      = kubernetes_service.n8n[0].metadata[0].name
        service_namespace = kubernetes_namespace.n8n[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.prowlarr_enabled ? {
      prowlarr = {
        host_prefix       = "prowlarr"
        service_name      = kubernetes_service.prowlarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.prowlarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.sonarr_enabled ? {
      sonarr = {
        host_prefix       = "sonarr"
        service_name      = kubernetes_service.sonarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.sonarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.radarr_enabled ? {
      radarr = {
        host_prefix       = "radarr"
        service_name      = kubernetes_service.radarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.radarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.qbittorrent_enabled ? {
      qbit = {
        host_prefix       = "qbit"
        service_name      = kubernetes_service.qbittorrent[0].metadata[0].name
        service_namespace = kubernetes_namespace.qbittorrent[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.emby_enabled ? {
      emby = {
        host_prefix       = "emby"
        service_name      = kubernetes_service.emby[0].metadata[0].name
        service_namespace = kubernetes_namespace.emby[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.bazarr_enabled ? {
      bazarr = {
        host_prefix       = "bazarr"
        service_name      = kubernetes_service.bazarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.bazarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.jackett_enabled ? {
      jackett = {
        host_prefix       = "jackett"
        service_name      = kubernetes_service.jackett[0].metadata[0].name
        service_namespace = kubernetes_namespace.jackett[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.cleanuparr_enabled ? {
      cleanuparr = {
        host_prefix       = "cleanuparr"
        service_name      = kubernetes_service.cleanuparr[0].metadata[0].name
        service_namespace = kubernetes_namespace.cleanuparr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.sabnzbd_enabled ? {
      sabnzbd = {
        host_prefix       = "sabnzbd"
        service_name      = kubernetes_service.sabnzbd[0].metadata[0].name
        service_namespace = kubernetes_namespace.sabnzbd[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.notifiarr_enabled ? {
      notifiarr = {
        host_prefix       = "notifiarr"
        service_name      = kubernetes_service.notifiarr[0].metadata[0].name
        service_namespace = kubernetes_namespace.notifiarr[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.ollama_enabled ? {
      ollama = {
        host_prefix       = "ollama"
        service_name      = kubernetes_service.ollama[0].metadata[0].name
        service_namespace = kubernetes_namespace.ollama[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.qdrant_enabled ? {
      qdrant = {
        host_prefix       = "qdrant"
        service_name      = kubernetes_service.qdrant[0].metadata[0].name
        service_namespace = kubernetes_namespace.qdrant[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.chromadb_enabled ? {
      chromadb = {
        host_prefix       = "chromadb"
        service_name      = kubernetes_service.chromadb[0].metadata[0].name
        service_namespace = kubernetes_namespace.chromadb[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.comfyui_enabled ? {
      comfyui = {
        host_prefix       = "comfyui"
        service_name      = kubernetes_service.comfyui[0].metadata[0].name
        service_namespace = kubernetes_namespace.comfyui[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.homepage_enabled ? {
      homepage = {
        host_prefix       = "homepage"
        service_name      = kubernetes_service.homepage[0].metadata[0].name
        service_namespace = kubernetes_namespace.homepage[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.claudecluster_enabled ? {
      claude = {
        host_prefix       = "claude"
        service_name      = kubernetes_service.claudecluster_backend[0].metadata[0].name
        service_namespace = kubernetes_namespace.claude_sandbox[0].metadata[0].name
        service_port      = 80
      }
    } : {},
    var.poker_enabled ? {
      poker = {
        host_prefix       = "poker"
        service_name      = kubernetes_service.poker[0].metadata[0].name
        service_namespace = kubernetes_namespace.poker[0].metadata[0].name
        service_port      = 3000
      }
    } : {},
    {
      for k, sub in local.cams_web_toys_subdomains :
      "cwt_${k}" => {
        host_prefix       = sub
        service_name      = kubernetes_service.cams_web_toys[0].metadata[0].name
        service_namespace = kubernetes_namespace.cams_web_toys[0].metadata[0].name
        service_port      = 3000
      }
    },
  )
}

resource "kubernetes_manifest" "ingressroute_local" {
  for_each = local.local_routes

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "local-${each.key}"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`${each.value.host_prefix}.local.${var.traefik_domain}`)"
        kind  = "Rule"
        # NOTE: deliberately no `middlewares` field — full bypass of OAuth,
        # CrowdSec, rate-limit, and basic-auth. That is the entire point of
        # this file.
        services = [merge(
          {
            name = each.value.service_name
            port = try(each.value.service_port, 80)
          },
          try(each.value.service_kind, null) != null ? { kind = each.value.service_kind } : {},
          try(each.value.service_namespace, null) != null ? { namespace = each.value.service_namespace } : {},
        )]
      }]
      tls = {
        certResolver = "letsencrypt"
        domains = [{
          main = "local.${var.traefik_domain}"
          sans = ["*.local.${var.traefik_domain}"]
        }]
      }
    }
  }

  depends_on = [helm_release.traefik]
}
