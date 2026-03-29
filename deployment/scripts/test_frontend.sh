#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/frontend"

env \
  -u API_BASE_URL \
  -u FRONTEND_API_BASE_URL \
  MSYS_NO_PATHCONV=1 \
  MSYS2_ARG_CONV_EXCL='*' \
  COMPOSE_CONVERT_WINDOWS_PATHS=0 \
  docker build --pull --no-cache --target frontend_test -t notechondria-frontend-test .
