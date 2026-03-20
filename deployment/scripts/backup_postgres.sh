#!/usr/bin/env bash
set -euo pipefail

ENV_PATH=${1:-.env}
BACKUP_DIR=${2:-./backups}
PROJECT_DIR=${3:-$(pwd)}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/notechondria_${TIMESTAMP}.sql"

cd "$PROJECT_DIR/backend"

docker compose --env-file "$ENV_PATH" up -d db
docker compose --env-file "$ENV_PATH" exec -T db sh -lc '
  until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
    sleep 1
  done
'

if ! docker compose --env-file "$ENV_PATH" exec -T db sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select 1"' >/dev/null 2>&1; then
  cat <<EOF
Skipping backup because PostgreSQL is not initialized for the configured role/database yet.
Configured values come from the Docker Compose environment file:
$ENV_PATH

This usually means the persistent Docker volume was initialized earlier with different POSTGRE_* values.
Either:
1. update the Jenkins env credential to match the existing database role/database, or
2. recreate the postgres volume for a fresh cluster initialization.

If this is the first deployment, this skip is expected and the pipeline should continue.
If you want a fresh test stack, remove the existing Docker volume for this stack and rerun the pipeline.
EOF
  exit 0
fi

docker compose --env-file "$ENV_PATH" exec -T db sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p' > "$BACKUP_FILE"

echo "Backup created at $BACKUP_FILE"
