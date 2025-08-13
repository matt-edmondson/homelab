# =============================================================================
# Common Resources and Variables - Shared Across All Modules
# =============================================================================

# Provider Configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }
  }
}

# Variables that are shared across all modules
variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "environment" = "homelab"
  }
}

variable "metrics_server_enabled" {
  description = "Enable metrics-server installation for kubectl top and HPA functionality"
  type        = bool
  default     = true
}

# Providers
provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path
  }
}

# Metrics Server Installation (optional)
resource "helm_release" "metrics_server" {
  count = var.metrics_server_enabled ? 1 : 0
  
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.13.0"
  namespace  = "kube-system"

  set = [
    {
      name  = "apiService.create"
      value = "true"
    },
    {
      name  = "args[0]"
      value = "--kubelet-insecure-tls"
    },
    {
      name  = "args[1]"  
      value = "--kubelet-preferred-address-types=InternalIP\\,ExternalIP\\,Hostname"
    },
    {
      name  = "args[2]"
      value = "--kubelet-use-node-status-port"
    },
    {
      name  = "args[3]"
      value = "--metric-resolution=15s"
    },
    {
      name  = "resources.requests.cpu"
      value = "100m"
    },
    {
      name  = "resources.requests.memory"
      value = "200Mi"
    },
    {
      name  = "resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "resources.limits.memory"
      value = "500Mi"
    }
  ]
  
  # Add timeout for metrics-server to be ready
  timeout = 300
  
  # Wait for deployment to be ready before allowing dependents
  wait          = true
  wait_for_jobs = true
}

# =============================================================================
# kube-proxy RBAC (Essential for ClusterIP services)
# =============================================================================

resource "kubernetes_cluster_role" "system_node_proxier" {
  metadata {
    name = "system:node-proxier"
    labels = var.common_labels
  }

  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "nodes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["servicecidrs"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }
}

resource "kubernetes_cluster_role_binding" "system_node_proxier" {
  metadata {
    name = "system:node-proxier"
    labels = var.common_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.system_node_proxier.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "kube-proxy"
    namespace = "kube-system"
  }
}

# Common Outputs
output "cluster_info" {
  description = "General cluster information"
  value = {
    metrics_server_enabled = var.metrics_server_enabled
    common_labels         = var.common_labels
    
    commands = {
      check_all_pods     = "kubectl get pods --all-namespaces"
      check_all_services = "kubectl get services --all-namespaces"
      check_loadbalancers = "kubectl get services --all-namespaces | grep LoadBalancer"
      check_storage      = "kubectl get pv,pvc --all-namespaces"
    }
    
    metrics_usage = var.metrics_server_enabled ? [
      "kubectl top nodes",
      "kubectl top pods --all-namespaces"
    ] : ["Metrics server disabled - enable with metrics_server_enabled = true"]
  }
}
