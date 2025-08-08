#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }

wait_for_namespace() {
  local namespace="$1"; local timeout_secs="${2:-300}"; local waited=0
  while ! kubectl get ns "$namespace" >/dev/null 2>&1; do
    sleep 2; waited=$((waited+2)); if [ "$waited" -ge "$timeout_secs" ]; then echo "Timeout waiting for namespace $namespace"; exit 1; fi
  done
}

wait_for_pods_ready() {
  local namespace="$1"; local timeout_secs="${2:-600}"; local waited=0
  # Wait for at least one pod to exist
  while true; do
    local count
    count=$(kubectl -n "$namespace" get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "${count:-0}" -gt 0 ]; then break; fi
    sleep 2; waited=$((waited+2)); if [ "$waited" -ge "$timeout_secs" ]; then echo "Timeout waiting for pods in $namespace"; exit 1; fi
  done
  kubectl -n "$namespace" wait --for=condition=Ready pods --all --timeout="${timeout_secs}s"
}

# 1) Install/upgrade cluster addons (CNI, LoadBalancer, Storage)
log "Applying addons (Flannel, MetalLB, Longhorn)"
kubectl apply -k "$SCRIPT_DIR/addons"

# 2) Wait for core addons to be ready
log "Waiting for Flannel to be Ready"
wait_for_namespace kube-flannel 300
wait_for_pods_ready kube-flannel 600

log "Waiting for MetalLB to be Ready"
wait_for_namespace metallb-system 300
wait_for_pods_ready metallb-system 600

log "Waiting for Longhorn to be Ready"
wait_for_namespace longhorn-system 600
wait_for_pods_ready longhorn-system 900

# 3) Deploy applications
log "Deploying BaGet application"
if [ -n "${BAGET_API_KEY:-}" ]; then
  BAGET_API_KEY="$BAGET_API_KEY" bash "$SCRIPT_DIR/applications/baget-deployment.sh"
else
  bash "$SCRIPT_DIR/applications/baget-deployment.sh"
fi

log "Deployment complete"