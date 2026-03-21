#!/bin/bash
# if the script cannot be found, change the file from CRLF to LF

set -e

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

mkdir -p "${PRODUCTION_STATIC_ROOT:-/home/staticfiles}"
mkdir -p "${PRODUCTION_MEDIA_ROOT:-/home/mediafiles}"

python manage.py migrate
python manage.py bootstrap_platform
echo "Collecting static files into ${PRODUCTION_STATIC_ROOT:-/home/staticfiles}"
python manage.py collectstatic --noinput

exec "$@"
