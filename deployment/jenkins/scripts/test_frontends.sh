#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
docker compose config >/dev/null
for app in editor_app planner_app portal_app; do
  docker build --target frontend_test -t "notechondria-${app}-test" "./frontend/${app}"
  docker build -t "notechondria-${app}:jenkins" "./frontend/${app}"
done
