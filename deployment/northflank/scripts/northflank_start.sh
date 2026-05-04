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

# `BACKEND_VERSION`, `BACKEND_BUILD_COMMIT`, and `BACKEND_BUILD_TIME`
# are no longer wired here — `_read_backend_version()` and
# `_build_metadata()` in `backend/notechondria/api_views.py` derive
# them from `/home/VERSION`, `/home/BUILD_COMMIT`, and
# `/home/BUILD_TIME` respectively, all baked into the image at
# Docker build time. The Dockerfile takes a `GIT_COMMIT` build ARG
# (Northflank populates it from `NORTHFLANK_GIT_COMMIT` per
# northflank.json's `buildArguments`).
#
# `BACKEND_DEPLOY_TARGET` is still env-driven because it's a label,
# not a derived fact — left as a runtime override so the same image
# can serve under different "deploy_target" identities.
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
