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

python manage.py migrate
python manage.py bootstrap_platform
python manage.py collectstatic --noinput

exec "$@"
