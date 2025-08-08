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

kubectl apply -f "$SCRIPT_DIR/baget-deployment.yaml"
kubectl -n baget delete secret baget-secrets --ignore-not-found
kubectl -n baget create secret generic baget-secrets --from-literal=ApiKey="$BAGET_API_KEY"
kubectl -n baget rollout restart deploy/baget
echo "BaGet ApiKey: $BAGET_API_KEY"