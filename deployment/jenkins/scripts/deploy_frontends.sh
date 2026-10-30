#!/usr/bin/env bash
set -Eeuo pipefail
# Prevent Git-for-Windows MSYS path conversion (/ → C:/Program Files/Git/).
export MSYS_NO_PATHCONV=1
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ENV_FILE="${1:-$ROOT_DIR/.env.deploy}"
NETWORK_SCRIPT="${ROOT_DIR}/deployment/jenkins/scripts/ensure_shared_network.sh"

bash "$NETWORK_SCRIPT" "$ENV_FILE"

# Stamp the builds with the repo VERSION; without it the Dart default ships
# and the apps show a false "new version" banner against the backend.
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION" 2>/dev/null || true)"
if [[ ! "$APP_VERSION" =~ ^[0-9A-Za-z.+-]+$ ]]; then
  printf 'Frontends not deployed: Jenkins.Deploy/frontends — %s/VERSION is missing, empty, or not a version string.\n' "$ROOT_DIR" >&2
  exit 1
fi
export APP_VERSION

for app in editor_app planner_app portal_app; do
  cd "$ROOT_DIR/frontend/$app"
  export FRONTEND_IMAGE="notechondria-${app}:v${APP_VERSION}-jenkins.${BUILD_NUMBER:-local}"
  export APP_BASE_HREF="/${app%_app}/"
  timeout 30m docker compose --env-file "$ENV_FILE" build
  docker compose --env-file "$ENV_FILE" up -d --wait --wait-timeout 180
done
