#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}
TIMEOUT_SECONDS=${3:-300}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/backend"

get_auto_reinit() {
  awk -F= '$1=="DB_AUTO_REINIT_IF_MISMATCH" {print $2}' "$ENV_PATH" | tail -n 1
}

wait_for_db() {
  local start_time
  start_time=$(date +%s)

  docker compose --env-file "$ENV_PATH" up -d db

  while true; do
    if docker compose --env-file "$ENV_PATH" exec -T db sh -lc 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1; then
      return 0
    fi

    if [[ $(( $(date +%s) - start_time )) -ge "$TIMEOUT_SECONDS" ]]; then
      echo "Timed out waiting for database readiness after ${TIMEOUT_SECONDS}s"
      return 1
    fi

    sleep 2
  done
}

db_auth_works() {
  docker compose --env-file "$ENV_PATH" exec -T db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select 1"' >/dev/null 2>&1
}

if ! wait_for_db; then
  docker compose --env-file "$ENV_PATH" logs --tail=200 db || true
  exit 1
fi

if db_auth_works; then
  echo "Database is reachable with the configured credentials."
  exit 0
fi

if [[ "$(get_auto_reinit)" == "True" ]]; then
  echo "Configured database credentials do not match the existing cluster. Reinitializing postgres volume because DB_AUTO_REINIT_IF_MISMATCH=True."
  docker compose --env-file "$ENV_PATH" down --remove-orphans || true
  docker volume rm notechondria_postgres-data || true

  if ! wait_for_db; then
    docker compose --env-file "$ENV_PATH" logs --tail=200 db || true
    exit 1
  fi

  if db_auth_works; then
    echo "Database was reinitialized and is now reachable."
    exit 0
  fi
fi

cat <<EOF
Database credentials do not match the existing postgres cluster.

This repository uses a persistent Docker volume for postgres. The current volume was initialized with different credentials or role names.

Options:
1. Update Jenkins Environment Injector properties to match the existing database role/password/database.
2. For disposable environments, set DB_AUTO_REINIT_IF_MISMATCH=True to recreate the postgres volume automatically.
3. Manually remove the docker volume notechondria_postgres-data and rerun the pipeline.
EOF
exit 1
