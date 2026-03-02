# Wave 4: Media Stack Extensions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy 7 media stack extension services (Bazarr, Jackett, Huntarr, Cleanuparr, SABnzbd, Notifiarr, Flaresolverr) that support the core media stack deployed in Wave 3.

**Architecture:** Each service follows the established one-file-per-service Terraform pattern: namespace, Longhorn PVC for config, optional NFS PV/PVC for media or downloads, Deployment with linuxserver.io images, ClusterIP Service. Six services get Traefik IngressRoutes with OAuth + CrowdSec + rate-limit middleware. Flaresolverr is internal-only (no IngressRoute, no DNS). All exposed services get DNS A records in Azure DNS.

**Tech Stack:** Terraform (Kubernetes provider), Longhorn StorageClass, NFS CSI driver, Traefik IngressRoute CRDs, Azure DNS

---

## Task 1: Create `terraform/bazarr.tf` — Subtitle Management

**Files:**
- Create: `terraform/bazarr.tf`

**Step 1: Write the Bazarr Terraform file**

```hcl
# =============================================================================
# Bazarr — Subtitle Management
# =============================================================================
# Integrates with Sonarr and Radarr to download and manage subtitles.
# Longhorn PVC for config/DB, NFS PVC for media (writes .srt files alongside
# video files on the NAS).
# =============================================================================

# Variables
variable "bazarr_storage_size" {
  description = "Storage size for Bazarr config/database"
  type        = string
  default     = "1Gi"
}

variable "bazarr_memory_request" {
  description = "Memory request for Bazarr container"
  type        = string
  default     = "128Mi"
}

variable "bazarr_memory_limit" {
  description = "Memory limit for Bazarr container"
  type        = string
  default     = "256Mi"
}

variable "bazarr_cpu_request" {
  description = "CPU request for Bazarr container"
  type        = string
  default     = "50m"
}

variable "bazarr_cpu_limit" {
  description = "CPU limit for Bazarr container"
  type        = string
  default     = "500m"
}

variable "bazarr_image_tag" {
  description = "Bazarr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "bazarr" {
  metadata {
    name = "bazarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "bazarr"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "bazarr_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "bazarr-config"
    namespace = kubernetes_namespace.bazarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.bazarr_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Media (static PV, read-write for subtitle files)
resource "kubernetes_persistent_volume" "bazarr_media" {
  metadata {
    name   = "bazarr-media-pv"
    labels = var.common_labels
  }

  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-media"

    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = var.nfs_media_share
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_media]
}

resource "kubernetes_persistent_volume_claim" "bazarr_media" {
  metadata {
    name      = "bazarr-media"
    namespace = kubernetes_namespace.bazarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-media"
    volume_name        = kubernetes_persistent_volume.bazarr_media.metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "bazarr" {
  depends_on = [
    kubernetes_persistent_volume_claim.bazarr_config,
    kubernetes_persistent_volume_claim.bazarr_media,
    helm_release.longhorn
  ]

  metadata {
    name      = "bazarr"
    namespace = kubernetes_namespace.bazarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "bazarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "bazarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "bazarr"
        })
      }

      spec {
        container {
          name  = "bazarr"
          image = "linuxserver/bazarr:${var.bazarr_image_tag}"

          port {
            container_port = 6767
          }

          env {
            name  = "PUID"
            value = "1000"
          }

          env {
            name  = "PGID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "bazarr-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "media"
            mount_path = "/media"
          }

          resources {
            requests = {
              memory = var.bazarr_memory_request
              cpu    = var.bazarr_cpu_request
            }
            limits = {
              memory = var.bazarr_memory_limit
              cpu    = var.bazarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/ping"
              port = 6767
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 6767
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "bazarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.bazarr_config.metadata[0].name
          }
        }

        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.bazarr_media.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "bazarr" {
  depends_on = [
    kubernetes_deployment.bazarr
  ]

  metadata {
    name      = "bazarr-service"
    namespace = kubernetes_namespace.bazarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "bazarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "bazarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 6767
    }
  }
}

# Outputs
output "bazarr_info" {
  description = "Bazarr subtitle management information"
  value = {
    namespace    = kubernetes_namespace.bazarr.metadata[0].name
    service_name = kubernetes_service.bazarr.metadata[0].name
    storage_size = var.bazarr_storage_size

    access = {
      web_ui = "https://bazarr.${var.traefik_domain}"
    }

    nfs_mounts = {
      media = "${var.nfs_server}:${var.nfs_media_share}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.bazarr.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.bazarr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.bazarr.metadata[0].name} -l app=bazarr -f"
    }
  }

  sensitive = true
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt bazarr.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/bazarr.tf
git commit -m "feat: add Bazarr subtitle management service"
```

---

## Task 2: Create `terraform/jackett.tf` — Indexer Support

**Files:**
- Create: `terraform/jackett.tf`

**Step 1: Write the Jackett Terraform file**

