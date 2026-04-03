#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/.env.deploy}"
cd "$ROOT_DIR"
docker compose --env-file "$ENV_FILE" up --build -d
sleep 10
docker compose exec -T app python manage.py migrate --noinput
docker compose exec -T app python manage.py bootstrap_platform || true
docker compose exec -T app python manage.py collectstatic --noinput --clear
