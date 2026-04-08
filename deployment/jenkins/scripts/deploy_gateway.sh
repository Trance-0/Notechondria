#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/.env.deploy}"
NETWORK_SCRIPT="${ROOT_DIR}/deployment/jenkins/scripts/ensure_shared_network.sh"

bash "$NETWORK_SCRIPT" "$ENV_FILE"

cd "$ROOT_DIR/deployment/docker/gateway"
docker compose --env-file "$ENV_FILE" up -d --force-recreate
