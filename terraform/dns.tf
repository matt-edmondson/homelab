# =============================================================================
# Azure DNS Records
# =============================================================================
# Creates individual A records in Azure DNS for each service subdomain,
# pointing to the external IP that port-forwards to the homelab router.
# =============================================================================

# Variables
variable "azure_dns_zone_name" {
  description = "Azure DNS zone name (e.g. example.com)"
  type        = string
}

variable "external_ip" {
  description = "External/public IP address that forwards to the homelab router (ports 80/443 -> Traefik)"
  type        = string
}

variable "traefik_local_ip" {
  description = "LAN IP of the Traefik LoadBalancer service, used as the A-record target for *.local.ktsu.dev hostnames. Must match the loadBalancerIP set in traefik.tf."
  type        = string
  default     = "192.168.0.238"
}

variable "dns_ttl" {
  description = "TTL in seconds for DNS A records"
  type        = number
  default     = 300
}

# Azure provider configuration (uses same credentials as DNS challenge)
provider "azurerm" {
  features {}

  resource_provider_registrations = "none"

  client_id       = var.azure_dns_client_id
  client_secret   = var.azure_dns_client_secret
  tenant_id       = var.azure_dns_tenant_id
  subscription_id = var.azure_dns_subscription_id
}

# Look up the existing Azure DNS zone
data "azurerm_dns_zone" "main" {
  name                = var.azure_dns_zone_name
  resource_group_name = var.azure_dns_resource_group
}

locals {
  # All service subdomains that need A records (filtered by enabled state)
  dns_records = merge(
    # Core infrastructure (always on)
    {
      traefik  = "traefik"
      longhorn = "longhorn"
    },
    # OAuth
    var.oauth_enabled ? { auth = "auth" } : {},
    # Monitoring
    var.monitoring_enabled ? {
      grafana      = "grafana"
      prometheus   = "prometheus"
      alertmanager = "alertmanager"
    } : {},
    # Kubernetes Dashboard
    var.kubernetes_dashboard_enabled ? { dashboard = "dashboard" } : {},
    # Devtron
    var.devtron_enabled ? { devtron = "devtron" } : {},
    # Applications
    var.baget_enabled ? { packages = "packages" } : {},
    var.n8n_enabled ? { n8n = "n8n" } : {},
    # Media Stack
    var.prowlarr_enabled ? { prowlarr = "prowlarr" } : {},
    var.sonarr_enabled ? { sonarr = "sonarr" } : {},
    var.radarr_enabled ? { radarr = "radarr" } : {},
    var.qbittorrent_enabled ? { qbit = "qbit" } : {},
    var.emby_enabled ? { emby = "emby" } : {},
    var.bazarr_enabled ? { bazarr = "bazarr" } : {},
    var.jackett_enabled ? { jackett = "jackett" } : {},
    var.cleanuparr_enabled ? { cleanuparr = "cleanuparr" } : {},
    var.sabnzbd_enabled ? { sabnzbd = "sabnzbd" } : {},
    var.notifiarr_enabled ? { notifiarr = "notifiarr" } : {},
    # AI/ML Stack
    var.ollama_enabled ? { ollama = "ollama" } : {},
    var.qdrant_enabled ? { qdrant = "qdrant" } : {},
    var.chromadb_enabled ? { chromadb = "chromadb" } : {},
    var.comfyui_enabled ? { comfyui = "comfyui" } : {},
    var.homepage_enabled ? { homepage = "homepage" } : {},
    # ClaudeCluster
    var.claudecluster_enabled ? { claude = "claude" } : {},
    # Planning Poker
    var.poker_enabled ? { poker = "poker" } : {},
    # Cams Web Toys — one entry per enabled toy, keys prefixed `cwt_` to avoid
    # collisions with sibling modules in this global merge.
    local.cams_web_toys_dns_records,
  )
}

# Create A records for each service subdomain
resource "azurerm_dns_a_record" "services" {
  for_each = local.dns_records

  name                = each.value
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = var.azure_dns_resource_group
  ttl                 = var.dns_ttl
  records             = [var.external_ip]

  tags = var.common_labels
}

# Local-only A records: <svc>.local.ktsu.dev -> Traefik LAN VIP.
# Iterates the same dns_records map as the public records, so every public
# service automatically gets a parallel local hostname. Bypass IngressRoutes
# (no OAuth/CrowdSec middleware) live in ingress-local.tf.
resource "azurerm_dns_a_record" "local_services" {
  for_each = local.dns_records

  name                = "${each.value}.local"
  zone_name           = data.azurerm_dns_zone.main.name
  resource_group_name = var.azure_dns_resource_group
  ttl                 = var.dns_ttl
  records             = [var.traefik_local_ip]

  tags = var.common_labels
}

# --- Static Sites DNS ---

# Create Azure DNS zone for each static site domain
resource "azurerm_dns_zone" "static_sites" {
  for_each = { for site in var.static_sites : site.domain => site }

  name                = each.key
  resource_group_name = var.azure_dns_resource_group

  tags = var.common_labels
}

# Create A record (@) for each static site domain
resource "azurerm_dns_a_record" "static_sites" {
  for_each = { for site in var.static_sites : site.domain => site }

  name                = "@"
  zone_name           = azurerm_dns_zone.static_sites[each.key].name
  resource_group_name = var.azure_dns_resource_group
  ttl                 = var.dns_ttl
  records             = [var.external_ip]

  tags = var.common_labels
}

# Outputs
output "dns_info" {
  description = "Azure DNS record information"
  value = {
    zone    = data.azurerm_dns_zone.main.name
    records = { for k, v in azurerm_dns_a_record.services : k => "${v.name}.${data.azurerm_dns_zone.main.name}" }
    local_records = { for k, v in azurerm_dns_a_record.local_services : k => "${v.name}.${data.azurerm_dns_zone.main.name}" }
    ip      = var.external_ip
    ttl     = var.dns_ttl

    static_sites = { for k, v in azurerm_dns_zone.static_sites : k => {
      nameservers = v.name_servers
      a_record    = var.external_ip
    } }

    commands = {
      verify = "nslookup grafana.${var.azure_dns_zone_name}"
    }
  }
}
