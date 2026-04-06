#!/usr/bin/env bash
set -euo pipefail

INPUT_PATH=${1:-}

if [[ -z "$INPUT_PATH" ]]; then
  echo "Usage: bash docs/operations/scripts/postgres_restore.sh <input.dump>" >&2
  exit 1
fi

if [[ ! -f "$INPUT_PATH" ]]; then
  echo "Backup file not found: $INPUT_PATH" >&2
  exit 1
fi

: "${PGHOST:?PGHOST is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required}"
PGPORT=${PGPORT:-5432}

pg_restore \
  --host "$PGHOST" \
  --port "$PGPORT" \
  --username "$PGUSER" \
  --dbname "$PGDATABASE" \
  --clean \
  --if-exists \
  --no-owner \
  --no-privileges \
  "$INPUT_PATH"

echo "Restore completed into $PGDATABASE on $PGHOST:$PGPORT"
