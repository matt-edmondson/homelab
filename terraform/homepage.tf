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
