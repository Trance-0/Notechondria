#!/usr/bin/env bash
set -Eeuo pipefail
# Prevent Git-for-Windows MSYS path conversion (/ → C:/Program Files/Git/).
export MSYS_NO_PATHCONV=1
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
for app in editor_app planner_app portal_app; do
  timeout 30m docker build --progress=plain --target frontend_test -t "notechondria-${app}-test" -f "frontend/${app}/Dockerfile" ./frontend
done
