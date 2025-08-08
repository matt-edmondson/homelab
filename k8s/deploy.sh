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

get_service_external_address() {
  local namespace="$1"; local service_name="$2"; local timeout_secs="${3:-300}"; local waited=0
  while true; do
    local ip
    local host
    ip=$(kubectl -n "$namespace" get svc "$service_name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    host=$(kubectl -n "$namespace" get svc "$service_name" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [ -n "${ip:-}" ] || [ -n "${host:-}" ]; then
      if [ -n "${ip:-}" ]; then echo "$ip"; else echo "$host"; fi
      return 0
    fi
    sleep 2; waited=$((waited+2)); if [ "$waited" -ge "$timeout_secs" ]; then return 1; fi
  done
}

apply_with_retry() {
  local file="$1"; local attempts="${2:-10}"; local delay_secs="${3:-6}"
  local i=1
  for ((i=1; i<=attempts; i++)); do
    if kubectl apply -f "$file"; then return 0; fi
    sleep "$delay_secs"
  done
  echo "Failed to apply $file after $attempts attempts"; return 1
}

# Pre-scan: Reuse existing Kubernetes Dashboard Service external IP if present (before applying)
DASHBOARD_EXISTING_EXT_IP=""
if kubectl -n kubernetes-dashboard get svc kubernetes-dashboard >/dev/null 2>&1; then
  DASHBOARD_EXISTING_EXT_IP=$(kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -z "$DASHBOARD_EXISTING_EXT_IP" ]; then
    DASHBOARD_EXISTING_EXT_IP=$(kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o jsonpath='{.spec.loadBalancerIP}' 2>/dev/null || true)
  fi
fi
# If user provided DASHBOARD_ADDR and it looks like an IPv4, prefer it for pinning
if [ -n "${DASHBOARD_ADDR:-}" ] && [[ "$DASHBOARD_ADDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  DASHBOARD_EXISTING_EXT_IP="$DASHBOARD_ADDR"
fi

# 1) Install/upgrade cluster addons
log "Applying addons"
kubectl apply -k "$SCRIPT_DIR/addons"

# 2) Wait for core addons to be ready
log "Waiting for Flannel to be Ready"
wait_for_namespace kube-flannel 300
wait_for_pods_ready kube-flannel 600

log "Waiting for MetalLB to be Ready"
wait_for_namespace metallb-system 300
wait_for_pods_ready metallb-system 600

# 2b) Apply MetalLB address pool after controller/webhooks are ready
if [ -f "$SCRIPT_DIR/addons/metallb-config.yaml" ]; then
  log "Applying MetalLB address pool configuration"
  apply_with_retry "$SCRIPT_DIR/addons/metallb-config.yaml" 15 4
fi

log "Waiting for Longhorn to be Ready"
wait_for_namespace longhorn-system 600
wait_for_pods_ready longhorn-system 900

# 2c) Wait for Kubernetes Dashboard (if included in addons)
if kubectl get ns kubernetes-dashboard >/dev/null 2>&1; then
  # If we had a prior external IP, pin it so the LB address remains stable
  if [ -n "${DASHBOARD_EXISTING_EXT_IP:-}" ]; then
    log "Reusing existing Dashboard Service External IP: ${DASHBOARD_EXISTING_EXT_IP}"
    # Wait briefly for the service object to exist, then patch
    for i in {1..60}; do
      if kubectl -n kubernetes-dashboard get svc kubernetes-dashboard >/dev/null 2>&1; then
        kubectl -n kubernetes-dashboard patch service kubernetes-dashboard -p "{\"spec\":{\"loadBalancerIP\":\"${DASHBOARD_EXISTING_EXT_IP}\"}}" >/dev/null 2>&1 || true
        break
      fi
      sleep 2
    done
  fi
  log "Waiting for Kubernetes Dashboard to be Ready"
  wait_for_namespace kubernetes-dashboard 300
  wait_for_pods_ready kubernetes-dashboard 600
  log "Waiting for Kubernetes Dashboard LoadBalancer address (via MetalLB)"
  if [ -n "${DASHBOARD_ADDR:-}" ]; then
    log "Using existing DASHBOARD_ADDR=${DASHBOARD_ADDR}"
  else
    DASHBOARD_ADDR=$(get_service_external_address kubernetes-dashboard kubernetes-dashboard 600 || true)
  fi
  if [ -n "${DASHBOARD_ADDR:-}" ]; then
    log "Kubernetes Dashboard available at: https://${DASHBOARD_ADDR}/"
  else
    log "Kubernetes Dashboard LoadBalancer address not assigned yet. You can also use kubectl proxy to access it locally."
  fi
  if [ -n "${DASHBOARD_TOKEN:-}" ]; then
    log "Using existing DASHBOARD_TOKEN for authentication"
  else
    log "To create an admin login token: kubectl -n kubernetes-dashboard create token dashboard-admin-sa"
  fi
fi

# 3) Deploy applications
log "Deploying BaGet application"
if [ -n "${BAGET_API_KEY:-}" ]; then
  BAGET_API_KEY="$BAGET_API_KEY" bash "$SCRIPT_DIR/applications/baget-deployment.sh"
else
  bash "$SCRIPT_DIR/applications/baget-deployment.sh"
fi

log "Deploying Prometheus"
bash "$SCRIPT_DIR/applications/prometheus-deployment.sh"

log "Deployment complete"