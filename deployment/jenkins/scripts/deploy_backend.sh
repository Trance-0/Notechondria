#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}
WAIT_SCRIPT=${3:-$PROJECT_DIR/deployment/jenkins/scripts/wait_for_stack.sh}
WAIT_TIMEOUT_SECONDS=${4:-300}
DB_READY_SCRIPT=${5:-$PROJECT_DIR/deployment/jenkins/scripts/ensure_db_ready.sh}
NETWORK_SCRIPT=${6:-$PROJECT_DIR/deployment/jenkins/scripts/ensure_shared_network.sh}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/backend"

bash "$NETWORK_SCRIPT" "$ENV_PATH"
bash "$DB_READY_SCRIPT" "$PROJECT_DIR" "$ENV_PATH" "$WAIT_TIMEOUT_SECONDS"
docker compose --env-file "$ENV_PATH" build --pull --no-cache app nginx
docker compose --env-file "$ENV_PATH" up -d --force-recreate
bash "$WAIT_SCRIPT" "$PROJECT_DIR" "$ENV_PATH" "$WAIT_TIMEOUT_SECONDS"
docker compose --env-file "$ENV_PATH" exec -T app python manage.py migrate --noinput
docker compose --env-file "$ENV_PATH" exec -T app python manage.py bootstrap_platform
docker compose --env-file "$ENV_PATH" exec -T app python manage.py collectstatic --noinput --clear
bash "$WAIT_SCRIPT" "$PROJECT_DIR" "$ENV_PATH" "$WAIT_TIMEOUT_SECONDS"

echo "Deployment finished successfully."
