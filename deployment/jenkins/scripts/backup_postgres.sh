#!/usr/bin/env bash
set -euo pipefail
umask 077

ENV_PATH=${1:-.env}
BACKUP_DIR=${2:-./backups}
PROJECT_DIR=${3:-$(pwd)}
export ENV_FILE_PATH="$ENV_PATH"

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
  deadline=$(( $(date +%s) + 120 ))
  until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "Deployment blocked: Jenkins.Database/backup — PostgreSQL readiness timed out after 120 seconds." >&2
      exit 1
    fi
    sleep 1
  done
'

if ! docker compose --env-file "$ENV_PATH" exec -T db sh -lc \
  'PGPASSWORD="$POSTGRES_PASSWORD" psql -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select 1"' >/dev/null 2>&1; then
  echo 'Deployment blocked: Jenkins.Database/backup — configured credentials do not match the PostgreSQL cluster; restore the matching deployment env before retrying.'
  exit 1
fi

docker compose --env-file "$ENV_PATH" exec -T db sh -lc 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F p' > "$BACKUP_FILE"

echo "Backup created at $BACKUP_FILE"
