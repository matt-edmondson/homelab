# =============================================================================
# Postfix — Outbound SMTP Relay
# =============================================================================
# Migrated from LXC 102. Handles outbound email for virtual domains,
# forwarding to Gmail. Internal ClusterIP service only (no IngressRoute).
#
# Domains: ktsu.dev, ktsu.io, matthewedmondson.com → Gmail
# =============================================================================

# Variables
variable "postfix_enabled" {
  description = "Enable Postfix SMTP relay deployment"
  type        = bool
  default     = true
}

variable "postfix_memory_request" {
  description = "Memory request for Postfix container"
  type        = string
  default     = "32Mi"
}

variable "postfix_memory_limit" {
  description = "Memory limit for Postfix container"
  type        = string
  default     = "128Mi"
}

variable "postfix_cpu_request" {
  description = "CPU request for Postfix container"
  type        = string
  default     = "50m"
}

variable "postfix_cpu_limit" {
  description = "CPU limit for Postfix container"
  type        = string
  default     = "200m"
}

variable "postfix_hostname" {
  description = "Mail hostname for Postfix (myhostname)"
  type        = string
  default     = "mail.ktsu.dev"
}

variable "postfix_relay_host" {
  description = "SMTP relay host (empty for direct delivery)"
  type        = string
  default     = ""
}

variable "postfix_virtual_domains" {
  description = "Space-separated list of virtual mailbox domains"
  type        = string
  default     = "ktsu.dev ktsu.io matthewedmondson.com"
}

variable "postfix_virtual_aliases" {
  description = "Virtual alias map entries (newline-separated, format: 'address destination')"
  type        = string
  default     = ""
  sensitive   = true
}

# Namespace
resource "kubernetes_namespace" "postfix" {
  count = var.postfix_enabled ? 1 : 0

  metadata {
    name = "postfix"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "postfix"
    })
  }
}

# ConfigMap — main.cf
resource "kubernetes_config_map" "postfix_config" {
  count = var.postfix_enabled ? 1 : 0

  metadata {
    name      = "postfix-config"
    namespace = kubernetes_namespace.postfix[0].metadata[0].name
    labels    = var.common_labels
  }

  data = {
    "main.cf" = <<-EOT
      # Postfix main configuration
      smtpd_banner = $myhostname ESMTP
      biff = no
      append_dot_mydomain = no

      myhostname = ${var.postfix_hostname}
      mydomain = ktsu.dev
      myorigin = $mydomain
      mydestination = localhost
      mynetworks = 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8

      # Virtual domain configuration
      virtual_alias_domains = ${var.postfix_virtual_domains}
      virtual_alias_maps = hash:/etc/postfix/virtual

      # TLS outbound
      smtp_tls_security_level = may
      smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt

      # Relay configuration
      ${var.postfix_relay_host != "" ? "relayhost = ${var.postfix_relay_host}" : "# Direct delivery (no relay)"}

      # Limits
      mailbox_size_limit = 0
      recipient_delimiter = +
      inet_interfaces = all
      inet_protocols = ipv4
    EOT

    "virtual" = var.postfix_virtual_aliases
  }
}

# Deployment
resource "kubernetes_deployment" "postfix" {
  count = var.postfix_enabled ? 1 : 0

  depends_on = [
    kubernetes_config_map.postfix_config,
  ]

  metadata {
    name      = "postfix"
    namespace = kubernetes_namespace.postfix[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "postfix"
    })
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "postfix"
      }
    }

    template {
      metadata {
        labels = merge(var.common_labels, {
          app = "postfix"
        })
      }

      spec {
        init_container {
          name    = "copy-config"
          image   = "boky/postfix:latest"
          command = ["sh", "-c", "cp -a /etc/postfix/* /postfix-writable/ && cp /config-source/main.cf /postfix-writable/main.cf && cp /config-source/virtual /postfix-writable/virtual"]

          volume_mount {
            name       = "postfix-config-source"
            mount_path = "/config-source"
          }

          volume_mount {
            name       = "postfix-config-writable"
            mount_path = "/postfix-writable"
          }
        }

        container {
          name  = "postfix"
          image = "boky/postfix:latest"

          port {
            container_port = 25
            protocol       = "TCP"
          }

          port {
            container_port = 587
            protocol       = "TCP"
          }

          env {
            name  = "ALLOWED_SENDER_DOMAINS"
            value = var.postfix_virtual_domains
          }

          env {
            name  = "HOSTNAME"
            value = var.postfix_hostname
          }

          volume_mount {
            name       = "postfix-config-writable"
            mount_path = "/etc/postfix"
          }

          resources {
            requests = {
              memory = var.postfix_memory_request
              cpu    = var.postfix_cpu_request
            }
            limits = {
              memory = var.postfix_memory_limit
              cpu    = var.postfix_cpu_limit
            }
          }

          liveness_probe {
            tcp_socket {
              port = 25
            }
            initial_delay_seconds = 15
            period_seconds        = 30
          }

          readiness_probe {
            tcp_socket {
              port = 25
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        volume {
          name = "postfix-config-source"
          config_map {
            name = kubernetes_config_map.postfix_config[0].metadata[0].name
          }
        }

        volume {
          name = "postfix-config-writable"
          empty_dir {}
        }
      }
    }
  }
}

# Service (ClusterIP — internal SMTP only)
resource "kubernetes_service" "postfix" {
  count = var.postfix_enabled ? 1 : 0

  depends_on = [
    kubernetes_deployment.postfix
  ]

  metadata {
    name      = "postfix-service"
    namespace = kubernetes_namespace.postfix[0].metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "postfix"
    })
  }

  spec {
    type = "ClusterIP"
    selector = {
      app = "postfix"
    }

    port {
      name        = "smtp"
      protocol    = "TCP"
      port        = 25
      target_port = 25
    }

    port {
      name        = "submission"
      protocol    = "TCP"
      port        = 587
      target_port = 587
    }
  }
}

# Outputs
output "postfix_info" {
  description = "Postfix SMTP relay information"
  value = var.postfix_enabled ? {
    namespace    = kubernetes_namespace.postfix[0].metadata[0].name
    service_name = kubernetes_service.postfix[0].metadata[0].name

    access = {
      smtp_internal = "postfix-service.${kubernetes_namespace.postfix[0].metadata[0].name}.svc.cluster.local:25"
      submission    = "postfix-service.${kubernetes_namespace.postfix[0].metadata[0].name}.svc.cluster.local:587"
    }

    virtual_domains = var.postfix_virtual_domains

    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.postfix[0].metadata[0].name}"
      logs       = "kubectl logs -n ${kubernetes_namespace.postfix[0].metadata[0].name} -l app=postfix -f"
      test_smtp  = "kubectl exec -n ${kubernetes_namespace.postfix[0].metadata[0].name} -it deploy/postfix -- postfix status"
    }
  } : null

  sensitive = true
}
