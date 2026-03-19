#!/bin/bash
# =============================================================================
# Raspberry Pi SD Card Preparation Script
# =============================================================================
# Run this on your workstation AFTER flashing Raspberry Pi OS (64-bit Lite)
# onto the SD card using Raspberry Pi Imager.
#
# This script writes cloud-init / first-boot configuration to the SD card's
# boot partition so the Pi comes up ready for Kubernetes.
#
# Usage:
#   ./rpi-prepare-sd.sh <boot-partition-path> <hostname> [static-ip]
#
# Examples:
#   ./rpi-prepare-sd.sh /mnt/d rpi-cp1 192.168.0.50
#   ./rpi-prepare-sd.sh /Volumes/bootfs rpi-cp1 192.168.0.50
# =============================================================================

set -euo pipefail

BOOT_PATH="${1:?Usage: $0 <boot-partition-path> <hostname> [static-ip]}"
HOSTNAME="${2:?Usage: $0 <boot-partition-path> <hostname> [static-ip]}"
STATIC_IP="${3:-}"

if [ ! -d "$BOOT_PATH" ]; then
    echo "ERROR: Boot partition not found at $BOOT_PATH"
    exit 1
fi

echo "=== Preparing SD card for: $HOSTNAME ==="

# Enable SSH on first boot
touch "$BOOT_PATH/ssh"
echo "  [OK] SSH enabled"

# Set hostname
echo "$HOSTNAME" > "$BOOT_PATH/hostname.txt"
echo "  [OK] Hostname set to $HOSTNAME"

# Configure kernel parameters for Kubernetes (cgroups memory)
# Raspberry Pi OS uses cmdline.txt for kernel boot parameters
CMDLINE="$BOOT_PATH/cmdline.txt"
if [ -f "$CMDLINE" ]; then
    # Add cgroup parameters if not already present
    if ! grep -q "cgroup_enable=memory" "$CMDLINE"; then
        sed -i 's/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/' "$CMDLINE"
        echo "  [OK] cgroup kernel parameters added to cmdline.txt"
    else
        echo "  [SKIP] cgroup parameters already present"
    fi
else
    echo "WARNING: cmdline.txt not found at $CMDLINE"
fi

# Write first-boot script that will run on the Pi
cat > "$BOOT_PATH/firstrun.sh" << 'FIRSTRUN'
#!/bin/bash
# First-boot configuration for Kubernetes control plane node
set -euo pipefail

HOSTNAME_FILE="/boot/firmware/hostname.txt"
if [ -f "$HOSTNAME_FILE" ]; then
    NEW_HOSTNAME=$(cat "$HOSTNAME_FILE")
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "127.0.1.1 $NEW_HOSTNAME" >> /etc/hosts
fi

# Set timezone
timedatectl set-timezone Australia/Melbourne

# Disable swap permanently (required for Kubernetes)
swapoff -a
systemctl disable dphys-swapfile.service
apt-get purge -y dphys-swapfile
rm -f /var/swap

# Enable IP forwarding and bridge-nf-call
cat > /etc/sysctl.d/99-kubernetes.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# Load required kernel modules on boot
cat > /etc/modules-load.d/kubernetes.conf << 'EOF'
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

# Remove this script so it doesn't run again
rm -f /boot/firmware/firstrun.sh
rm -f /boot/firmware/hostname.txt

echo "First-boot configuration complete. Reboot recommended."
FIRSTRUN

chmod +x "$BOOT_PATH/firstrun.sh"
echo "  [OK] First-boot script written"

# If a static IP was provided, write a network config hint file
if [ -n "$STATIC_IP" ]; then
    cat > "$BOOT_PATH/static-ip.txt" << EOF
# Apply this network configuration on the Pi after first boot:
# Edit /etc/dhcpcd.conf and add:
interface eth0
static ip_address=${STATIC_IP}/24
static routers=192.168.0.1
static domain_name_servers=192.168.0.1
EOF
    echo "  [OK] Static IP hint written ($STATIC_IP)"
fi

echo ""
echo "=== SD card prepared ==="
echo ""
echo "Next steps:"
echo "  1. Insert SD card into the Pi and boot it"
echo "  2. SSH in: ssh pi@${STATIC_IP:-$HOSTNAME.local}"
echo "  3. Run firstrun.sh if it didn't auto-execute:"
echo "     sudo bash /boot/firmware/firstrun.sh && sudo reboot"
echo "  4. After reboot, run rpi-k8s-control-plane.sh on the Pi"
