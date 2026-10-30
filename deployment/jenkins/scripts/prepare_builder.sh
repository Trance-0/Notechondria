#!/usr/bin/env bash
set -Eeuo pipefail
# One capped BuildKit worker serializes expensive build stages across this stack.
AVAILABLE_KB=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
if (( AVAILABLE_KB < 12000000 )); then
  echo 'Deployment blocked: Jenkins.Build/resources — less than 12 GB RAM is available for the 8 GB build worker.' >&2
  exit 1
fi
if ! docker buildx inspect notechondria-local >/dev/null 2>&1; then
  docker buildx create --name notechondria-local --driver docker-container \
    --driver-opt memory=8g,cpu-period=100000,cpu-quota=400000,default-load=true \
    --buildkitd-flags '--oci-max-parallelism=1'
fi
timeout 3m docker buildx inspect notechondria-local --bootstrap
