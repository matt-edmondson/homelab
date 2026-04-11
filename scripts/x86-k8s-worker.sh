#!/bin/bash
# =============================================================================
# x86_64 Kubernetes Worker Node Setup (with optional NVIDIA GPU)
# =============================================================================
# Run this ON the worker node after a fresh Debian/Ubuntu install.
#
# This script:
#   1. Configures kernel parameters for Kubernetes
#   2. Installs containerd as the container runtime
#   3. Installs kubeadm, kubelet, kubectl
#   4. (Optional) Installs NVIDIA driver + nvidia-container-toolkit
#   5. Joins the cluster as a worker node
#
# Prerequisites:
#   - Debian 12 (Bookworm) or Ubuntu 22.04/24.04 (x86_64)
#   - Swap disabled
#   - Network connectivity to existing control plane
#   - Run as root (sudo)
#
# Usage:
#   # Install everything + NVIDIA drivers, then join:
#   sudo ./x86-k8s-worker.sh --join --gpu \
#     --api-server 192.168.0.40:6443 \
#     --token <bootstrap-token> \
#     --cert-hash <ca-cert-hash>
#
#   # Install without GPU support:
#   sudo ./x86-k8s-worker.sh --join \
#     --api-server 192.168.0.40:6443 \
#     --token <bootstrap-token> \
#     --cert-hash <ca-cert-hash>
#
#   # Just install packages (don't join yet):
#   sudo ./x86-k8s-worker.sh --install-only --gpu
#
# To generate join parameters on an existing control plane node:
#   sudo kubeadm token create --print-join-command
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
KUBE_VERSION="1.32"

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
MODE=""
API_SERVER=""
TOKEN=""
CERT_HASH=""
GPU=false
NODE_IP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --join)           MODE="join";           shift ;;
        --install-only)   MODE="install-only";   shift ;;
        --gpu)            GPU=true;              shift ;;
        --api-server)     API_SERVER="$2";       shift 2 ;;
        --token)          TOKEN="$2";            shift 2 ;;
        --cert-hash)      CERT_HASH="$2";        shift 2 ;;
        --node-ip)        NODE_IP="$2";          shift 2 ;;
        -h|--help)
            sed -n '2,/^# =====/p' "$0" | head -n -1 | sed 's/^# //'
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$MODE" ]; then
    echo "ERROR: Specify --join or --install-only"
    echo "Run with --help for usage."
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# -----------------------------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------------------------
echo "=== Preflight checks ==="

ARCH=$(dpkg --print-architecture)
if [ "$ARCH" != "amd64" ]; then
    echo "WARNING: Expected amd64 architecture, got $ARCH"
fi
echo "  Architecture: $ARCH"

if swapon --show | grep -q .; then
    echo "Disabling swap..."
    swapoff -a
    # Comment out swap entries in fstab
    sed -i '/\sswap\s/s/^/#/' /etc/fstab
    echo "  [OK] Swap disabled"
else
    echo "  [OK] Swap already disabled"
fi

# Load and persist kernel modules
modprobe overlay 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true
echo "  [OK] Kernel modules loaded"

cat > /etc/modules-load.d/kubernetes.conf << 'EOF'
overlay
br_netfilter
EOF

# Set and persist sysctl parameters
cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system > /dev/null 2>&1
echo "  [OK] sysctl parameters set"

# -----------------------------------------------------------------------------
# Install containerd
# -----------------------------------------------------------------------------
echo ""
echo "=== Installing containerd ==="

apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg

# Docker repo for containerd
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
fi

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq containerd.io

# Configure containerd with systemd cgroup driver
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
echo "  [OK] containerd installed and configured"

