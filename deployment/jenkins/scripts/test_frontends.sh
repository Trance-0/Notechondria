#!/usr/bin/env bash
set -Eeuo pipefail
# Prevent Git-for-Windows MSYS path conversion (/ → C:/Program Files/Git/).
export MSYS_NO_PATHCONV=1
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
docker compose config >/dev/null
for app in editor_app planner_app portal_app; do
  docker build --no-cache --target frontend_test -t "notechondria-${app}-test" "./frontend/${app}"
  docker build --no-cache -t "notechondria-${app}:jenkins" "./frontend/${app}"
done
