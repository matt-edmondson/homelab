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

# Reuse existing external IP if present
EXISTING_LB_IP=""
if kubectl -n baget get svc baget-service >/dev/null 2>&1; then
  EXISTING_LB_IP=$(kubectl -n baget get svc baget-service -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null || true)
  if [ -z "$EXISTING_LB_IP" ]; then
    EXISTING_LB_IP=$(kubectl -n baget get svc baget-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  fi
fi

kubectl apply -f "$SCRIPT_DIR/baget-deployment.yaml"

# If we had a prior IP, pin it so NGINX upstream stays stable
if [ -n "$EXISTING_LB_IP" ]; then
  echo "Reusing existing LoadBalancer IP: $EXISTING_LB_IP"
  kubectl -n baget patch service baget-service -p "{\"spec\":{\"loadBalancerIP\":\"$EXISTING_LB_IP\"}}" >/dev/null || true
fi
kubectl -n baget delete secret baget-secrets --ignore-not-found
kubectl -n baget create secret generic baget-secrets --from-literal=ApiKey="$BAGET_API_KEY"
kubectl -n baget rollout restart deploy/baget
echo "BaGet ApiKey: $BAGET_API_KEY"

echo "Waiting for external IP from MetalLB..."
for i in {1..60}; do
  EXTERNAL_IP=$(kubectl -n baget get svc baget-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true)
  if [ -n "$EXTERNAL_IP" ]; then echo "BaGet Service External IP: $EXTERNAL_IP"; break; fi
  sleep 2
done
if [ -z "${EXTERNAL_IP:-}" ]; then echo "Timed out waiting for external IP"; exit 1; fi