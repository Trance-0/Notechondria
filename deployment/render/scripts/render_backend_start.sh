#!/usr/bin/env bash
set -Eeuo pipefail

# Render free-tier backend start/boot script for Notechondria.
# Intended for use as the Render Start Command or via a wrapper shell script.
#
# Expected env:
# - DATABASE_URL
# - SECRET_KEY
# - ALLOWED_HOSTS
# - CSRF_TRUSTED_ORIGINS
# - PORT (provided by Render)
# Optional env:
# - PYTHONUNBUFFERED=1
# - WEB_CONCURRENCY=2
# - OPENAI_API_KEY
# - GITHUB_APP_* values if used

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR/backend"

export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"
export PORT="${PORT:-10000}"
export WEB_CONCURRENCY="${WEB_CONCURRENCY:-2}"

printf '==> Running Django migrations\n'
python manage.py migrate --noinput

printf '==> Bootstrapping platform defaults\n'
python manage.py bootstrap_platform || true

printf '==> Collecting static files\n'
python manage.py collectstatic --noinput --clear

printf '==> Starting gunicorn on port %s\n' "$PORT"
exec gunicorn notechondria.wsgi:application \
  --bind "0.0.0.0:${PORT}" \
  --workers "$WEB_CONCURRENCY" \
  --timeout 120
