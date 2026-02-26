#!/bin/sh
set -e

echo "Starting git pull loop (interval: ${interval}s)"

while true; do
%{ for site in sites ~}
  echo "Pulling ${site.domain} (${site.branch})..."
  cd /sites/${site.domain} && git pull origin ${site.branch} 2>&1 || echo "Failed to pull ${site.domain}"
%{ endfor ~}
  sleep ${interval}
done
