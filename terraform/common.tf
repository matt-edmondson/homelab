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
      name  = "args"
      value = "{--cert-dir=/tmp,--secure-port=4443,--kubelet-preferred-address-types=InternalIP\\,ExternalIP\\,Hostname,--kubelet-use-node-status-port,--metric-resolution=15s,--kubelet-insecure-tls}"
    },
    {
      name  = "metrics.enabled"
      value = "true"
    },
    {
      name  = "serviceMonitor.enabled"
      value = "true"
    }
  ]
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
