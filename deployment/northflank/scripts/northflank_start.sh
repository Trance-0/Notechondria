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
# - CASDOOR_* to enable Casdoor SSO (auth.trance-0.com); empty leaves the
#   backend in shadow mode and the legacy email/password fallback still works
# - GITHUB_DATA_SYNC_APP_* to enable the experimental per-user data-sync
#   feature (POST /api/v1/integrations/github/push/)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR/backend"

export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"
export PORT="${PORT:-8000}"
export WEB_CONCURRENCY="${WEB_CONCURRENCY:-2}"

# Surface VERSION + build provenance via /api/v1/handshake/ so the
# deploy-status check can see which version is actually serving.
if [[ -f "$ROOT_DIR/VERSION" && -z "${BACKEND_VERSION:-}" ]]; then
  export BACKEND_VERSION="$(tr -d '\r\n' < "$ROOT_DIR/VERSION")"
fi
export BACKEND_BUILD_COMMIT="${BACKEND_BUILD_COMMIT:-${NORTHFLANK_GIT_COMMIT:-}}"
export BACKEND_BUILD_TIME="${BACKEND_BUILD_TIME:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
export BACKEND_DEPLOY_TARGET="${BACKEND_DEPLOY_TARGET:-northflank}"

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
