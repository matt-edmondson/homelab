# =============================================================================
# NFS CSI Driver — Dynamic NFS Provisioning from Synology NAS
# =============================================================================
# Installs the Kubernetes NFS CSI driver via Helm and creates a StorageClass
# for dynamic PV provisioning from the NAS NFS exports.
#
# NAS: 192.168.0.148 (Synology)
# Exports: /volume2/media, /volume2/downloads
# =============================================================================

# Variables
variable "nfs_csi_chart_version" {
  description = "NFS CSI driver Helm chart version"
  type        = string
  default     = "4.11.0"
}

variable "nfs_server" {
  description = "IP address or hostname of the NFS server"
  type        = string
  default     = "192.168.0.148"
}

variable "nfs_media_share" {
  description = "NFS export path for media files"
  type        = string
  default     = "/volume2/media"
}

variable "nfs_downloads_share" {
  description = "NFS export path for downloads"
  type        = string
  default     = "/volume2/downloads"
}

# Helm Release — NFS CSI Driver
resource "helm_release" "nfs_csi_driver" {
  name       = "csi-driver-nfs"
  repository = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts"
  chart      = "csi-driver-nfs"
  version    = var.nfs_csi_chart_version
  namespace  = "kube-system"

  values = [
    yamlencode({
      controller = {
        replicas = 1
      }
    })
  ]

  timeout = 300
  wait    = true
}

# StorageClass — NFS Media (read-write-many, retain)
resource "kubernetes_storage_class" "nfs_media" {
  metadata {
    name   = "nfs-media"
    labels = var.common_labels
  }

  storage_provisioner    = "nfs.csi.k8s.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    server = var.nfs_server
    share  = var.nfs_media_share
  }

  mount_options = ["nfsvers=4.1", "hard"]

  depends_on = [helm_release.nfs_csi_driver]
}

# StorageClass — NFS Downloads (read-write-many, retain)
resource "kubernetes_storage_class" "nfs_downloads" {
  metadata {
    name   = "nfs-downloads"
    labels = var.common_labels
  }

  storage_provisioner    = "nfs.csi.k8s.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    server = var.nfs_server
    share  = var.nfs_downloads_share
  }

  mount_options = ["nfsvers=4.1", "hard"]

  depends_on = [helm_release.nfs_csi_driver]
}

# Outputs
output "nfs_info" {
  description = "NFS CSI driver information"
  value = {
    nfs_server              = var.nfs_server
    media_storage_class     = kubernetes_storage_class.nfs_media.metadata[0].name
    downloads_storage_class = kubernetes_storage_class.nfs_downloads.metadata[0].name

    commands = {
      check_driver = "kubectl get csidrivers"
      check_sc     = "kubectl get storageclass"
      check_pods   = "kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs"
    }
  }
}
