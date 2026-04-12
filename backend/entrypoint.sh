#!/bin/bash
# if the script cannot be found, change the file from CRLF to LF

set -e

normalize_container_path() {
    local value="${1:-}"
    local fallback="$2"

    if [ -z "$value" ]; then
        echo "$fallback"
        return
    fi

    case "$value" in
        /*)
            printf '%s\n' "${value%/}"
            ;;
        [A-Za-z]:*|*:\\*)
            printf '%s\n' "$fallback"
            ;;
        *)
            printf '%s\n' "$fallback"
            ;;
    esac
}

if [ -n "$POSTGRE_HOST" ] && [ -n "$POSTGRE_PORT" ]
then
    echo "Waiting for postgres..."
    start_time=$SECONDS
    timeout_seconds=300

    while ! nc -z "$POSTGRE_HOST" "$POSTGRE_PORT"; do
      if [ $((SECONDS - start_time)) -ge "$timeout_seconds" ]; then
        echo "Timed out waiting for postgres after ${timeout_seconds}s"
        exit 1
      fi
      sleep 0.1
    done

    echo "PostgreSQL started"
fi

if [ -n "$POSTGRE_HOST" ] && [ -n "$POSTGRE_PORT" ] && [ -n "$POSTGRE_USERNAME" ]
then
    echo "Checking postgres credentials..."
    if ! python - <<'PY'
import os
import sys

import psycopg2

try:
    psycopg2.connect(
        dbname=os.getenv("POSTGRE_DB", "postgres"),
        user=os.getenv("POSTGRE_USERNAME"),
        password=os.getenv("POSTGRE_PASSWORD"),
        host=os.getenv("POSTGRE_HOST", "db"),
        port=os.getenv("POSTGRE_PORT", "5432"),
    ).close()
except psycopg2.OperationalError as exc:
    print("Database authentication failed before migrate.")
    print(str(exc).strip())
    print("If this environment uses an old postgres volume, either:")
    print("1. Restore the previous POSTGRE_USERNAME/POSTGRE_PASSWORD/POSTGRE_DB values, or")
    print("2. Reinitialize the postgres volume for this disposable deployment.")
    sys.exit(1)
PY
    then
        exit 1
    fi
fi

DJANGO_PRODUCTION_STATIC_ROOT="$(normalize_container_path "${DJANGO_PRODUCTION_STATIC_ROOT:-}" "/home/staticfiles")"
DJANGO_PRODUCTION_MEDIA_ROOT="$(normalize_container_path "${DJANGO_PRODUCTION_MEDIA_ROOT:-}" "/home/mediafiles")"
export DJANGO_PRODUCTION_STATIC_ROOT
export DJANGO_PRODUCTION_MEDIA_ROOT

mkdir -p "${DJANGO_PRODUCTION_STATIC_ROOT}"
mkdir -p "${DJANGO_PRODUCTION_MEDIA_ROOT}"

# Detect whether the target database has ever been migrated. If it hasn't,
# or if any migrations are still unapplied, run `manage.py migrate`. On a
# fresh Northflank/Render addon the schema is empty and this is what
# bootstraps it; on an existing DB this is a no-op when nothing is pending.
if python manage.py migrate --check >/dev/null 2>&1; then
    echo "Database schema is up to date; skipping migrate."
else
    echo "Database schema is missing or has pending migrations; running migrate."
    python manage.py migrate --noinput
fi
python manage.py bootstrap_platform
echo "Collecting static files into ${DJANGO_PRODUCTION_STATIC_ROOT}"
python manage.py collectstatic --noinput --clear
python - <<'PY'
import os
import shutil
import sys
from pathlib import Path

import rest_framework
from django.contrib import admin

static_root = Path(os.getenv("DJANGO_PRODUCTION_STATIC_ROOT", "/home/staticfiles")).resolve()
static_root.mkdir(parents=True, exist_ok=True)

package_static_dirs = [
    Path(admin.__file__).resolve().parent / "static" / "admin",
    Path(rest_framework.__file__).resolve().parent / "static" / "rest_framework",
]

for source in package_static_dirs:
    if not source.exists():
        continue
    destination = static_root / source.name
    if destination.exists():
        continue
    shutil.copytree(source, destination)

required_assets = [
    static_root / "admin" / "css" / "base.css",
    static_root / "admin" / "js" / "theme.js",
    static_root / "rest_framework" / "css" / "bootstrap.min.css",
    static_root / "rest_framework" / "js" / "default.js",
]

missing = [str(path) for path in required_assets if not path.exists()]
if missing:
    print("Static asset verification failed after collectstatic.")
    for path in missing:
        print(f"Missing: {path}")
    sys.exit(1)

print("Verified Django admin and DRF static assets are present.")
PY

if [ "$#" -eq 0 ]; then
    # No CMD supplied (Northflank's "configType: default" leaves Dockerfile
    # CMD empty, and our Dockerfile doesn't declare one). Fall back to the
    # gunicorn invocation we want everywhere. Docker-compose and Jenkins
    # override this by passing `command:` explicitly.
    port="${PORT:-8000}"
    workers="${WEB_CONCURRENCY:-2}"
    echo "No CMD passed; starting gunicorn on 0.0.0.0:${port} with ${workers} worker(s)."
    exec gunicorn notechondria.wsgi:application \
        --chdir /home/notechondria \
        --bind "0.0.0.0:${port}" \
        --workers "${workers}" \
        --timeout 120
fi

exec "$@"
