#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

generate_random_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32 | tr -d '\n'
  elif command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -NonInteractive -Command "[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))"
  elif [ -r /dev/urandom ] && command -v base64 >/dev/null 2>&1; then
    head -c 32 /dev/urandom | base64 | tr -d '\n'
  elif command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr -d '\n'
  else
    date +%s%N | sha256sum | awk '{print $1}'
  fi
}

BAGET_API_KEY="${BAGET_API_KEY:-$(generate_random_key)}"

# MetalLB parameters (override via env):
BAGET_LB_POOL_NAME="${BAGET_LB_POOL_NAME:-baget-pool}"
BAGET_LB_RANGE="${BAGET_LB_RANGE:-192.168.1.240-192.168.1.250}"
BAGET_LOADBALANCER_IP="${BAGET_LOADBALANCER_IP:-}"

kubectl apply -f "$SCRIPT_DIR/baget-deployment.yaml"
kubectl -n baget delete secret baget-secrets --ignore-not-found
kubectl -n baget create secret generic baget-secrets --from-literal=ApiKey="$BAGET_API_KEY"
kubectl -n baget rollout restart deploy/baget
echo "BaGet ApiKey: $BAGET_API_KEY"

echo "Ensuring MetalLB is installed..."
kubectl get ns metallb-system >/dev/null 2>&1 || kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml

if ! kubectl -n metallb-system get ipaddresspool "$BAGET_LB_POOL_NAME" >/dev/null 2>&1; then
  cat <<'YAML' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: REPLACE_POOL_NAME
  namespace: metallb-system
spec:
  addresses:
    - REPLACE_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: REPLACE_POOL_NAME-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - REPLACE_POOL_NAME
YAML
  # replace placeholders
  kubectl -n metallb-system get ipaddresspool "$BAGET_LB_POOL_NAME" >/dev/null 2>&1 || true
  # The heredoc applied already; no replacement needed in-cluster.
fi

echo "Annotating Service with MetalLB pool '$BAGET_LB_POOL_NAME'..."
kubectl -n baget annotate service baget-service metallb.universe.tf/address-pool="$BAGET_LB_POOL_NAME" --overwrite

if [ -n "$BAGET_LOADBALANCER_IP" ]; then
  echo "Setting static LoadBalancer IP: $BAGET_LOADBALANCER_IP"
  kubectl -n baget patch service baget-service -p "{\"spec\":{\"loadBalancerIP\":\"$BAGET_LOADBALANCER_IP\"}}"
fi

echo "Waiting for external IP from MetalLB..."
for i in {1..60}; do
  EXTERNAL_IP=$(kubectl -n baget get svc baget-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true)
  if [ -n "$EXTERNAL_IP" ]; then echo "BaGet Service External IP: $EXTERNAL_IP"; break; fi
  sleep 2
done
if [ -z "${EXTERNAL_IP:-}" ]; then echo "Timed out waiting for external IP"; exit 1; fi