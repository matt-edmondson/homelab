# =============================================================================
# Kubernetes Dashboard - Self-Contained Module
# =============================================================================

# Variables
variable "kubernetes_dashboard_chart_version" {
  description = "Version of Kubernetes Dashboard Helm chart"
  type        = string
  default     = "7.13.0"
}

variable "dashboard_enable_skip_login" {
  description = "Enable skip login button for homelab convenience (less secure)"
  type        = bool
  default     = true
}

variable "dashboard_enable_insecure_login" {
  description = "Enable insecure login for homelab convenience (less secure)"
  type        = bool
  default     = true
}

variable "dashboard_session_lifetime" {
  description = "Session lifetime in seconds"
  type        = number
  default     = 43200  # 12 hours
}

variable "dashboard_auto_generate_certificates" {
  description = "Auto-generate certificates for dashboard"
  type        = bool
  default     = true
}

# Namespace
resource "kubernetes_namespace" "kubernetes_dashboard" {
  metadata {
    name = "kubernetes-dashboard"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "kubernetes-dashboard"
    })
  }
}

# Admin User ServiceAccount for easier access in homelab
resource "kubernetes_service_account" "dashboard_admin_user" {
  metadata {
    name      = "dashboard-admin-user"
    namespace = kubernetes_namespace.kubernetes_dashboard.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "dashboard-admin-user"
    })
  }
}

# ClusterRoleBinding to give admin access
resource "kubernetes_cluster_role_binding" "dashboard_admin_user" {
  metadata {
    name = "dashboard-admin-user"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "dashboard-admin-user"
    })
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.dashboard_admin_user.metadata[0].name
    namespace = kubernetes_service_account.dashboard_admin_user.metadata[0].namespace
  }
}

# Secret for the admin user token (Kubernetes 1.24+)
resource "kubernetes_secret" "dashboard_admin_user_token" {
  metadata {
    name      = "dashboard-admin-user-token"
    namespace = kubernetes_namespace.kubernetes_dashboard.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "dashboard-admin-user-token"
    })
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.dashboard_admin_user.metadata[0].name
    }
  }
  
  type = "kubernetes.io/service-account-token"
  
  depends_on = [kubernetes_service_account.dashboard_admin_user]
}

# Kubernetes Dashboard Helm Release
resource "helm_release" "kubernetes_dashboard" {
  name       = "kubernetes-dashboard"
  repository = "https://kubernetes.github.io/dashboard/"
  chart      = "kubernetes-dashboard"
  version    = var.kubernetes_dashboard_chart_version
  namespace  = kubernetes_namespace.kubernetes_dashboard.metadata[0].name

  values = [
    yamlencode({
      app = {
        ingress = {
          enabled = false
        }
        
        # Security settings for homelab
        settings = {
          itemsPerPage = 25
          labelsLimit = 3
          logsAutoRefreshTimeInterval = 5
          resourceAutoRefreshTimeInterval = 5
          disableAccessDeniedNotifications = false
        }
        
        # Enable skip login and insecure access for homelab convenience
        extraArgs = concat([
          "--enable-skip-login=${var.dashboard_enable_skip_login}",
          "--enable-insecure-login=${var.dashboard_enable_insecure_login}",
          "--disable-settings-authorizer=true",
          "--session-lifetime=${var.dashboard_session_lifetime}"
        ], var.dashboard_auto_generate_certificates ? ["--auto-generate-certificates"] : [])
        
        # Service configuration
        service = {
          type = "ClusterIP"  # We'll create our own LoadBalancer service
          externalPort = 443
          internalPort = 8443
        }
        
        # Resource limits
        resources = {
          requests = {
            cpu = "100m"
            memory = "200Mi"
          }
          limits = {
            cpu = "500m"
            memory = "500Mi"
          }
        }
      }
      
      # Metrics scraper configuration
      metricsScraper = {
        enabled = true
        resources = {
          requests = {
            cpu = "100m"
            memory = "200Mi"
          }
          limits = {
            cpu = "500m"
            memory = "500Mi"
          }
        }
      }
      
      # Cert manager integration (disabled for simplicity)
      cert-manager = {
        enabled = false
      }
      
      # Nginx integration (disabled)
      nginx = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.kubernetes_dashboard,
    kubernetes_service_account.dashboard_admin_user,
    kubernetes_cluster_role_binding.dashboard_admin_user
  ]
}

# LoadBalancer Service for external access (gets DHCP IP from kube-vip)
resource "kubernetes_service" "kubernetes_dashboard_lb" {
  metadata {
    name      = "kubernetes-dashboard-lb"
    namespace = kubernetes_namespace.kubernetes_dashboard.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "kubernetes-dashboard"
      "app.kubernetes.io/component" = "kubernetes-dashboard"
    })
    annotations = {
      "kube-vip.io/loadbalancerHostname" = "dashboard"
    }
  }
  
  spec {
    type             = "LoadBalancer"
    load_balancer_ip = "0.0.0.0"  # Trigger kube-vip DHCP behavior
    selector = {
      "app.kubernetes.io/name"      = "kong"
      "app.kubernetes.io/component" = "app"
    }
    port {
      name        = "https"
      port        = 443
      target_port = 8443
      protocol    = "TCP"
    }
  }
  
  depends_on = [
    helm_release.kubernetes_dashboard,
    kubernetes_daemonset.kube_vip  # Ensure LoadBalancer support is available
  ]
}

