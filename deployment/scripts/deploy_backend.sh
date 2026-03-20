#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/backend"

docker compose --env-file "$ENV_PATH" pull || true
docker compose --env-file "$ENV_PATH" up --build -d
docker compose --env-file "$ENV_PATH" exec -T app python manage.py collectstatic --noinput

echo "Deployment finished successfully."
