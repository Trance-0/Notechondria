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
  nginx_container_id=$(docker compose --env-file "$ENV_PATH" ps -q nginx)
  app_ready=false
  nginx_ready=false

  if [[ -z "$app_container_id" ]]; then
    echo "App container has not been created yet."
  else
    health_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$app_container_id")

    if [[ "$health_status" == "healthy" || "$health_status" == "running" ]]; then
      app_ready=true
    fi

    if [[ "$health_status" == "exited" || "$health_status" == "dead" || "$health_status" == "unhealthy" ]]; then
      echo "App container failed with status: $health_status"
      docker compose --env-file "$ENV_PATH" logs --tail=200 app db nginx || true
      exit 1
    fi
  fi

  if [[ -z "$nginx_container_id" ]]; then
    echo "Nginx container has not been created yet."
  else
    nginx_health_status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$nginx_container_id")

    if [[ "$nginx_health_status" == "healthy" || "$nginx_health_status" == "running" ]]; then
      nginx_ready=true
    fi

    if [[ "$nginx_health_status" == "exited" || "$nginx_health_status" == "dead" || "$nginx_health_status" == "unhealthy" ]]; then
      echo "Nginx container failed with status: $nginx_health_status"
      docker compose --env-file "$ENV_PATH" logs --tail=200 app db nginx || true
      exit 1
    fi
  fi

  if [[ "$app_ready" == true && "$nginx_ready" == true ]]; then
    echo "App and nginx containers are ready."
    exit 0
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
