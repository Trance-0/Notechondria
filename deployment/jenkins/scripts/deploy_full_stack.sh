#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/local.env}"
export BUILDX_BUILDER=notechondria-local
bash "$ROOT_DIR/deployment/jenkins/scripts/prepare_builder.sh"
bash "$ROOT_DIR/deployment/jenkins/scripts/test_backend.sh" "$ROOT_DIR" "$ENV_FILE"
bash "$ROOT_DIR/deployment/jenkins/scripts/test_frontends.sh"
timeout 5m bash "$ROOT_DIR/deployment/jenkins/scripts/backup_postgres.sh" "$ENV_FILE" "${BACKUP_DIR:-$ROOT_DIR/logs/backups}" "$ROOT_DIR"
bash "$ROOT_DIR/deployment/jenkins/scripts/deploy_backend.sh" "$ROOT_DIR" "$ENV_FILE"
bash "$ROOT_DIR/deployment/jenkins/scripts/deploy_frontends.sh" "$ENV_FILE"
bash "$ROOT_DIR/deployment/jenkins/scripts/deploy_gateway.sh" "$ENV_FILE"
bash "$ROOT_DIR/deployment/jenkins/scripts/verify_deployment.sh" "$ENV_FILE"
