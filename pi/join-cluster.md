# Joining the Kubernetes Cluster

After cloud-init completes and the Pi reboots, follow these steps.

## On the Pi (SSH in as matt)

### 1. Set kubelet node-ip to WiFi address

```bash
WIFI_IP=$(ip -4 addr show wlan0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "KUBELET_EXTRA_ARGS=--node-ip=$WIFI_IP" | sudo tee /etc/default/kubelet
sudo systemctl restart kubelet
```

### 2. (Pi 5 only) Verify NVMe mount and etcd symlink

```bash
df -h /data
ls -la /var/lib/etcd
```

You should see `/dev/nvme0n1` mounted at `/data` and `/var/lib/etcd -> /data/etcd`.

## On an existing control plane node

### 3. Generate join credentials

```bash
# Get the join command with token
kubeadm token create --print-join-command

# Upload certs and get certificate key
sudo kubeadm init phase upload-certs --upload-certs
```

## Back on the Pi

### 4. Join as control plane

Combine the outputs from step 3 into a single command:

```bash
sudo kubeadm join <api-server>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <certificate-key>
```

The `node-role.kubernetes.io/control-plane:NoSchedule` taint is applied automatically.

### 5. Verify

```bash
kubectl get nodes
```

Both pi4 and pi5 should appear with role `control-plane` and status `Ready`.