```hcl
# =============================================================================
# Jackett — Additional Indexer Support
# =============================================================================
# Provides additional indexer/tracker support for Prowlarr.
# Longhorn PVC for config, no NFS mounts needed.
# =============================================================================

# Variables
variable "jackett_storage_size" {
  description = "Storage size for Jackett config"
  type        = string
  default     = "1Gi"
}

variable "jackett_memory_request" {
  description = "Memory request for Jackett container"
  type        = string
  default     = "128Mi"
}

variable "jackett_memory_limit" {
  description = "Memory limit for Jackett container"
  type        = string
  default     = "256Mi"
}

variable "jackett_cpu_request" {
  description = "CPU request for Jackett container"
  type        = string
  default     = "50m"
}

variable "jackett_cpu_limit" {
  description = "CPU limit for Jackett container"
  type        = string
  default     = "500m"
}

variable "jackett_image_tag" {
  description = "Jackett container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "jackett" {
  metadata {
    name = "jackett"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "jackett"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "jackett_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "jackett-config"
    namespace = kubernetes_namespace.jackett.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.jackett_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "jackett" {
  depends_on = [
    kubernetes_persistent_volume_claim.jackett_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "jackett"
    namespace = kubernetes_namespace.jackett.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "jackett"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "jackett"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "jackett"
        })
      }

      spec {
        container {
          name  = "jackett"
          image = "linuxserver/jackett:${var.jackett_image_tag}"

          port {
            container_port = 9117
          }

          env {
            name  = "PUID"
            value = "1000"
          }

          env {
            name  = "PGID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "jackett-config"
            mount_path = "/config"
          }

          resources {
            requests = {
              memory = var.jackett_memory_request
              cpu    = var.jackett_cpu_request
            }
            limits = {
              memory = var.jackett_memory_limit
              cpu    = var.jackett_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/UI/Dashboard"
              port = 9117
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/UI/Dashboard"
              port = 9117
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "jackett-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.jackett_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "jackett" {
  depends_on = [
    kubernetes_deployment.jackett
  ]

  metadata {
    name      = "jackett-service"
    namespace = kubernetes_namespace.jackett.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "jackett"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "jackett"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 9117
    }
  }
}

# Outputs
output "jackett_info" {
  description = "Jackett indexer information"
  value = {
    namespace    = kubernetes_namespace.jackett.metadata[0].name
    service_name = kubernetes_service.jackett.metadata[0].name
    storage_size = var.jackett_storage_size

    access = {
      web_ui = "https://jackett.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.jackett.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.jackett.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.jackett.metadata[0].name} -l app=jackett -f"
    }
  }

  sensitive = true
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt jackett.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/jackett.tf
git commit -m "feat: add Jackett indexer support service"
```

---

## Task 3: Create `terraform/huntarr.tf` — Missing Media Hunter

**Files:**
- Create: `terraform/huntarr.tf`

**Step 1: Write the Huntarr Terraform file**

```hcl
# =============================================================================
# Huntarr — Missing Media Hunter
# =============================================================================
# Monitors Sonarr and Radarr for missing media and triggers searches.
# Longhorn PVC for config, no NFS mounts needed.
# =============================================================================

# Variables
variable "huntarr_storage_size" {
  description = "Storage size for Huntarr config"
  type        = string
  default     = "512Mi"
}

variable "huntarr_memory_request" {
  description = "Memory request for Huntarr container"
  type        = string
  default     = "64Mi"
}

variable "huntarr_memory_limit" {
  description = "Memory limit for Huntarr container"
  type        = string
  default     = "128Mi"
}

variable "huntarr_cpu_request" {
  description = "CPU request for Huntarr container"
  type        = string
  default     = "25m"
}

variable "huntarr_cpu_limit" {
  description = "CPU limit for Huntarr container"
  type        = string
  default     = "200m"
}

variable "huntarr_image_tag" {
  description = "Huntarr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "huntarr" {
  metadata {
    name = "huntarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "huntarr"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "huntarr_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "huntarr-config"
    namespace = kubernetes_namespace.huntarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.huntarr_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "huntarr" {
  depends_on = [
    kubernetes_persistent_volume_claim.huntarr_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "huntarr"
    namespace = kubernetes_namespace.huntarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "huntarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "huntarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "huntarr"
        })
      }

      spec {
        container {
          name  = "huntarr"
          image = "huntarr/huntarr:${var.huntarr_image_tag}"

          port {
            container_port = 9705
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "huntarr-config"
            mount_path = "/config"
          }

          resources {
            requests = {
              memory = var.huntarr_memory_request
              cpu    = var.huntarr_cpu_request
            }
            limits = {
              memory = var.huntarr_memory_limit
              cpu    = var.huntarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 9705
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 9705
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "huntarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.huntarr_config.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "huntarr" {
  depends_on = [
    kubernetes_deployment.huntarr
  ]

  metadata {
    name      = "huntarr-service"
    namespace = kubernetes_namespace.huntarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "huntarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "huntarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 9705
    }
  }
}

# Outputs
output "huntarr_info" {
  description = "Huntarr missing media hunter information"
  value = {
    namespace    = kubernetes_namespace.huntarr.metadata[0].name
    service_name = kubernetes_service.huntarr.metadata[0].name
    storage_size = var.huntarr_storage_size

    access = {
      web_ui = "https://huntarr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.huntarr.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.huntarr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.huntarr.metadata[0].name} -l app=huntarr -f"
    }
  }

  sensitive = true
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt huntarr.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/huntarr.tf
git commit -m "feat: add Huntarr missing media hunter service"
```

