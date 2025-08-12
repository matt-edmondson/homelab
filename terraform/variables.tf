variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "metallb_ip_range" {
  description = "IP range for MetalLB LoadBalancer services"
  type        = list(string)
  default     = ["192.168.1.10-192.168.1.250"]
}

variable "metallb_asn" {
  description = "ASN for MetalLB speakers (cluster ASN)"
  type        = number
  default     = 65002
}

variable "router_asn" {
  description = "ASN for the router/gateway (UDM Pro ASN)"
  type        = number
  default     = 65001
}

variable "router_ip" {
  description = "IP address of the router/gateway for BGP peering"
  type        = string
  default     = "192.168.0.1"
}

variable "baget_api_key" {
  description = "API key for Baget NuGet server (generate a secure random key)"
  type        = string
  sensitive   = true
  default     = "your-secure-api-key-here"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
  default     = "admin123"
}

variable "longhorn_replica_count" {
  description = "Number of replicas for Longhorn storage"
  type        = number
  default     = 2
}

# Network Configuration
variable "cluster_domain" {
  description = "Kubernetes cluster domain"
  type        = string
  default     = "cluster.local"
}

# Application Configuration
variable "baget_storage_size" {
  description = "Storage size for Baget data"
  type        = string
  default     = "10Gi"
}

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus data"
  type        = string
  default     = "20Gi"
}

variable "prometheus_retention" {
  description = "Data retention period for Prometheus"
  type        = string
  default     = "15d"
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana data"
  type        = string
  default     = "10Gi"
}

variable "alertmanager_storage_size" {
  description = "Storage size for Alertmanager data"
  type        = string
  default     = "5Gi"
}

# Resource Limits
variable "baget_memory_request" {
  description = "Memory request for Baget container"
  type        = string
  default     = "256Mi"
}

variable "baget_memory_limit" {
  description = "Memory limit for Baget container"
  type        = string
  default     = "512Mi"
}

variable "baget_cpu_request" {
  description = "CPU request for Baget container"
  type        = string
  default     = "250m"
}

variable "baget_cpu_limit" {
  description = "CPU limit for Baget container"
  type        = string
  default     = "500m"
}

# Helm Chart Versions
variable "metallb_chart_version" {
  description = "Version of MetalLB Helm chart"
  type        = string
  default     = "0.14.5"
}

variable "longhorn_chart_version" {
  description = "Version of Longhorn Helm chart"
  type        = string
  default     = "1.6.2"
}

variable "prometheus_stack_chart_version" {
  description = "Version of kube-prometheus-stack Helm chart"
  type        = string
  default     = "57.2.0"
}

# Tags and Labels
variable "common_labels" {
  description = "Common labels to apply to all resources"
  type        = map(string)
  default = {
    "managed-by" = "terraform"
    "environment" = "homelab"
  }
}
