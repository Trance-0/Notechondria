#!/usr/bin/env bash
set -Eeuo pipefail
# Prevent Git-for-Windows MSYS path conversion (/ → C:/Program Files/Git/).
export MSYS_NO_PATHCONV=1
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT_DIR"
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo 'Frontend tests blocked: Jenkins.Test/version — VERSION must contain a Docker-compatible semantic version.' >&2
  exit 1
fi
for app in editor_app planner_app portal_app; do
  timeout 30m docker build --progress=plain --target frontend_test -t "notechondria-${app}-test:v${APP_VERSION}-jenkins.${BUILD_NUMBER:-local}" -f "frontend/${app}/Dockerfile" ./frontend
done
