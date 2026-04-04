#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/.env.deploy}"
cd "$ROOT_DIR"
docker compose --env-file "$ENV_FILE" up -d gateway_nginx
