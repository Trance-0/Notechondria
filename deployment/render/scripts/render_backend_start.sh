#!/usr/bin/env bash
set -Eeuo pipefail

# Render free-tier backend start/boot script for Notechondria.
# Intended for use as the Render Start Command or via a wrapper shell script.
#
# Expected env:
# - DATABASE_URL
# - DJANGO_SECRET_KEY
# - DJANGO_ALLOWED_HOSTS
# - DJANGO_CSRF_TRUSTED_ORIGINS
# - PORT (provided by Render)
# Optional env:
# - PYTHONUNBUFFERED=1
# - WEB_CONCURRENCY=2
# - BACKEND_CUSTOM_DOMAIN
# - OPENAI_API_KEY
# - GITHUB_APP_* values if used

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR/backend"

export PYTHONUNBUFFERED="${PYTHONUNBUFFERED:-1}"
export PORT="${PORT:-10000}"
export WEB_CONCURRENCY="${WEB_CONCURRENCY:-2}"

# Surface VERSION + build provenance via /api/v1/handshake/ so the
# deploy-status check can see which version is actually serving.
# Render's filesystem path differs from the Docker layout; falling
# through these defaults keeps the field non-empty either way.
if [[ -f "$ROOT_DIR/VERSION" && -z "${BACKEND_VERSION:-}" ]]; then
  export BACKEND_VERSION="$(tr -d '\r\n' < "$ROOT_DIR/VERSION")"
fi
export BACKEND_BUILD_COMMIT="${BACKEND_BUILD_COMMIT:-${RENDER_GIT_COMMIT:-}}"
export BACKEND_BUILD_TIME="${BACKEND_BUILD_TIME:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
export BACKEND_DEPLOY_TARGET="${BACKEND_DEPLOY_TARGET:-render}"

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
