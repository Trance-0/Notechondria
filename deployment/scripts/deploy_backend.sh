#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}
WAIT_SCRIPT=${3:-$PROJECT_DIR/deployment/scripts/wait_for_stack.sh}
WAIT_TIMEOUT_SECONDS=${4:-300}
DB_READY_SCRIPT=${5:-$PROJECT_DIR/deployment/scripts/ensure_db_ready.sh}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/backend"

bash "$DB_READY_SCRIPT" "$PROJECT_DIR" "$ENV_PATH" "$WAIT_TIMEOUT_SECONDS"
docker compose --env-file "$ENV_PATH" pull || true
docker compose --env-file "$ENV_PATH" up --build -d
bash "$WAIT_SCRIPT" "$PROJECT_DIR" "$ENV_PATH" "$WAIT_TIMEOUT_SECONDS"
docker compose --env-file "$ENV_PATH" exec -T app python manage.py collectstatic --noinput

echo "Deployment finished successfully."
