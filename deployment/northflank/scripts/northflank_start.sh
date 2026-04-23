#!/usr/bin/env bash
set -Eeuo pipefail

# Northflank backend start/boot script for Notechondria.
# Intended for use as the Northflank Combined Service custom command, or
# as an override CMD if you swap the Dockerfile ENTRYPOINT.
#
# Expected env (wired via Northflank runtime environment, Secret Group, or
# linked PostgreSQL addon):
# - DATABASE_URL or (POSTGRE_HOST, POSTGRE_PORT, POSTGRE_DB, POSTGRE_USERNAME, POSTGRE_PASSWORD)
# - DJANGO_SECRET_KEY
# - DJANGO_ALLOWED_HOSTS
# - DJANGO_CSRF_TRUSTED_ORIGINS
# - PORT (Northflank injects; defaults to 8000)
# - CLOUDFLARE_R2_* (required — see sample.northflank.env)
# Optional env:
# - PYTHONUNBUFFERED=1
# - WEB_CONCURRENCY=2
# - BACKEND_CUSTOM_DOMAIN
# - GOOGLE_OAUTH_*, GITHUB_APP_* if OAuth is enabled
# - SMTP_* if email verification is enabled

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR/backend"

export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"
export PORT="${PORT:-8000}"
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