---

## Task 4: Create `terraform/cleanuparr.tf` — Library Cleanup

**Files:**
- Create: `terraform/cleanuparr.tf`

**Step 1: Write the Cleanuparr Terraform file**

Cleanuparr is stateless — no PVC needed. It connects to Sonarr/Radarr APIs and is configured via environment variables.

```hcl
# =============================================================================
# Cleanuparr — Library Cleanup Automation
# =============================================================================
# Automates library cleanup via Sonarr/Radarr APIs.
# Stateless — no persistent storage needed.
# =============================================================================

# Variables
variable "cleanuparr_memory_request" {
  description = "Memory request for Cleanuparr container"
  type        = string
  default     = "64Mi"
}

variable "cleanuparr_memory_limit" {
  description = "Memory limit for Cleanuparr container"
  type        = string
  default     = "128Mi"
}

variable "cleanuparr_cpu_request" {
  description = "CPU request for Cleanuparr container"
  type        = string
  default     = "25m"
}

variable "cleanuparr_cpu_limit" {
  description = "CPU limit for Cleanuparr container"
  type        = string
  default     = "200m"
}

variable "cleanuparr_image_tag" {
  description = "Cleanuparr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "cleanuparr" {
  metadata {
    name = "cleanuparr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cleanuparr"
    })
  }
}

# Deployment
resource "kubernetes_deployment" "cleanuparr" {
  metadata {
    name      = "cleanuparr"
    namespace = kubernetes_namespace.cleanuparr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cleanuparr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "cleanuparr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "cleanuparr"
        })
      }

      spec {
        container {
          name  = "cleanuparr"
          image = "flmedicmento/cleanuparr:${var.cleanuparr_image_tag}"

          port {
            container_port = 80
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          resources {
            requests = {
              memory = var.cleanuparr_memory_request
              cpu    = var.cleanuparr_cpu_request
            }
            limits = {
              memory = var.cleanuparr_memory_limit
              cpu    = var.cleanuparr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "cleanuparr" {
  depends_on = [
    kubernetes_deployment.cleanuparr
  ]

  metadata {
    name      = "cleanuparr-service"
    namespace = kubernetes_namespace.cleanuparr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "cleanuparr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "cleanuparr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 80
    }
  }
}

# Outputs
output "cleanuparr_info" {
  description = "Cleanuparr library cleanup information"
  value = {
    namespace    = kubernetes_namespace.cleanuparr.metadata[0].name
    service_name = kubernetes_service.cleanuparr.metadata[0].name

    access = {
      web_ui = "https://cleanuparr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.cleanuparr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.cleanuparr.metadata[0].name} -l app=cleanuparr -f"
    }
  }

  sensitive = true
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt cleanuparr.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/cleanuparr.tf
git commit -m "feat: add Cleanuparr library cleanup service"
```

---

## Task 5: Create `terraform/sabnzbd.tf` — Usenet Download Client

**Files:**
- Create: `terraform/sabnzbd.tf`

**Step 1: Write the SABnzbd Terraform file**

SABnzbd has Longhorn config PVC + NFS downloads PVC. Configured post-deploy via web UI.

