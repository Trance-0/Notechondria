#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}
WAIT_SCRIPT=${3:-$PROJECT_DIR/deployment/scripts/wait_for_frontend.sh}
WAIT_TIMEOUT_SECONDS=${4:-300}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/frontend"

docker compose --env-file "$ENV_PATH" build --pull --no-cache frontend
docker compose --env-file "$ENV_PATH" up -d --force-recreate frontend
bash "$WAIT_SCRIPT" "$PROJECT_DIR" "$ENV_PATH" "$WAIT_TIMEOUT_SECONDS"

echo "Frontend deployment finished successfully."
