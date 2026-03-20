#!/usr/bin/env bash
set -euo pipefail

ENV_PATH=${1:-.env}
BACKUP_DIR=${2:-./backups}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

set -a
source "$ENV_PATH"
set +a

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/notechondria_${TIMESTAMP}.sql"

PGPASSWORD="${POSTGRE_PASSWORD}" pg_dump \
  -h "${POSTGRE_HOST}" \
  -p "${POSTGRE_PORT}" \
  -U "${POSTGRE_USERNAME}" \
  -d "${POSTGRE_DB:-postgres}" \
  -F p > "$BACKUP_FILE"

echo "Backup created at $BACKUP_FILE"