# Outputs
output "kubernetes_dashboard_info" {
  description = "Kubernetes Dashboard information"
  value = {
    namespace           = kubernetes_namespace.kubernetes_dashboard.metadata[0].name
    chart_version       = var.kubernetes_dashboard_chart_version
    service_name        = kubernetes_service.kubernetes_dashboard_lb.metadata[0].name
    admin_user          = kubernetes_service_account.dashboard_admin_user.metadata[0].name
    skip_login_enabled  = var.dashboard_enable_skip_login
    insecure_login      = var.dashboard_enable_insecure_login
    session_lifetime    = "${var.dashboard_session_lifetime} seconds"
    
    ip_address = try(
      kubernetes_service.kubernetes_dashboard_lb.status[0].load_balancer[0].ingress[0].ip,
      "pending (will be assigned by router DHCP)"
    )
    
    access = {
      web_ui = "Access Dashboard at: https://<dhcp-assigned-ip>"
      insecure_access = var.dashboard_enable_insecure_login ? "http://<dhcp-assigned-ip>:8080" : "HTTPS only"
    }
    
    authentication = {
      method = var.dashboard_enable_skip_login ? "Skip login enabled for homelab convenience" : "Token authentication required"
      admin_token_command = "kubectl get secret -n ${kubernetes_namespace.kubernetes_dashboard.metadata[0].name} ${kubernetes_secret.dashboard_admin_user_token.metadata[0].name} -o jsonpath='{.data.token}' | base64 --decode"
    }
    
    commands = {
      check_pods = "kubectl get pods -n ${kubernetes_namespace.kubernetes_dashboard.metadata[0].name}"
      check_service = "kubectl get svc -n ${kubernetes_namespace.kubernetes_dashboard.metadata[0].name}"
      get_ip = "kubectl get svc -n ${kubernetes_namespace.kubernetes_dashboard.metadata[0].name} ${kubernetes_service.kubernetes_dashboard_lb.metadata[0].name} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
      get_admin_token = "kubectl get secret -n ${kubernetes_namespace.kubernetes_dashboard.metadata[0].name} ${kubernetes_secret.dashboard_admin_user_token.metadata[0].name} -o jsonpath='{.data.token}' | base64 --decode && echo"
      view_logs = "kubectl logs -n ${kubernetes_namespace.kubernetes_dashboard.metadata[0].name} -l app.kubernetes.io/name=kubernetes-dashboard -f"
    }
    
    security_notes = [
      "Skip login and insecure login are enabled for homelab convenience",
      "Admin user has cluster-admin privileges - suitable for homelab only",
      "For production, disable skip login and use proper RBAC",
      "Dashboard is accessible via HTTPS with auto-generated certificates"
    ]
  }
}
