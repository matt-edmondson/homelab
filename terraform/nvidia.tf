# =============================================================================
# NVIDIA Device Plugin — GPU Resource Scheduling
# =============================================================================
# Deploys the NVIDIA device plugin as a DaemonSet via Helm. This detects GPUs
# on K8s nodes and exposes them as schedulable `nvidia.com/gpu` resources.
#
# Prerequisites (manual, not Terraform-managed):
#   1. Enable IOMMU on Proxmox host: intel_iommu=on iommu=pt
#   2. Blacklist nouveau: /etc/modprobe.d/blacklist.conf
#   3. Configure VFIO for RTX 2060 PCI passthrough
#   4. Pass GPU to K8s node VM via Proxmox UI
#   5. Install nvidia-driver + nvidia-container-toolkit in guest VM
# =============================================================================

# Variables
variable "nvidia_device_plugin_chart_version" {
  description = "NVIDIA device plugin Helm chart version"
  type        = string
  default     = "0.17.0"
}

variable "nvidia_device_plugin_enabled" {
  description = "Enable NVIDIA device plugin (set to true after GPU passthrough is configured)"
  type        = bool
  default     = false
}

# Helm Release — NVIDIA Device Plugin
resource "helm_release" "nvidia_device_plugin" {
  count = var.nvidia_device_plugin_enabled ? 1 : 0

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

    prerequisites = {
      step_1 = "Enable IOMMU: add 'intel_iommu=on iommu=pt' to Proxmox host kernel cmdline"
      step_2 = "Blacklist nouveau: echo 'blacklist nouveau' >> /etc/modprobe.d/blacklist.conf && update-initramfs -u"
      step_3 = "Configure VFIO: bind RTX 2060 PCI IDs to vfio-pci driver"
      step_4 = "Pass GPU to K8s node VM via Proxmox UI"
      step_5 = "Install nvidia-driver + nvidia-container-toolkit in guest VM"
      step_6 = "Label GPU node: kubectl label node <node> nvidia.com/gpu.present=true"
    }

    commands = {
      check_plugin = "kubectl get pods -n kube-system -l app.kubernetes.io/name=nvidia-device-plugin"
      check_gpu    = "kubectl describe node <gpu-node> | grep nvidia.com/gpu"
      test_gpu     = "kubectl run gpu-test --rm -it --image=nvidia/cuda:12.4.0-base-ubuntu22.04 --limits=nvidia.com/gpu=1 -- nvidia-smi"
    }
  }
}