```hcl
# =============================================================================
# SABnzbd — Usenet Download Client
# =============================================================================
# Usenet downloader used by Sonarr/Radarr as a download client.
# Longhorn PVC for config, NFS PVC for downloads.
# Configure Usenet servers via the web UI after deployment.
# =============================================================================

# Variables
variable "sabnzbd_storage_size" {
  description = "Storage size for SABnzbd config"
  type        = string
  default     = "1Gi"
}

variable "sabnzbd_memory_request" {
  description = "Memory request for SABnzbd container"
  type        = string
  default     = "256Mi"
}

variable "sabnzbd_memory_limit" {
  description = "Memory limit for SABnzbd container"
  type        = string
  default     = "512Mi"
}

variable "sabnzbd_cpu_request" {
  description = "CPU request for SABnzbd container"
  type        = string
  default     = "100m"
}

variable "sabnzbd_cpu_limit" {
  description = "CPU limit for SABnzbd container"
  type        = string
  default     = "1000m"
}

variable "sabnzbd_image_tag" {
  description = "SABnzbd container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "sabnzbd" {
  metadata {
    name = "sabnzbd"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sabnzbd"
    })
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "sabnzbd_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "sabnzbd-config"
    namespace = kubernetes_namespace.sabnzbd.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.sabnzbd_storage_size
      }
    }
  }
}

# Persistent Volume — NFS Downloads (static PV)
resource "kubernetes_persistent_volume" "sabnzbd_downloads" {
  metadata {
    name   = "sabnzbd-downloads-pv"
    labels = var.common_labels
  }

  spec {
    capacity = {
      storage = "1Ti"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "nfs-downloads"

    persistent_volume_source {
      nfs {
        server = var.nfs_server
        path   = var.nfs_downloads_share
      }
    }
  }

  depends_on = [kubernetes_storage_class.nfs_downloads]
}

resource "kubernetes_persistent_volume_claim" "sabnzbd_downloads" {
  metadata {
    name      = "sabnzbd-downloads"
    namespace = kubernetes_namespace.sabnzbd.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-downloads"
    volume_name        = kubernetes_persistent_volume.sabnzbd_downloads.metadata[0].name
    resources {
      requests = {
        storage = "1Ti"
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "sabnzbd" {
  depends_on = [
    kubernetes_persistent_volume_claim.sabnzbd_config,
    kubernetes_persistent_volume_claim.sabnzbd_downloads,
    helm_release.longhorn
  ]

  metadata {
    name      = "sabnzbd"
    namespace = kubernetes_namespace.sabnzbd.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sabnzbd"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "sabnzbd"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "sabnzbd"
        })
      }

      spec {
        container {
          name  = "sabnzbd"
          image = "linuxserver/sabnzbd:${var.sabnzbd_image_tag}"

          port {
            container_port = 8080
          }

          env {
            name  = "PUID"
            value = "1000"
          }

          env {
            name  = "PGID"
            value = "1000"
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "sabnzbd-config"
            mount_path = "/config"
          }

          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }

          resources {
            requests = {
              memory = var.sabnzbd_memory_request
              cpu    = var.sabnzbd_cpu_request
            }
            limits = {
              memory = var.sabnzbd_memory_limit
              cpu    = var.sabnzbd_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/api?mode=version"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/api?mode=version"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "sabnzbd-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sabnzbd_config.metadata[0].name
          }
        }

        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.sabnzbd_downloads.metadata[0].name
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "sabnzbd" {
  depends_on = [
    kubernetes_deployment.sabnzbd
  ]

  metadata {
    name      = "sabnzbd-service"
    namespace = kubernetes_namespace.sabnzbd.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "sabnzbd"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "sabnzbd"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 8080
    }
  }
}

# Outputs
output "sabnzbd_info" {
  description = "SABnzbd Usenet download client information"
  value = {
    namespace    = kubernetes_namespace.sabnzbd.metadata[0].name
    service_name = kubernetes_service.sabnzbd.metadata[0].name
    config_size  = var.sabnzbd_storage_size

    access = {
      web_ui = "https://sabnzbd.${var.traefik_domain}"
    }

    nfs_mounts = {
      downloads = "${var.nfs_server}:${var.nfs_downloads_share}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.sabnzbd.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.sabnzbd.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.sabnzbd.metadata[0].name} -l app=sabnzbd -f"
    }
  }

  sensitive = true
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt sabnzbd.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/sabnzbd.tf
git commit -m "feat: add SABnzbd Usenet download client"
```

---

## Task 6: Create `terraform/notifiarr.tf` — Rich Notifications

**Files:**
- Create: `terraform/notifiarr.tf`

**Step 1: Write the Notifiarr Terraform file**

Migrated from LXC 101. Config file managed as a sensitive Terraform variable, stored in a Kubernetes Secret.

```hcl
# =============================================================================
# Notifiarr — Rich Notifications for Arr Stack
# =============================================================================
# Migrated from LXC 101. Receives webhooks from arr services and sends
# rich notifications to Discord/Telegram/etc.
# Config file from LXC stored as a Kubernetes Secret.
# =============================================================================

# Variables
variable "notifiarr_storage_size" {
  description = "Storage size for Notifiarr config"
  type        = string
  default     = "1Gi"
}

variable "notifiarr_memory_request" {
  description = "Memory request for Notifiarr container"
  type        = string
  default     = "64Mi"
}

variable "notifiarr_memory_limit" {
  description = "Memory limit for Notifiarr container"
  type        = string
  default     = "128Mi"
}

variable "notifiarr_cpu_request" {
  description = "CPU request for Notifiarr container"
  type        = string
  default     = "25m"
}

variable "notifiarr_cpu_limit" {
  description = "CPU limit for Notifiarr container"
  type        = string
  default     = "200m"
}

variable "notifiarr_image_tag" {
  description = "Notifiarr container image tag"
  type        = string
  default     = "latest"
}

variable "notifiarr_config" {
  description = "Contents of the notifiarr.conf configuration file (migrated from LXC 101)"
  type        = string
  sensitive   = true
  default     = ""
}

# Namespace
resource "kubernetes_namespace" "notifiarr" {
  metadata {
    name = "notifiarr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "notifiarr"
    })
  }
}

# Secret — Config file (from LXC 101 migration)
resource "kubernetes_secret" "notifiarr_config" {
  count = var.notifiarr_config != "" ? 1 : 0

  metadata {
    name      = "notifiarr-config"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "notifiarr.conf" = var.notifiarr_config
  }
}

# Persistent Volume Claim — Config (Longhorn)
resource "kubernetes_persistent_volume_claim" "notifiarr_config" {
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "notifiarr-config"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.notifiarr_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "notifiarr" {
  depends_on = [
    kubernetes_persistent_volume_claim.notifiarr_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "notifiarr"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "notifiarr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "notifiarr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "notifiarr"
        })
      }

      spec {
        container {
          name  = "notifiarr"
          image = "golift/notifiarr:${var.notifiarr_image_tag}"

          port {
            container_port = 5454
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          volume_mount {
            name       = "notifiarr-config"
            mount_path = "/config"
          }

          dynamic "volume_mount" {
            for_each = var.notifiarr_config != "" ? [1] : []
            content {
              name       = "notifiarr-secret-config"
              mount_path = "/config/notifiarr.conf"
              sub_path   = "notifiarr.conf"
            }
          }

          resources {
            requests = {
              memory = var.notifiarr_memory_request
              cpu    = var.notifiarr_cpu_request
            }
            limits = {
              memory = var.notifiarr_memory_limit
              cpu    = var.notifiarr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 5454
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 5454
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "notifiarr-config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.notifiarr_config.metadata[0].name
          }
        }

        dynamic "volume" {
          for_each = var.notifiarr_config != "" ? [1] : []
          content {
            name = "notifiarr-secret-config"
            secret {
              secret_name = kubernetes_secret.notifiarr_config[0].metadata[0].name
            }
          }
        }
      }
    }
  }
}

# Service
resource "kubernetes_service" "notifiarr" {
  depends_on = [
    kubernetes_deployment.notifiarr
  ]

  metadata {
    name      = "notifiarr-service"
    namespace = kubernetes_namespace.notifiarr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "notifiarr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "notifiarr"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5454
    }
  }
}

# Outputs
output "notifiarr_info" {
  description = "Notifiarr notification service information"
  value = {
    namespace    = kubernetes_namespace.notifiarr.metadata[0].name
    service_name = kubernetes_service.notifiarr.metadata[0].name
    storage_size = var.notifiarr_storage_size
    config_from_secret = var.notifiarr_config != ""

    access = {
      web_ui = "https://notifiarr.${var.traefik_domain}"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.notifiarr.metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.notifiarr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.notifiarr.metadata[0].name} -l app=notifiarr -f"
    }
  }

  sensitive = true
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt notifiarr.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/notifiarr.tf
git commit -m "feat: add Notifiarr notification service (migrated from LXC 101)"
```

