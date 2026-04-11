# =============================================================================
# NVIDIA Device Plugin — GPU Resource Scheduling
# =============================================================================
# Deploys the NVIDIA device plugin as a DaemonSet via Helm. This detects GPUs
# on K8s nodes and exposes them as schedulable `nvidia.com/gpu` resources.
#
# Each GPU node advertises nvidia.com/gpu: 1. Workloads requesting that
# resource get exclusive access to one GPU per node. VRAM-tier labels
# (gpu-vram-8gb, gpu-vram-12gb, etc.) let workloads express minimum VRAM
# requirements so the scheduler picks an appropriate node.
#
# Prerequisites per GPU node (use scripts/x86-k8s-worker.sh --gpu):
#   1. Blacklist nouveau driver
#   2. Install nvidia-driver + nvidia-container-toolkit
#   3. Configure containerd with NVIDIA runtime
#   4. Label node: kubectl label node <node> nvidia.com/gpu.present=true
#   5. (Optional, for PCI passthrough) Enable IOMMU and configure VFIO
# =============================================================================

# Variables
variable "nvidia_device_plugin_chart_version" {
  description = "NVIDIA device plugin Helm chart version"
  type        = string
  default     = "0.17.0"
}

variable "nvidia_device_plugin_enabled" {
  description = "Enable NVIDIA device plugin (set to true after GPU nodes are configured)"
  type        = bool
  default     = false
}

variable "gpu_nodes" {
  description = "Map of GPU node hostname to VRAM in GB (e.g. { \"rainbow.home\" = 16, \"celery.home\" = 12 })"
  type        = map(number)
  default     = {}
}

# Locals — VRAM tier labels
locals {
  vram_tiers = [4, 6, 8, 10, 12, 16, 24, 48]

  # For each GPU node, generate cumulative tier labels (a 12GB node satisfies 4, 6, 8, 10, 12)
  gpu_node_labels = {
    for node, vram in var.gpu_nodes : node => {
      for tier in local.vram_tiers :
      "gpu-vram-${tier}gb" => "true"
      if tier <= vram
    }
  }
}

# Node Labels — VRAM tiers (applied to existing GPU nodes)
resource "kubernetes_labels" "gpu_node_vram" {
  for_each = var.gpu_nodes

  api_version = "v1"
  kind        = "Node"

  metadata {
    name = each.key
  }

  labels = merge(
    { "nvidia.com/gpu.present" = "true" },
    local.gpu_node_labels[each.key]
  )
}

# Helm Release — NVIDIA Device Plugin
resource "helm_release" "nvidia_device_plugin" {
  count = var.nvidia_device_plugin_enabled ? 1 : 0

  depends_on = [kubernetes_labels.gpu_node_vram]

  name       = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.nvidia_device_plugin_chart_version
  namespace  = "kube-system"

  values = [
    yamlencode({
      compatWithCPUManager = false
      nodeSelector = {
        "nvidia.com/gpu.present" = "true"
      }
    })
  ]

  timeout = 300
  wait    = true
}

# Outputs
output "nvidia_device_plugin_info" {
  description = "NVIDIA device plugin information"
  value = {
    enabled       = var.nvidia_device_plugin_enabled
    chart_version = var.nvidia_device_plugin_chart_version
    gpu_nodes     = var.gpu_nodes
    vram_labels   = local.gpu_node_labels

    prerequisites = {
      step_1 = "Run scripts/x86-k8s-worker.sh --gpu on the node (installs drivers + toolkit)"
      step_2 = "Join node to cluster: x86-k8s-worker.sh --join --gpu ..."
      step_3 = "Add node to gpu_nodes in terraform.tfvars (Terraform applies labels)"
      step_4 = "Set nvidia_device_plugin_enabled = true"
    }

    commands = {
      check_plugin = "kubectl get pods -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin"
      check_gpu    = "kubectl describe node <gpu-node> | grep nvidia.com/gpu"
      check_labels = "kubectl get nodes --show-labels | grep gpu-vram"
      test_gpu     = "kubectl run gpu-test --rm -it --image=nvidia/cuda:12.4.0-base-ubuntu22.04 --limits=nvidia.com/gpu=1 -- nvidia-smi"
    }
  }
}
