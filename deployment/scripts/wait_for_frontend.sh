#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=${1:-$(pwd)}
ENV_PATH=${2:-$PROJECT_DIR/.env}
TIMEOUT_SECONDS=${3:-300}

if [[ ! -f "$ENV_PATH" ]]; then
  echo "Env file not found: $ENV_PATH"
  exit 1
fi

cd "$PROJECT_DIR/frontend"

start_time=$(date +%s)

while true; do
  frontend_container_id=$(docker compose --env-file "$ENV_PATH" ps -q frontend)

  if [[ -z "$frontend_container_id" ]]; then
    echo "Frontend container has not been created yet."
  else
    health_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$frontend_container_id")

    if [[ "$health_status" == "healthy" || "$health_status" == "running" ]]; then
      echo "Frontend container is ready with status: $health_status"
      exit 0
    fi

    if [[ "$health_status" == "exited" || "$health_status" == "dead" || "$health_status" == "unhealthy" ]]; then
      echo "Frontend container failed with status: $health_status"
      docker compose --env-file "$ENV_PATH" logs --tail=200 frontend || true
      exit 1
    fi
  fi

  current_time=$(date +%s)
  if [[ $((current_time - start_time)) -ge "$TIMEOUT_SECONDS" ]]; then
    echo "Timed out waiting for frontend readiness after ${TIMEOUT_SECONDS}s"
    docker compose --env-file "$ENV_PATH" logs --tail=200 frontend || true
    docker compose --env-file "$ENV_PATH" stop frontend || true
    exit 1
  fi

  sleep 5
done
