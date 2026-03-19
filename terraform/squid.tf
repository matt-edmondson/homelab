# =============================================================================
# Squid — Caching HTTP Proxy
# =============================================================================
# Migrated from LXC 105. Caching forward proxy for internal use.
# Internal ClusterIP service only (no IngressRoute).
#
# Note: This service was largely idle on the LXC. Consider whether it's still
# needed before deploying.
# =============================================================================

# Variables
variable "squid_enabled" {
  description = "Enable Squid caching proxy deployment"
  type        = bool
  default     = true
}

variable "squid_cache_storage_size" {
  description = "Storage size for Squid cache"
  type        = string
  default     = "10Gi"
}

variable "squid_memory_request" {
  description = "Memory request for Squid container"
  type        = string
  default     = "64Mi"
}

variable "squid_memory_limit" {
  description = "Memory limit for Squid container"
  type        = string
  default     = "768Mi"
}

variable "squid_cpu_request" {
  description = "CPU request for Squid container"
  type        = string
  default     = "50m"
}

variable "squid_cpu_limit" {
  description = "CPU limit for Squid container"
  type        = string
  default     = "250m"
}

variable "squid_max_cache_size_mb" {
  description = "Maximum Squid disk cache size in MB"
  type        = number
  default     = 8192
}

# Namespace
resource "kubernetes_namespace" "squid" {
  count = var.squid_enabled ? 1 : 0

  metadata {
    name = "squid"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "squid"
    })
  }
}

# ConfigMap — squid.conf
resource "kubernetes_config_map" "squid_config" {
  count = var.squid_enabled ? 1 : 0

  metadata {
    name      = "squid-config"
    namespace = kubernetes_namespace.squid[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "squid.conf" = <<-EOT
      # Squid caching proxy configuration
      http_port 3128

      # Access control
      acl localnet src 10.0.0.0/8
      acl localnet src 172.16.0.0/12
      acl localnet src 192.168.0.0/16
      acl SSL_ports port 443
      acl Safe_ports port 80
      acl Safe_ports port 443
      acl Safe_ports port 1025-65535
      acl CONNECT method CONNECT

      http_access deny !Safe_ports
      http_access deny CONNECT !SSL_ports
      http_access allow localnet
      http_access allow localhost
      http_access deny all

      # Cache configuration (memory-only, no disk cache to reduce OOM risk)
      cache_dir null /tmp
      maximum_object_size 64 MB
      cache_mem 64 MB

      # Logging
      access_log daemon:/var/log/squid/access.log squid
      cache_log /var/log/squid/cache.log

      # Tuning
      shutdown_lifetime 5 seconds
      coredump_dir /var/spool/squid
    EOT
  }
}

# Persistent Volume Claim (Longhorn — cache storage)
resource "kubernetes_persistent_volume_claim" "squid_cache" {
  count = var.squid_enabled ? 1 : 0

  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn
  ]

  metadata {
    name      = "squid-cache"
    namespace = kubernetes_namespace.squid[0].metadata[0].name
    labels    = var.common_labels
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = data.kubernetes_storage_class.longhorn.metadata[0].name
    resources {
      requests = {
        storage = var.squid_cache_storage_size
      }
    }
  }
}

# Deployment
resource "kubernetes_deployment" "squid" {
  count = var.squid_enabled ? 1 : 0

  depends_on = [
    kubernetes_persistent_volume_claim.squid_cache,
    kubernetes_config_map.squid_config,
    helm_release.longhorn
  ]

  metadata {
    name      = "squid"
    namespace = kubernetes_namespace.squid[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "squid"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "squid"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "squid"
        })
      }

      spec {
        init_container {
          name    = "fix-permissions"
          image   = "busybox:latest"
          command = ["sh", "-c", "chown -R 13:13 /var/spool/squid && chmod -R 755 /var/spool/squid"]

          volume_mount {
            name       = "squid-cache"
            mount_path = "/var/spool/squid"
          }
        }

        container {
          name  = "squid"
          image = "sameersbn/squid:3.5.27-2"

          port {
            container_port = 3128
          }

          volume_mount {
            name       = "squid-config"
            mount_path = "/etc/squid/squid.conf"
            sub_path   = "squid.conf"
          }

          volume_mount {
            name       = "squid-cache"
            mount_path = "/var/spool/squid"
          }

          resources {
            requests = {
              memory = var.squid_memory_request
              cpu    = var.squid_cpu_request
            }
            limits = {
              memory = var.squid_memory_limit
              cpu    = var.squid_cpu_limit
            }
          }

          liveness_probe {
            tcp_socket {
              port = 3128
            }
            initial_delay_seconds = 15
            period_seconds        = 30
          }

          readiness_probe {
            tcp_socket {
              port = 3128
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        volume {
          name = "squid-config"
          config_map {
            name = kubernetes_config_map.squid_config[0].metadata[0].name
          }
        }

        volume {
          name = "squid-cache"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.squid_cache[0].metadata[0].name
          }
        }
      }
    }
  }
}

# Service (ClusterIP — internal proxy only)
resource "kubernetes_service" "squid" {
  count = var.squid_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.squid
  ]

  metadata {
    name      = "squid-service"
    namespace = kubernetes_namespace.squid[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "squid"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "squid"
    }

    port {
      protocol    = "TCP"
      port        = 3128
      target_port = 3128
    }
  }
}

# Outputs
output "squid_info" {
  description = "Squid caching proxy information"
  value = var.squid_enabled ? {
    namespace    = kubernetes_namespace.squid[0].metadata[0].name
    service_name = kubernetes_service.squid[0].metadata[0].name
    cache_size   = var.squid_cache_storage_size

    access = {
      proxy_internal = "squid-service.${kubernetes_namespace.squid[0].metadata[0].name}.svc.cluster.local:3128"
    }

    usage = {
      curl_via_proxy = "curl -x http://squid-service.squid.svc.cluster.local:3128 https://example.com"
    }

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.squid[0].metadata[0].name}"
      check_pvc  = "kubectl get pvc -n ${kubernetes_namespace.squid[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.squid[0].metadata[0].name} -l app=squid -f"
    }
  } : null

  sensitive = true
}
