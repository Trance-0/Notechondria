#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/.env.deploy}"
NETWORK_SCRIPT="${ROOT_DIR}/deployment/jenkins/scripts/ensure_shared_network.sh"

bash "$NETWORK_SCRIPT" "$ENV_FILE"

for app in editor_app planner_app portal_app; do
  cd "$ROOT_DIR/frontend/$app"
  docker compose --env-file "$ENV_FILE" up --build -d
done