---

## Task 7: Create `terraform/flaresolverr.tf` — CAPTCHA Solver

**Files:**
- Create: `terraform/flaresolverr.tf`

**Step 1: Write the Flaresolverr Terraform file**

Internal-only service. No IngressRoute, no DNS. Prowlarr connects via cluster DNS.

```hcl
# =============================================================================
# Flaresolverr — CAPTCHA/Cloudflare Bypass Proxy
# =============================================================================
# Runs a headless Chromium instance to solve CAPTCHAs for Prowlarr indexers.
# Internal-only: no IngressRoute or DNS record.
# Prowlarr connects via: flaresolverr-service.flaresolverr.svc.cluster.local:8191
# =============================================================================

# Variables
variable "flaresolverr_memory_request" {
  description = "Memory request for Flaresolverr container"
  type        = string
  default     = "256Mi"
}

variable "flaresolverr_memory_limit" {
  description = "Memory limit for Flaresolverr container"
  type        = string
  default     = "512Mi"
}

variable "flaresolverr_cpu_request" {
  description = "CPU request for Flaresolverr container"
  type        = string
  default     = "100m"
}

variable "flaresolverr_cpu_limit" {
  description = "CPU limit for Flaresolverr container"
  type        = string
  default     = "1000m"
}

variable "flaresolverr_image_tag" {
  description = "Flaresolverr container image tag"
  type        = string
  default     = "latest"
}

# Namespace
resource "kubernetes_namespace" "flaresolverr" {
  metadata {
    name = "flaresolverr"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flaresolverr"
    })
  }
}

# Deployment (stateless — no PVC)
resource "kubernetes_deployment" "flaresolverr" {
  metadata {
    name      = "flaresolverr"
    namespace = kubernetes_namespace.flaresolverr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flaresolverr"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "flaresolverr"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "flaresolverr"
        })
      }

      spec {
        container {
          name  = "flaresolverr"
          image = "ghcr.io/flaresolverr/flaresolverr:${var.flaresolverr_image_tag}"

          port {
            container_port = 8191
          }

          env {
            name  = "TZ"
            value = "Australia/Brisbane"
          }

          env {
            name  = "LOG_LEVEL"
            value = "info"
          }

          resources {
            requests = {
              memory = var.flaresolverr_memory_request
              cpu    = var.flaresolverr_cpu_request
            }
            limits = {
              memory = var.flaresolverr_memory_limit
              cpu    = var.flaresolverr_cpu_limit
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8191
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8191
            }
            initial_delay_seconds = 10
            period_seconds        = 5
          }
        }
      }
    }
  }
}

# Service (internal-only — no IngressRoute)
resource "kubernetes_service" "flaresolverr" {
  depends_on = [
    kubernetes_deployment.flaresolverr
  ]

  metadata {
    name      = "flaresolverr-service"
    namespace = kubernetes_namespace.flaresolverr.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "flaresolverr"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "flaresolverr"
    }

    port {
      protocol    = "TCP"
      port        = 8191
      target_port = 8191
    }
  }
}

# Outputs
output "flaresolverr_info" {
  description = "Flaresolverr CAPTCHA solver information"
  value = {
    namespace     = kubernetes_namespace.flaresolverr.metadata[0].name
    service_name  = kubernetes_service.flaresolverr.metadata[0].name
    cluster_dns   = "flaresolverr-service.${kubernetes_namespace.flaresolverr.metadata[0].name}.svc.cluster.local:8191"
    internal_only = true

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.flaresolverr.metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.flaresolverr.metadata[0].name} -l app=flaresolverr -f"
      test       = "kubectl exec -n ${kubernetes_namespace.flaresolverr.metadata[0].name} -it deploy/flaresolverr -- wget -qO- http://localhost:8191/health"
    }
  }
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt flaresolverr.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/flaresolverr.tf
git commit -m "feat: add Flaresolverr CAPTCHA solver (internal-only)"
```

