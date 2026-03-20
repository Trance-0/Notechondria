#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}
TIMEOUT_SECONDS=${3:-300}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/backend"

start_time=$(date +%s)

while true; do
  app_container_id=$(docker compose --env-file "$ENV_PATH" ps -q app)

  if [[ -z "$app_container_id" ]]; then
    echo "App container has not been created yet."
  else
    health_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$app_container_id")

    if [[ "$health_status" == "healthy" || "$health_status" == "running" ]]; then
      echo "App container is ready with status: $health_status"
      exit 0
    fi

    if [[ "$health_status" == "exited" || "$health_status" == "dead" || "$health_status" == "unhealthy" ]]; then
      echo "App container failed with status: $health_status"
      docker compose --env-file "$ENV_PATH" logs --tail=200 app db nginx || true
      exit 1
    fi
  fi

  current_time=$(date +%s)
  if [[ $((current_time - start_time)) -ge "$TIMEOUT_SECONDS" ]]; then
    echo "Timed out waiting for stack readiness after ${TIMEOUT_SECONDS}s"
    docker compose --env-file "$ENV_PATH" logs --tail=200 app db nginx || true
    docker compose --env-file "$ENV_PATH" stop app nginx || true
    exit 1
  fi

  sleep 5
done
