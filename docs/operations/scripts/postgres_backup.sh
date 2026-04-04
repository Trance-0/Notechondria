#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH=${1:-}

if [[ -z "$OUTPUT_PATH" ]]; then
  echo "Usage: bash docs/operations/scripts/postgres_backup.sh <output.dump>" >&2
  exit 1
fi

: "${PGHOST:?PGHOST is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGPASSWORD:?PGPASSWORD is required}"
: "${PGDATABASE:?PGDATABASE is required}"
PGPORT=${PGPORT:-5432}

mkdir -p "$(dirname "$OUTPUT_PATH")"

pg_dump \
  --host "$PGHOST" \
  --port "$PGPORT" \
  --username "$PGUSER" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file "$OUTPUT_PATH" \
  "$PGDATABASE"

echo "Backup written to $OUTPUT_PATH"