---

## Task 8: Modify `terraform/ingress.tf` — Add Wave 4 IngressRoutes

**Files:**
- Modify: `terraform/ingress.tf`

**Step 1: Add IngressRoutes for 6 Wave 4 services**

Append after the Emby IngressRoute (before the `# --- Static Sites ---` section). All get rate-limit + crowdsec-bouncer + oauth-forward-auth middleware except where noted.

```hcl
# Bazarr
resource "kubernetes_manifest" "ingressroute_bazarr" {
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
          name      = kubernetes_service.bazarr.metadata[0].name
          namespace = kubernetes_namespace.bazarr.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Jackett
resource "kubernetes_manifest" "ingressroute_jackett" {
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
          name      = kubernetes_service.jackett.metadata[0].name
          namespace = kubernetes_namespace.jackett.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Huntarr
resource "kubernetes_manifest" "ingressroute_huntarr" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "huntarr"
      namespace = kubernetes_namespace.traefik.metadata[0].name
      labels    = var.common_labels
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [{
        match = "Host(`huntarr.${var.traefik_domain}`)"
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
          name      = kubernetes_service.huntarr.metadata[0].name
          namespace = kubernetes_namespace.huntarr.metadata[0].name
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
    kubernetes_service.huntarr,
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Cleanuparr
resource "kubernetes_manifest" "ingressroute_cleanuparr" {
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
          name      = kubernetes_service.cleanuparr.metadata[0].name
          namespace = kubernetes_namespace.cleanuparr.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# SABnzbd
resource "kubernetes_manifest" "ingressroute_sabnzbd" {
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
          name      = kubernetes_service.sabnzbd.metadata[0].name
          namespace = kubernetes_namespace.sabnzbd.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}

# Notifiarr
resource "kubernetes_manifest" "ingressroute_notifiarr" {
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
          name      = kubernetes_service.notifiarr.metadata[0].name
          namespace = kubernetes_namespace.notifiarr.metadata[0].name
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
    kubernetes_manifest.middleware_rate_limit,
    kubernetes_manifest.middleware_crowdsec_bouncer,
    kubernetes_manifest.middleware_oauth_forward_auth,
  ]
}
```

**Step 2: Validate**

Run: `cd terraform && terraform fmt ingress.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/ingress.tf
git commit -m "feat: add Wave 4 IngressRoutes (bazarr, jackett, huntarr, cleanuparr, sabnzbd, notifiarr)"
```

---

## Task 9: Modify `terraform/dns.tf` — Add Wave 4 DNS Records

**Files:**
- Modify: `terraform/dns.tf`

**Step 1: Add 6 new entries to the `dns_records` local**

In the `locals` block (around line 43-61), add after the `emby` entry:

```hcl
    bazarr       = "bazarr"
    jackett      = "jackett"
    huntarr      = "huntarr"
    cleanuparr   = "cleanuparr"
    sabnzbd      = "sabnzbd"
    notifiarr    = "notifiarr"
```

Note: Flaresolverr is intentionally excluded — it has no IngressRoute or DNS record.

**Step 2: Validate**

Run: `cd terraform && terraform fmt dns.tf && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/dns.tf
git commit -m "feat: add Wave 4 DNS records (bazarr, jackett, huntarr, cleanuparr, sabnzbd, notifiarr)"
```

---

## Task 10: Modify `terraform/Makefile` — Add Wave 4 Targets

**Files:**
- Modify: `terraform/Makefile`

**Step 1: Add to `.PHONY` declaration**

Add to the `.PHONY` continuation lines (after `plan-emby apply-emby`):

```makefile
	plan-bazarr apply-bazarr plan-jackett apply-jackett plan-huntarr apply-huntarr \
	plan-cleanuparr apply-cleanuparr plan-sabnzbd apply-sabnzbd plan-notifiarr apply-notifiarr \
	plan-flaresolverr apply-flaresolverr
```

**Step 2: Add plan targets**

Add after the `plan-emby` target:

