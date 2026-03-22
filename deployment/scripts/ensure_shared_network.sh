#!/usr/bin/env bash
set -euo pipefail

ENV_PATH=${1:-}
NETWORK_NAME=${2:-}

if [[ -z "$NETWORK_NAME" && -n "$ENV_PATH" && -f "$ENV_PATH" ]]; then
  NETWORK_NAME=$(grep -E '^NOTECHONDRIA_SHARED_NETWORK=' "$ENV_PATH" | tail -n 1 | cut -d= -f2- | tr -d '\r')
fi

NETWORK_NAME=${NETWORK_NAME:-notechondria-shared}

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Docker shared network already exists: $NETWORK_NAME"
  exit 0
fi

docker network create "$NETWORK_NAME" >/dev/null
echo "Created Docker shared network: $NETWORK_NAME"
