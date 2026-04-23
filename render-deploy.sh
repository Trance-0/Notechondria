#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

load_env_file() {
  local env_file="$1"
  if [[ -f "$env_file" ]]; then
    echo "Loading env from $env_file"
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
    return 0
  fi
  return 1
}

if [[ $# -gt 0 ]]; then
  load_env_file "$1" || true
else
  load_env_file "$ROOT_DIR/.env" || true
  load_env_file "/etc/secrets/.env" || true
  for candidate in /etc/secrets/*.env; do
    [[ -e "$candidate" ]] || break
    load_env_file "$candidate" || true
    break
  done
fi

bash "$ROOT_DIR/deployment/render/scripts/render_backend_start.sh"
