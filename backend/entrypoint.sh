#!/bin/bash
# if the script cannot be found, change the file from CRLF to LF

set -e

if [ -n "$POSTGRE_HOST" ] && [ -n "$POSTGRE_PORT" ]
then
    echo "Waiting for postgres..."

    while ! nc -z "$POSTGRE_HOST" "$POSTGRE_PORT"; do
      sleep 0.1
    done

    echo "PostgreSQL started"
fi

python manage.py migrate

exec "$@"
