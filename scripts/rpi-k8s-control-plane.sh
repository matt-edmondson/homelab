#!/bin/bash
# =============================================================================
# Raspberry Pi Kubernetes Control Plane Setup
# =============================================================================
# Run this ON the Raspberry Pi after it has booted with Raspberry Pi OS (64-bit
# Lite) and the first-boot script has run.
#
# This script:
#   1. Installs containerd as the container runtime
#   2. Installs kubeadm, kubelet, kubectl
#   3. Joins the existing cluster as a control plane node
#
# Prerequisites:
#   - Raspberry Pi OS 64-bit (Bookworm) with cgroups enabled
#   - Swap disabled (done by firstrun.sh or manually)
#   - Network connectivity to existing control plane
#   - Run as root (sudo)
#
# Usage:
#   # Initialize a NEW cluster (first control plane node):
#   sudo ./rpi-k8s-control-plane.sh --init
#
#   # Join an EXISTING cluster as control plane:
#   sudo ./rpi-k8s-control-plane.sh --join \
#     --api-server 192.168.0.40:6443 \
#     --token <bootstrap-token> \
#     --cert-hash <ca-cert-hash> \
#     --cert-key <certificate-key>
#
#   # Just install packages (don't init or join):
#   sudo ./rpi-k8s-control-plane.sh --install-only
#
# To generate join parameters on an existing control plane node:
#   sudo kubeadm token create --print-join-command
#   sudo kubeadm init phase upload-certs --upload-certs
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
KUBE_VERSION="1.32"
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"

# -----------------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------------
MODE=""
API_SERVER=""
TOKEN=""
CERT_HASH=""
CERT_KEY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --init)         MODE="init";          shift ;;
        --join)         MODE="join";           shift ;;
        --install-only) MODE="install-only";   shift ;;
        --api-server)   API_SERVER="$2";       shift 2 ;;
        --token)        TOKEN="$2";            shift 2 ;;
        --cert-hash)    CERT_HASH="$2";        shift 2 ;;
        --cert-key)     CERT_KEY="$2";         shift 2 ;;
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
    echo "ERROR: Specify --init, --join, or --install-only"
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
if [ "$ARCH" != "arm64" ]; then
    echo "WARNING: Expected arm64 architecture, got $ARCH"
fi
echo "  Architecture: $ARCH"

if swapon --show | grep -q .; then
    echo "ERROR: Swap is still enabled. Disable it first:"
    echo "  sudo swapoff -a && sudo systemctl disable dphys-swapfile"
    exit 1
fi
echo "  [OK] Swap disabled"

if ! grep -q "cgroup_enable=memory" /proc/cmdline; then
    echo "ERROR: cgroup memory not enabled in kernel cmdline."
    echo "  Add 'cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1' to /boot/firmware/cmdline.txt and reboot."
    exit 1
fi
echo "  [OK] cgroups enabled"

# Check kernel modules
modprobe overlay 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true
echo "  [OK] Kernel modules loaded"

# Verify sysctl
sysctl -w net.bridge.bridge-nf-call-iptables=1  > /dev/null 2>&1
sysctl -w net.bridge.bridge-nf-call-ip6tables=1 > /dev/null 2>&1
sysctl -w net.ipv4.ip_forward=1                 > /dev/null 2>&1
echo "  [OK] sysctl parameters set"

# -----------------------------------------------------------------------------
# Install containerd
# -----------------------------------------------------------------------------
echo ""
echo "=== Installing containerd ==="

apt-get update -qq
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg

# Install containerd from Docker's repo (has arm64 builds)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list

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
# Install kubeadm, kubelet, kubectl
# -----------------------------------------------------------------------------
echo ""
echo "=== Installing Kubernetes ${KUBE_VERSION} ==="

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v${KUBE_VERSION}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet
echo "  [OK] kubeadm, kubelet, kubectl installed (v${KUBE_VERSION})"

# -----------------------------------------------------------------------------
# Persistent sysctl and modules (ensure they survive reboot)
# -----------------------------------------------------------------------------
cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

cat > /etc/modules-load.d/kubernetes.conf << 'EOF'
overlay
br_netfilter
EOF

# -----------------------------------------------------------------------------
# Execute mode
# -----------------------------------------------------------------------------
echo ""

case "$MODE" in
    init)
        echo "=== Initializing new Kubernetes cluster ==="
        echo ""
        echo "This will create a NEW cluster. If you want to join an existing"
        echo "cluster, use --join instead."
        echo ""
        read -r -p "Continue? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi

        kubeadm init \
            --pod-network-cidr="$POD_CIDR" \
            --service-cidr="$SERVICE_CIDR" \
            --control-plane-endpoint="$(hostname -I | awk '{print $1}'):6443" \
            --upload-certs

        # Set up kubeconfig for the pi user
        PI_HOME=$(getent passwd pi | cut -d: -f6 || echo "/home/pi")
        if [ -d "$PI_HOME" ]; then
            mkdir -p "$PI_HOME/.kube"
            cp /etc/kubernetes/admin.conf "$PI_HOME/.kube/config"
            chown -R "$(id -u pi):$(id -g pi)" "$PI_HOME/.kube"
        fi

        echo ""
        echo "=== Cluster initialized ==="
        echo ""
        echo "Next steps:"
        echo "  1. Install Flannel CNI (managed by Terraform in your homelab repo)"
        echo "  2. To add more control plane nodes, run on THIS node:"
        echo "     sudo kubeadm token create --print-join-command"
        echo "     sudo kubeadm init phase upload-certs --upload-certs"
        echo "  3. Then run this script with --join on the new nodes"
        ;;

    join)
        echo "=== Joining existing cluster as control plane ==="

        if [ -z "$API_SERVER" ] || [ -z "$TOKEN" ] || [ -z "$CERT_HASH" ] || [ -z "$CERT_KEY" ]; then
            echo "ERROR: --join requires all of: --api-server, --token, --cert-hash, --cert-key"
            echo ""
            echo "Generate these on an existing control plane node:"
            echo "  sudo kubeadm token create --print-join-command"
            echo "  sudo kubeadm init phase upload-certs --upload-certs"
            exit 1
        fi

        kubeadm join "$API_SERVER" \
            --token "$TOKEN" \
            --discovery-token-ca-cert-hash "$CERT_HASH" \
            --control-plane \
            --certificate-key "$CERT_KEY"

        # Set up kubeconfig for the pi user
        PI_HOME=$(getent passwd pi | cut -d: -f6 || echo "/home/pi")
        if [ -d "$PI_HOME" ]; then
            mkdir -p "$PI_HOME/.kube"
            cp /etc/kubernetes/admin.conf "$PI_HOME/.kube/config"
            chown -R "$(id -u pi):$(id -g pi)" "$PI_HOME/.kube"
        fi

        echo ""
        echo "=== Joined cluster as control plane node ==="
        echo "Run 'kubectl get nodes' to verify."
        ;;

    install-only)
        echo "=== Install complete (no init/join) ==="
        echo ""
        echo "Packages installed: containerd, kubeadm, kubelet, kubectl"
        echo ""
        echo "To join an existing cluster as control plane, run:"
        echo "  sudo kubeadm join <api-server>:6443 \\"
        echo "    --token <token> \\"
        echo "    --discovery-token-ca-cert-hash sha256:<hash> \\"
        echo "    --control-plane \\"
        echo "    --certificate-key <cert-key>"
        echo ""
        echo "Generate join parameters on an existing control plane:"
        echo "  sudo kubeadm token create --print-join-command"
        echo "  sudo kubeadm init phase upload-certs --upload-certs"
        ;;
esac

echo ""
echo "Done."
