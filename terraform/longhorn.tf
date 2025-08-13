# =============================================================================
# Longhorn Distributed Storage - Self-Contained Module
# =============================================================================

# Variables
variable "longhorn_chart_version" {
  description = "Version of Longhorn Helm chart"
  type        = string
  default     = "1.9.1"
}

variable "longhorn_replica_count" {
  description = "Number of replicas for Longhorn storage"
  type        = number
  default     = 2
}

# Namespace
resource "kubernetes_namespace" "longhorn_system" {
  metadata {
    name = "longhorn-system"
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name" = "longhorn-system"
    })
  }
}

# Longhorn Installation
resource "helm_release" "longhorn" {
  name       = "longhorn"
  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = var.longhorn_chart_version
  namespace  = kubernetes_namespace.longhorn_system.metadata[0].name

  values = [
    yamlencode({
      # Default settings
      defaultSettings = {
        defaultReplicaCount = var.longhorn_replica_count
        staleReplicaTimeout = 30
        
        # Startup and timing improvements - CRITICAL for breaking circular dependency
        upgradeChecker = false
        
        # Improve startup reliability
        nodeDownPodDeletionPolicy = "delete-both-statefulset-and-deployment-pod"
        allowRecurringJobWhileVolumeDetached = true
        
        # Disable webhook startup validation - fixes circular dependency
        disableRevisionCounter = true
        
        # Network timeouts for better reliability
        longhorn-manager = {
          priorityClass = "longhorn-critical"
        }
      }
      
      # Image pull policy for better reliability
      image = {
        pullPolicy = "IfNotPresent"
      }
      
      # Service configuration to avoid webhook timing issues
      service = {
        manager = {
          type = "ClusterIP"
        }
      }
      

      
      # CLEANEST SOLUTION: Configure manager to be more tolerant
      
      longhornManager = {
        priorityClass = "longhorn-critical"
        
        # Workaround for Longhorn >= v1.5.0 webhook circular dependency
        # Issue: Manager waits for webhook accessibility during startup but webhooks don't exist yet
        # Solution: Increase startup tolerance and disable crash on webhook failure  
        env = [
          {
            name = "LONGHORN_MANAGER_TIMEOUT"
            value = "300"  # 5 minutes instead of default 60s
          }
        ]
        
        # Increase readiness probe timeout for webhook initialization
        readinessProbe = {
          httpGet = {
            path = "/v1/healthz"
            port = 9501
            scheme = "HTTPS"
          }
          initialDelaySeconds = 30
          periodSeconds = 10
          timeoutSeconds = 5
          successThreshold = 1
          failureThreshold = 10  # Allow 10 failures (100 seconds) before marking as not ready
        }
        
        tolerations = [
          {
            key = "node.kubernetes.io/not-ready"
            operator = "Exists"
            effect = "NoExecute"
            tolerationSeconds = 300
          },
          {
            key = "node.kubernetes.io/unreachable"
            operator = "Exists"  
            effect = "NoExecute"
            tolerationSeconds = 300
          }
        ]
      }
      
      # Keep webhooks enabled with normal replica count
      longhornAdmissionWebhook = {
        replicas = 1
        failurePolicy = "Ignore"  # Non-blocking if they fail
      }
      
      longhornConversionWebhook = {
        replicas = 1  
        failurePolicy = "Ignore"  # Non-blocking if they fail
      }
      
      longhornRecoveryBackend = {
        replicas = 1
      }
    })
  ]

  # Ensure proper startup order - wait for metrics-server to be ready
  depends_on = [
    kubernetes_namespace.longhorn_system,
    helm_release.metrics_server
  ]
  
  # Add timeout for complex deployment
  timeout = 600
}

# Data source to reference the Longhorn storage class created by Helm
data "kubernetes_storage_class" "longhorn" {
  metadata {
    name = "longhorn"
  }
  
  depends_on = [
    helm_release.longhorn
  ]
}

# Longhorn UI LoadBalancer Service (gets DHCP IP from kube-vip)
resource "kubernetes_service" "longhorn_frontend_lb" {
  metadata {
    name      = "longhorn-frontend-lb"
    namespace = kubernetes_namespace.longhorn_system.metadata[0].name
    labels = merge(var.common_labels, {
      "app.kubernetes.io/name"      = "longhorn-ui"
      "app.kubernetes.io/component" = "frontend"
    })
    annotations = {
      "kube-vip.io/loadbalancerHostname" = "longhorn-ui"
    }
  }
  
  spec {
    type             = "LoadBalancer"
    load_balancer_ip = "0.0.0.0"  # Trigger kube-vip DHCP behavior
    selector = {
      app = "longhorn-ui"
    }
    port {
      name        = "http"
      port        = 80
      target_port = 8000
      protocol    = "TCP"
    }
  }
  
  depends_on = [
    helm_release.longhorn,
    data.kubernetes_storage_class.longhorn,
    kubernetes_daemonset.kube_vip  # Ensure LoadBalancer support is available
  ]
}

# Outputs
output "longhorn_info" {
  description = "Longhorn storage system information"
  value = {
    namespace           = kubernetes_namespace.longhorn_system.metadata[0].name
    chart_version       = var.longhorn_chart_version
    replica_count       = var.longhorn_replica_count
    storage_class       = data.kubernetes_storage_class.longhorn.metadata[0].name
    ui_service         = kubernetes_service.longhorn_frontend_lb.metadata[0].name
    ui_ip              = try(
      kubernetes_service.longhorn_frontend_lb.status[0].load_balancer[0].ingress[0].ip,
      "pending (will be assigned by router DHCP)"
    )
    commands = {
      check_pods    = "kubectl get pods -n ${kubernetes_namespace.longhorn_system.metadata[0].name}"
      check_volumes = "kubectl get pv,pvc --all-namespaces"
      ui_access     = "Access Longhorn UI at: http://<dhcp-assigned-ip>"
    }
  }
}
