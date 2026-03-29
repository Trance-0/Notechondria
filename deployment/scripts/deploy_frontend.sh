#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}
WAIT_SCRIPT=${3:-$PROJECT_DIR/deployment/scripts/wait_for_frontend.sh}
WAIT_TIMEOUT_SECONDS=${4:-300}
NETWORK_SCRIPT=${5:-$PROJECT_DIR/deployment/scripts/ensure_shared_network.sh}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

env_value() {
  local key="$1"
  grep -E "^${key}=" "$ENV_PATH" | tail -n 1 | cut -d= -f2-
}

run_frontend_compose() {
  local frontend_api_base_url
  local frontend_backend_origin
  local frontend_image
  local frontend_host_port
  local shared_network

  frontend_api_base_url=$(env_value "FRONTEND_API_BASE_URL")
  frontend_backend_origin=$(env_value "FRONTEND_BACKEND_ORIGIN")
  frontend_image=$(env_value "FRONTEND_IMAGE")
  frontend_host_port=$(env_value "FRONTEND_HOST_PORT")
  shared_network=$(env_value "NOTECHONDRIA_SHARED_NETWORK")

  if [[ ! "$frontend_api_base_url" =~ ^https?:// ]]; then
    echo "FRONTEND_API_BASE_URL must be an absolute browser-facing URL. Found: $frontend_api_base_url"
    exit 1
  fi

  env \
    -u API_BASE_URL \
    -u FRONTEND_API_BASE_URL \
    -u FRONTEND_BACKEND_ORIGIN \
    -u FRONTEND_IMAGE \
    -u FRONTEND_HOST_PORT \
    -u NOTECHONDRIA_SHARED_NETWORK \
    MSYS_NO_PATHCONV=1 \
    MSYS2_ARG_CONV_EXCL='*' \
    COMPOSE_CONVERT_WINDOWS_PATHS=0 \
    FRONTEND_API_BASE_URL="$frontend_api_base_url" \
    FRONTEND_BACKEND_ORIGIN="$frontend_backend_origin" \
    FRONTEND_IMAGE="$frontend_image" \
    FRONTEND_HOST_PORT="$frontend_host_port" \
    NOTECHONDRIA_SHARED_NETWORK="$shared_network" \
    docker compose --env-file "$ENV_PATH" "$@"
}

cd "$PROJECT_DIR/frontend"

bash "$NETWORK_SCRIPT" "$ENV_PATH"
run_frontend_compose build --pull --no-cache frontend
run_frontend_compose up -d --force-recreate frontend
bash "$WAIT_SCRIPT" "$PROJECT_DIR" "$ENV_PATH" "$WAIT_TIMEOUT_SECONDS"

echo "Frontend deployment finished successfully."
