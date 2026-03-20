#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/backend"

docker compose --env-file "$ENV_PATH" build app
docker compose --env-file "$ENV_PATH" run --rm --no-deps --entrypoint sh app -lc 'python manage.py test --settings=notechondria.settings_test'
