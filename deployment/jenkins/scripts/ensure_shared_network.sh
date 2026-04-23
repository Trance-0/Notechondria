#!/usr/bin/env bash
set -euo pipefail

ENV_PATH=${1:-.env}

if [[ -f "$ENV_PATH" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$ENV_PATH"
  set +a
fi

NETWORK_NAME=${NOTECHONDRIA_SHARED_NETWORK:-notechondria-shared}

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "Shared Docker network already exists: $NETWORK_NAME"
else
  docker network create "$NETWORK_NAME" >/dev/null
  echo "Created shared Docker network: $NETWORK_NAME"
fi
