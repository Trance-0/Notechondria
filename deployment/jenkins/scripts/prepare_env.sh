#!/usr/bin/env bash
set -euo pipefail

OUTPUT_PATH=${1:-.env.deploy}
SOURCE_PATH=${2:-}
DEFAULT_FRONTEND_PUBLIC_ORIGIN="http://localhost:${FRONTEND_HOST_PORT:-9060}"

# Read project version from VERSION file at repo root for image tagging.
# Falls back to "0.0.0" when the file is missing.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../../.."
VERSION_FILE="${REPO_ROOT}/VERSION"
if [[ -f "$VERSION_FILE" ]]; then
  PROJECT_VERSION="$(tr -d '\r\n' < "$VERSION_FILE")"
else
  PROJECT_VERSION="0.0.0"
fi
VERSION_TAG="v${PROJECT_VERSION}.${BUILD_NUMBER:-local}"

normalize_container_path_value() {
  local value="${1:-}"
  local fallback="$2"

  if [[ -z "$value" ]]; then
    printf '%s\n' "$fallback"
    return
  fi

  case "$value" in
    /*)
      printf '%s/\n' "${value%/}"
      ;;
    [A-Za-z]:*|*:\\*)
      printf '%s\n' "$fallback"
      ;;
    *)
      printf '%s\n' "$fallback"
      ;;
  esac
}

rewrite_env_path_key() {
  local key="$1"
  local fallback="$2"
  local current
  current=$(grep -E "^${key}=" "$OUTPUT_PATH" | tail -n 1 | cut -d= -f2- || true)
  current=$(normalize_container_path_value "$current" "$fallback")

  local tmp_file
  tmp_file=$(mktemp)
  awk -v key="$key" -v value="$current" '
    BEGIN { replaced = 0 }
    $0 ~ ("^" key "=") {
      if (!replaced) {
        print key "=" value
        replaced = 1
      }
      next
    }
    { print }
    END {
      if (!replaced) {
        print key "=" value
      }
    }
  ' "$OUTPUT_PATH" > "$tmp_file"
  mv "$tmp_file" "$OUTPUT_PATH"
}

normalize_frontend_api_url_value() {
  local value="${1:-}"
  local fallback="$2"

  if [[ -z "$value" ]]; then
    printf '%s\n' "$fallback"
    return
  fi

  case "$value" in
    /*)
      printf '%s\n' "$fallback"
      ;;
    http://localhost:9080|http://localhost:9080/api/v1)
      printf '%s\n' "$fallback"
      ;;
    http://*|https://*)
      local normalized="${value%/}"
      if [[ "$normalized" == */api/v1 ]]; then
        printf '%s\n' "$normalized"
      elif [[ "$normalized" == */api ]]; then
        printf '%s/v1\n' "$normalized"
      else
        printf '%s/api/v1\n' "$normalized"
      fi
      ;;
    *)
      printf '%s\n' "$fallback"
      ;;
  esac
}

rewrite_frontend_api_base_key() {
  local key="FRONTEND_API_BASE_URL"
  local fallback="$1"
  local current
  current=$(grep -E "^${key}=" "$OUTPUT_PATH" | tail -n 1 | cut -d= -f2- || true)
  current=$(normalize_frontend_api_url_value "$current" "$fallback")

  local tmp_file
  tmp_file=$(mktemp)
  awk -v key="$key" -v value="$current" '
    BEGIN { replaced = 0 }
    $0 ~ ("^" key "=") {
      if (!replaced) {
        print key "=" value
        replaced = 1
      }
      next
    }
    { print }
    END {
      if (!replaced) {
        print key "=" value
      }
    }
  ' "$OUTPUT_PATH" > "$tmp_file"
  mv "$tmp_file" "$OUTPUT_PATH"
}

frontend_public_origin_from_env_file() {
  local port
  port=$(grep -E '^FRONTEND_HOST_PORT=' "$OUTPUT_PATH" | tail -n 1 | cut -d= -f2- || true)
  if [[ -z "$port" ]]; then
    port="${FRONTEND_HOST_PORT:-9060}"
  fi
  printf 'http://localhost:%s\n' "$port"
}

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [[ -n "$SOURCE_PATH" && -f "$SOURCE_PATH" ]]; then
  cp "$SOURCE_PATH" "$OUTPUT_PATH"
else
  : "${DJANGO_SECRET_KEY:?DJANGO_SECRET_KEY is required when no source env file is provided}"
  : "${POSTGRE_USERNAME:?POSTGRE_USERNAME is required when no source env file is provided}"
  : "${POSTGRE_PASSWORD:?POSTGRE_PASSWORD is required when no source env file is provided}"
  : "${POSTGRE_HOST:?POSTGRE_HOST is required when no source env file is provided}"
  : "${POSTGRE_PORT:?POSTGRE_PORT is required when no source env file is provided}"
  : "${POSTGRE_DB:?POSTGRE_DB is required when no source env file is provided}"

  cat > "$OUTPUT_PATH" <<EOF
DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY}
DJANGO_DEBUG=${DJANGO_DEBUG:-False}
DJANGO_ALLOWED_HOSTS=${DJANGO_ALLOWED_HOSTS:-localhost,127.0.0.1}
DJANGO_ALLOWED_HOSTS_COMPOSE='${DJANGO_ALLOWED_HOSTS_COMPOSE:-localhost 127.0.0.1}'
DJANGO_CSRF_TRUSTED_ORIGINS=${DJANGO_CSRF_TRUSTED_ORIGINS:-http://localhost:9080,http://localhost:9060}
DJANGO_LOG_LEVEL=${DJANGO_LOG_LEVEL:-INFO}
DJANGO_LOG_FILE_NAME=${DJANGO_LOG_FILE_NAME:-notechondria}
DJANGO_SUPERUSER_USERNAME=${DJANGO_SUPERUSER_USERNAME:-admin}
DJANGO_SUPERUSER_EMAIL=${DJANGO_SUPERUSER_EMAIL:-admin@example.com}
DJANGO_SUPERUSER_PASSWORD=${DJANGO_SUPERUSER_PASSWORD:-change-me}
APP_HOST_PORT=${APP_HOST_PORT:-9080}
BACKEND_HOST_PORT=${BACKEND_HOST_PORT:-9090}
FRONTEND_HOST_PORT=${FRONTEND_HOST_PORT:-9060}
DB_HOST_PORT=${DB_HOST_PORT:-9032}
POSTGRE_USERNAME=${POSTGRE_USERNAME}
POSTGRE_PASSWORD=${POSTGRE_PASSWORD}
POSTGRE_HOST=${POSTGRE_HOST}
POSTGRE_PORT=${POSTGRE_PORT}
POSTGRE_DB=${POSTGRE_DB}
DJANGO_PRODUCTION_STATIC_ROOT=${DJANGO_PRODUCTION_STATIC_ROOT:-/home/staticfiles/}
DJANGO_PRODUCTION_MEDIA_ROOT=${DJANGO_PRODUCTION_MEDIA_ROOT:-/home/mediafiles/}
OPENAI_API_KEY=${OPENAI_API_KEY:-}
SMTP_HOST=${SMTP_HOST:-}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_USERNAME=${SMTP_USERNAME:-}
SMTP_PASSWORD=${SMTP_PASSWORD:-}
SMTP_USE_TLS=${SMTP_USE_TLS:-True}
SMTP_USE_SSL=${SMTP_USE_SSL:-False}
SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL:-no-reply@example.com}
SMTP_EMAIL_VERIFICATION_TTL_HOURS=${SMTP_EMAIL_VERIFICATION_TTL_HOURS:-24}
FRONTEND_VERIFY_URL=${FRONTEND_VERIFY_URL:-http://localhost:9060/#/verify}
FRONTEND_API_BASE_URL=${FRONTEND_API_BASE_URL:-${DEFAULT_FRONTEND_PUBLIC_ORIGIN}/api/v1}
FRONTEND_BACKEND_ORIGIN=${FRONTEND_BACKEND_ORIGIN:-http://nginx}
NOTECHONDRIA_SHARED_NETWORK=${NOTECHONDRIA_SHARED_NETWORK:-notechondria-shared}
GITHUB_APP_ID=${GITHUB_APP_ID:-}
GITHUB_APP_CLIENT_ID=${GITHUB_APP_CLIENT_ID:-}
GITHUB_APP_CLIENT_SECRET=${GITHUB_APP_CLIENT_SECRET:-}
GITHUB_APP_PRIVATE_KEY_PATH=${GITHUB_APP_PRIVATE_KEY_PATH:-}
GITHUB_APP_WEBHOOK_SECRET=${GITHUB_APP_WEBHOOK_SECRET:-}
GITHUB_AUTHORIZED_REDIRECT_URI=${GITHUB_AUTHORIZED_REDIRECT_URI:-}
GOOGLE_OAUTH_CLIENT_ID=${GOOGLE_OAUTH_CLIENT_ID:-}
GOOGLE_OAUTH_CLIENT_SECRET=${GOOGLE_OAUTH_CLIENT_SECRET:-}
GOOGLE_AUTHORIZED_REDIRECT_URI=${GOOGLE_AUTHORIZED_REDIRECT_URI:-}
FRONTEND_ORIGIN=${FRONTEND_ORIGIN:-}
APP_IMAGE=${APP_IMAGE:-trancezero/notechondria:${VERSION_TAG}}
NGINX_IMAGE=${NGINX_IMAGE:-trancezero/nginx:${VERSION_TAG}}
FRONTEND_IMAGE=${FRONTEND_IMAGE:-trancezero/notechondria-frontend:${VERSION_TAG}}
DB_AUTO_REINIT_IF_MISMATCH=${DB_AUTO_REINIT_IF_MISMATCH:-False}
EOF
fi

rewrite_env_path_key "DJANGO_PRODUCTION_STATIC_ROOT" "/home/staticfiles/"
rewrite_env_path_key "DJANGO_PRODUCTION_MEDIA_ROOT" "/home/mediafiles/"
rewrite_frontend_api_base_key "$(frontend_public_origin_from_env_file)/api/v1"

chmod 600 "$OUTPUT_PATH"
echo "Deployment env prepared at $OUTPUT_PATH"
