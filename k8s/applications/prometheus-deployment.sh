#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reuse existing Service External IP (VIP) if present
EXISTING_EXT_IP=""
if kubectl -n prometheus get svc prometheus-service >/dev/null 2>&1; then
  EXISTING_EXT_IP=$(kubectl -n prometheus get svc prometheus-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -z "$EXISTING_EXT_IP" ]; then
    EXISTING_EXT_IP=$(kubectl -n prometheus get svc prometheus-service -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null || true)
  fi
fi

kubectl apply -f "$SCRIPT_DIR/prometheus-deployment.yaml"

if [ -n "$EXISTING_EXT_IP" ]; then
  echo "Reusing existing Service External IP: $EXISTING_EXT_IP"
  kubectl -n prometheus patch service prometheus-service -p "{\"spec\":{\"loadBalancerIP\":\"$EXISTING_EXT_IP\"}}" >/dev/null || true
fi

echo "Waiting for external IP from MetalLB..."
for i in {1..60}; do
  EXTERNAL_IP=$(kubectl -n prometheus get svc prometheus-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' || true)
  if [ -n "$EXTERNAL_IP" ]; then echo "Prometheus Service External IP: $EXTERNAL_IP"; break; fi
  sleep 2
done
if [ -z "${EXTERNAL_IP:-}" ]; then echo "Timed out waiting for external IP"; exit 1; fi


