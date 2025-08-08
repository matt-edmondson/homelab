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

# Reuse existing API key if present, unless overridden via BAGET_API_KEY
EXISTING_API_KEY=""
if kubectl -n baget get secret baget-secrets >/dev/null 2>&1; then
  EXISTING_API_KEY=$(kubectl -n baget get secret baget-secrets -o jsonpath='{.data.ApiKey}' 2>/dev/null | base64 -d 2>/dev/null | tr -d '\n' || true)
fi

if [ -n "${BAGET_API_KEY:-}" ]; then
  EFFECTIVE_API_KEY="$BAGET_API_KEY"
elif [ -n "$EXISTING_API_KEY" ]; then
  EFFECTIVE_API_KEY="$EXISTING_API_KEY"
else
  EFFECTIVE_API_KEY="$(generate_random_key)"
fi

# Reuse existing Service External IP (VIP) if present
EXISTING_EXT_IP=""
if kubectl -n baget get svc baget-service >/dev/null 2>&1; then
  # Prefer the last assigned external IP reported by MetalLB
  EXISTING_EXT_IP=$(kubectl -n baget get svc baget-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  # Fallback to spec.loadBalancerIP if it was pinned previously
  if [ -z "$EXISTING_EXT_IP" ]; then
    EXISTING_EXT_IP=$(kubectl -n baget get svc baget-service -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null || true)
  fi
fi

kubectl apply -f "$SCRIPT_DIR/baget-deployment.yaml"

# If we had a prior external IP, pin it so NGINX upstream stays stable
if [ -n "$EXISTING_EXT_IP" ]; then
  echo "Reusing existing Service External IP: $EXISTING_EXT_IP"
  kubectl -n baget patch service baget-service -p "{\"spec\":{\"loadBalancerIP\":\"$EXISTING_EXT_IP\"}}" >/dev/null || true
fi

cat <<YAML | kubectl -n baget apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: baget-secrets
type: Opaque
stringData:
  ApiKey: "$EFFECTIVE_API_KEY"
YAML
kubectl -n baget rollout restart deploy/baget
echo "BaGet ApiKey: $EFFECTIVE_API_KEY"

echo "Waiting for external IP from MetalLB..."
for i in {1..60}; do
  EXTERNAL_IP=$(kubectl -n baget get svc baget-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true)
  if [ -n "$EXTERNAL_IP" ]; then echo "BaGet Service External IP: $EXTERNAL_IP"; break; fi
  sleep 2
done
if [ -z "${EXTERNAL_IP:-}" ]; then echo "Timed out waiting for external IP"; exit 1; fi