```makefile
plan-bazarr: check-vars check-init ## Plan Bazarr subtitle management
	@echo "Planning Bazarr components..."
	terraform plan \
		-target=kubernetes_namespace.bazarr \
		-target=kubernetes_persistent_volume_claim.bazarr_config \
		-target=kubernetes_persistent_volume.bazarr_media \
		-target=kubernetes_persistent_volume_claim.bazarr_media \
		-target=kubernetes_deployment.bazarr \
		-target=kubernetes_service.bazarr

plan-jackett: check-vars check-init ## Plan Jackett indexer
	@echo "Planning Jackett components..."
	terraform plan \
		-target=kubernetes_namespace.jackett \
		-target=kubernetes_persistent_volume_claim.jackett_config \
		-target=kubernetes_deployment.jackett \
		-target=kubernetes_service.jackett

plan-huntarr: check-vars check-init ## Plan Huntarr missing media hunter
	@echo "Planning Huntarr components..."
	terraform plan \
		-target=kubernetes_namespace.huntarr \
		-target=kubernetes_persistent_volume_claim.huntarr_config \
		-target=kubernetes_deployment.huntarr \
		-target=kubernetes_service.huntarr

plan-cleanuparr: check-vars check-init ## Plan Cleanuparr library cleanup
	@echo "Planning Cleanuparr components..."
	terraform plan \
		-target=kubernetes_namespace.cleanuparr \
		-target=kubernetes_deployment.cleanuparr \
		-target=kubernetes_service.cleanuparr

plan-sabnzbd: check-vars check-init ## Plan SABnzbd Usenet client
	@echo "Planning SABnzbd components..."
	terraform plan \
		-target=kubernetes_namespace.sabnzbd \
		-target=kubernetes_persistent_volume_claim.sabnzbd_config \
		-target=kubernetes_persistent_volume.sabnzbd_downloads \
		-target=kubernetes_persistent_volume_claim.sabnzbd_downloads \
		-target=kubernetes_deployment.sabnzbd \
		-target=kubernetes_service.sabnzbd

plan-notifiarr: check-vars check-init ## Plan Notifiarr notifications
	@echo "Planning Notifiarr components..."
	terraform plan \
		-target=kubernetes_namespace.notifiarr \
		-target=kubernetes_persistent_volume_claim.notifiarr_config \
		-target=kubernetes_deployment.notifiarr \
		-target=kubernetes_service.notifiarr

plan-flaresolverr: check-vars check-init ## Plan Flaresolverr CAPTCHA solver
	@echo "Planning Flaresolverr components..."
	terraform plan \
		-target=kubernetes_namespace.flaresolverr \
		-target=kubernetes_deployment.flaresolverr \
		-target=kubernetes_service.flaresolverr
```

**Step 3: Add apply targets**

Add after the `apply-emby` target:

```makefile
apply-bazarr: check-vars check-init ## Deploy Bazarr subtitle management
	@echo "Deploying Bazarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.bazarr \
		-target=kubernetes_persistent_volume_claim.bazarr_config \
		-target=kubernetes_persistent_volume.bazarr_media \
		-target=kubernetes_persistent_volume_claim.bazarr_media \
		-target=kubernetes_deployment.bazarr \
		-target=kubernetes_service.bazarr

apply-jackett: check-vars check-init ## Deploy Jackett indexer
	@echo "Deploying Jackett..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.jackett \
		-target=kubernetes_persistent_volume_claim.jackett_config \
		-target=kubernetes_deployment.jackett \
		-target=kubernetes_service.jackett

apply-huntarr: check-vars check-init ## Deploy Huntarr missing media hunter
	@echo "Deploying Huntarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.huntarr \
		-target=kubernetes_persistent_volume_claim.huntarr_config \
		-target=kubernetes_deployment.huntarr \
		-target=kubernetes_service.huntarr

apply-cleanuparr: check-vars check-init ## Deploy Cleanuparr library cleanup
	@echo "Deploying Cleanuparr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.cleanuparr \
		-target=kubernetes_deployment.cleanuparr \
		-target=kubernetes_service.cleanuparr

apply-sabnzbd: check-vars check-init ## Deploy SABnzbd Usenet client
	@echo "Deploying SABnzbd..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.sabnzbd \
		-target=kubernetes_persistent_volume_claim.sabnzbd_config \
		-target=kubernetes_persistent_volume.sabnzbd_downloads \
		-target=kubernetes_persistent_volume_claim.sabnzbd_downloads \
		-target=kubernetes_deployment.sabnzbd \
		-target=kubernetes_service.sabnzbd

apply-notifiarr: check-vars check-init ## Deploy Notifiarr notifications
	@echo "Deploying Notifiarr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.notifiarr \
		-target=kubernetes_persistent_volume_claim.notifiarr_config \
		-target=kubernetes_deployment.notifiarr \
		-target=kubernetes_service.notifiarr

apply-flaresolverr: check-vars check-init ## Deploy Flaresolverr CAPTCHA solver
	@echo "Deploying Flaresolverr..."
	terraform apply -auto-approve \
		-target=kubernetes_namespace.flaresolverr \
		-target=kubernetes_deployment.flaresolverr \
		-target=kubernetes_service.flaresolverr
```

**Step 4: Commit**

```bash
git add terraform/Makefile
git commit -m "feat: add Wave 4 Makefile targets"
```

---

## Task 11: Modify `terraform/terraform.tfvars.example` — Add Wave 4 Variables

**Files:**
- Modify: `terraform/terraform.tfvars.example`

**Step 1: Add Wave 4 variable examples**

Append after the Emby section (before the Labels section):