# -----------------------------------------------------------------------------
# Install NVIDIA drivers + container toolkit (optional)
# -----------------------------------------------------------------------------
if [ "$GPU" = true ]; then
    echo ""
    echo "=== Installing NVIDIA drivers + container toolkit ==="

    # Detect distro for NVIDIA repo
    DISTRO=$(. /etc/os-release; echo "${ID}${VERSION_ID}" | sed 's/\.//')

    # Install NVIDIA driver (if not already present)
    if ! command -v nvidia-smi &> /dev/null; then
        echo "  Installing NVIDIA driver..."

        # For Debian, use the non-free firmware repo
        if [ "$(. /etc/os-release && echo "$ID")" = "debian" ]; then
            apt-get install -y -qq linux-headers-$(uname -r)
            # Add non-free repo if not present
            if ! grep -q "non-free" /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null; then
                sed -i 's/main$/main contrib non-free non-free-firmware/' /etc/apt/sources.list
                apt-get update -qq
            fi
            apt-get install -y -qq nvidia-driver firmware-misc-nonfree
        else
            # Ubuntu — use the ubuntu-drivers tool
            apt-get install -y -qq ubuntu-drivers-common
            ubuntu-drivers install
        fi
        echo "  [OK] NVIDIA driver installed (reboot may be required)"
    else
        echo "  [SKIP] NVIDIA driver already installed"
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader
    fi

    # Install nvidia-container-toolkit
    if [ ! -f /etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg ]; then
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg
    fi

    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
        | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
        > /etc/apt/sources.list.d/nvidia-container-toolkit.list

    apt-get update -qq
    apt-get install -y -qq nvidia-container-toolkit
    echo "  [OK] nvidia-container-toolkit installed"

    # Configure containerd to use the NVIDIA runtime
    nvidia-ctk runtime configure --runtime=containerd
    systemctl restart containerd
    echo "  [OK] containerd configured with NVIDIA runtime"

    # Add NVIDIA kernel modules to load on boot
    cat > /etc/modules-load.d/nvidia.conf << 'EOF'
nvidia
nvidia_uvm
nvidia_modeset
EOF

    # Blacklist nouveau
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    echo "  [OK] nouveau blacklisted"
fi

# -----------------------------------------------------------------------------
# Install kubeadm, kubelet, kubectl
# -----------------------------------------------------------------------------
echo ""
echo "=== Installing Kubernetes ${KUBE_VERSION} ==="

if [ ! -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key" \
        | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
fi

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet
echo "  [OK] kubeadm, kubelet, kubectl installed (v${KUBE_VERSION})"

# -----------------------------------------------------------------------------
# Set node-ip if specified
# -----------------------------------------------------------------------------
if [ -n "$NODE_IP" ]; then
    echo "KUBELET_EXTRA_ARGS=--node-ip=$NODE_IP" > /etc/default/kubelet
    systemctl restart kubelet
    echo "  [OK] kubelet node-ip set to $NODE_IP"
fi

# -----------------------------------------------------------------------------
# Execute mode
# -----------------------------------------------------------------------------
echo ""

case "$MODE" in
    join)
        echo "=== Joining cluster as worker node ==="

        if [ -z "$API_SERVER" ] || [ -z "$TOKEN" ] || [ -z "$CERT_HASH" ]; then
            echo "ERROR: --join requires: --api-server, --token, --cert-hash"
            echo ""
            echo "Generate these on an existing control plane node:"
            echo "  sudo kubeadm token create --print-join-command"
            exit 1
        fi

        kubeadm join "$API_SERVER" \
            --token "$TOKEN" \
            --discovery-token-ca-cert-hash "$CERT_HASH"

        echo ""
        echo "=== Joined cluster as worker node ==="
        echo ""
        echo "From a control plane node, verify with:"
        echo "  kubectl get nodes"

        if [ "$GPU" = true ]; then
            echo ""
            echo "GPU post-join steps:"
            echo "  1. Label this node:  kubectl label node $(hostname) nvidia.com/gpu.present=true"
            echo "  2. Verify GPU:       kubectl describe node $(hostname) | grep nvidia.com/gpu"
        fi
        ;;

    install-only)
        echo "=== Install complete (no join) ==="
        echo ""
        echo "Packages installed: containerd, kubeadm, kubelet, kubectl"
        if [ "$GPU" = true ]; then
            echo "GPU packages installed: nvidia-driver, nvidia-container-toolkit"
            echo ""
            echo "IMPORTANT: If this is the first NVIDIA driver install, reboot before joining:"
            echo "  sudo reboot"
        fi
        echo ""
        echo "To join as a worker node, run:"
        echo "  sudo kubeadm join <api-server>:6443 \\"
        echo "    --token <token> \\"
        echo "    --discovery-token-ca-cert-hash sha256:<hash>"
        echo ""
        echo "Generate join parameters on an existing control plane:"
        echo "  sudo kubeadm token create --print-join-command"

        if [ "$GPU" = true ]; then
            echo ""
            echo "After joining, label this node for GPU scheduling:"
            echo "  kubectl label node $(hostname) nvidia.com/gpu.present=true"
        fi
        ;;
esac

echo ""
echo "Done."