```hcl
# Bazarr Subtitle Management
#bazarr_storage_size   = "1Gi"
#bazarr_memory_request = "128Mi"
#bazarr_memory_limit   = "256Mi"
#bazarr_image_tag      = "latest"

# Jackett Indexer
#jackett_storage_size   = "1Gi"
#jackett_memory_request = "128Mi"
#jackett_memory_limit   = "256Mi"
#jackett_image_tag      = "latest"

# Huntarr Missing Media Hunter
#huntarr_storage_size   = "512Mi"
#huntarr_memory_request = "64Mi"
#huntarr_memory_limit   = "128Mi"
#huntarr_image_tag      = "latest"

# Cleanuparr Library Cleanup (stateless)
#cleanuparr_memory_request = "64Mi"
#cleanuparr_memory_limit   = "128Mi"
#cleanuparr_image_tag      = "latest"

# SABnzbd Usenet Client
#sabnzbd_storage_size   = "1Gi"
#sabnzbd_memory_request = "256Mi"
#sabnzbd_memory_limit   = "512Mi"
#sabnzbd_image_tag      = "latest"

# Notifiarr Notifications (migrated from LXC 101)
#notifiarr_storage_size   = "1Gi"
#notifiarr_memory_request = "64Mi"
#notifiarr_memory_limit   = "128Mi"
#notifiarr_image_tag      = "latest"
#notifiarr_config         = ""  # Paste contents of notifiarr.conf from LXC 101

# Flaresolverr CAPTCHA Solver (internal-only, no IngressRoute)
#flaresolverr_memory_request = "256Mi"
#flaresolverr_memory_limit   = "512Mi"
#flaresolverr_image_tag      = "latest"
```

**Step 2: Validate**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit**

```bash
git add terraform/terraform.tfvars.example
git commit -m "feat: add Wave 4 variables to tfvars example"
```

---

## Task 12: Update `CLAUDE.md` — Add Wave 4 Documentation

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Wave 4 files to the File Organization section**

Add after the `dns.tf` entry in the file organization list:

```markdown
- [nfs.tf](terraform/nfs.tf) — NFS CSI driver for Synology NAS storage provisioning
- [crowdsec.tf](terraform/crowdsec.tf) — CrowdSec intrusion detection (LAPI + agent DaemonSet)
- [oauth.tf](terraform/oauth.tf) — OAuth2 Proxy with GitHub SSO (ForwardAuth middleware)
- [n8n.tf](terraform/n8n.tf) — n8n workflow automation platform
- [postfix.tf](terraform/postfix.tf) — Postfix SMTP relay for outbound mail
- [squid.tf](terraform/squid.tf) — Squid caching HTTP proxy
- [prowlarr.tf](terraform/prowlarr.tf) — Prowlarr indexer aggregation
- [sonarr.tf](terraform/sonarr.tf) — Sonarr TV show management (NFS media + downloads)
- [radarr.tf](terraform/radarr.tf) — Radarr movie management (NFS media + downloads)
- [qbittorrent.tf](terraform/qbittorrent.tf) — qBittorrent with gluetun VPN sidecar (NFS downloads)
- [emby.tf](terraform/emby.tf) — Emby media server (NFS media)
- [bazarr.tf](terraform/bazarr.tf) — Bazarr subtitle management (NFS media)
- [jackett.tf](terraform/jackett.tf) — Jackett indexer support
- [huntarr.tf](terraform/huntarr.tf) — Huntarr missing media hunter
- [cleanuparr.tf](terraform/cleanuparr.tf) — Cleanuparr library cleanup (stateless)
- [sabnzbd.tf](terraform/sabnzbd.tf) — SABnzbd Usenet download client (NFS downloads)
- [notifiarr.tf](terraform/notifiarr.tf) — Notifiarr rich notifications (migrated from LXC 101)
- [flaresolverr.tf](terraform/flaresolverr.tf) — Flaresolverr CAPTCHA solver (internal-only)
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Wave 4 file organization"
```

---

## Task 13: Validate Full Configuration

**Step 1: Format all Terraform files**

Run: `cd terraform && terraform fmt -recursive`
Expected: Lists any files that were reformatted (or no output if already formatted)

**Step 2: Validate configuration**

Run: `cd terraform && terraform validate`
Expected: "Success! The configuration is valid."

**Step 3: Commit any formatting changes**

```bash
git add terraform/
git commit -m "chore: format Wave 4 terraform files"
```

---

## Deployment Order

All Wave 4 services are independent of each other and can be deployed in any order. They all depend on Wave 0 (NFS for Bazarr/SABnzbd) and Wave 1 (CrowdSec/OAuth for middleware).

```
Wave 4 (any order):
  make apply-bazarr         → Bazarr subtitle management
  make apply-jackett        → Jackett indexer support
  make apply-huntarr        → Huntarr missing media hunter
  make apply-cleanuparr     → Cleanuparr library cleanup
  make apply-sabnzbd        → SABnzbd Usenet client
  make apply-notifiarr      → Notifiarr notifications
  make apply-flaresolverr   → Flaresolverr CAPTCHA solver
  make apply-ingress        → Updated IngressRoutes with Wave 4 services
  make apply-azure-dns      → DNS records for Wave 4 services
```
