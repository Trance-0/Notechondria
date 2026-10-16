#!/usr/bin/env bash
# Build the three Flutter web apps from this checkout and serve them on
# 127.0.0.1 behind one nginx gateway that forwards /api/, /media/, and
# /static/ to a remote Notechondria backend. No local backend or database.
#
#   scripts/local_remote_deploy.sh up     # build (sequential) + (re)start
#   scripts/local_remote_deploy.sh down   # stop and remove the containers
#
# Env: LOCAL_GATEWAY_HOST_PORT (default 9068, always bound to 127.0.0.1),
#      REMOTE_BACKEND_ORIGIN (default https://notechondria.trance-0.com).
# Images are stamped with the repo-root VERSION (APP_VERSION build arg) and
# containers use --restart unless-stopped so the preview survives a Docker
# daemon or host restart; `down` removes them for good.
# Details: docs/development/local_dev.md.
set -Eeuo pipefail
export MSYS_NO_PATHCONV=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_PORT="${LOCAL_GATEWAY_HOST_PORT:-9068}"
REMOTE_ORIGIN="${REMOTE_BACKEND_ORIGIN:-https://notechondria.trance-0.com}"
NETWORK=notechondria-local
GATEWAY=notechondria-local-gateway
GATEWAY_IMAGE=nginx:1.27-alpine
APPS=(portal editor planner)
BUILD_TIMEOUT_SECONDS=1200
READY_TIMEOUT_SECONDS=60

log() { printf '[LocalDeploy] %s\n' "$*"; }
fail() { printf '[LocalDeploy] %s\n' "$*" >&2; exit 1; }

port_in_use() {
  if command -v ss >/dev/null 2>&1; then
    ss -Hltn "sport = :$1" | grep -q .
  elif command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"
  else
    # docker run still refuses a taken port; it just reports it less clearly.
    return 1
  fi
}

remove_containers() {
  docker rm -f "$GATEWAY" "${APPS[@]/#/notechondria-local-}" >/dev/null 2>&1 || true
}

preflight() {
  command -v docker >/dev/null 2>&1 \
    || fail "Local deploy not started: LocalDeploy/preflight — docker CLI not found on PATH."
  command -v curl >/dev/null 2>&1 \
    || fail "Local deploy not started: LocalDeploy/preflight — curl not found on PATH (needed for the readiness check)."
  [[ "$HOST_PORT" =~ ^[0-9]{1,5}$ ]] && (( HOST_PORT >= 1 && HOST_PORT <= 65535 )) \
    || fail "Local deploy not started: LocalDeploy/preflight — LOCAL_GATEWAY_HOST_PORT='$HOST_PORT' is not a TCP port (1-65535)."
  # The value is substituted into nginx config, so accept only scheme://host[:port].
  [[ "$REMOTE_ORIGIN" =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?$ ]] \
    || fail "Local deploy not started: LocalDeploy/preflight — REMOTE_BACKEND_ORIGIN='$REMOTE_ORIGIN' must look like https://host[:port] with no path."
  # Without a real APP_VERSION the apps ship the Dart default and show a false
  # "new version" banner against the backend handshake.
  APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION" 2>/dev/null || true)"
  [[ "$APP_VERSION" =~ ^[0-9A-Za-z.+-]+$ ]] \
    || fail "Local deploy not started: LocalDeploy/preflight — $ROOT_DIR/VERSION is missing, empty, or not a version string ('$APP_VERSION')."
  local own
  own="$(docker port "$GATEWAY" 80/tcp 2>/dev/null || true)"
  if [[ "$own" != "127.0.0.1:$HOST_PORT" ]] && port_in_use "$HOST_PORT"; then
    fail "Local deploy not started: LocalDeploy/preflight — host port $HOST_PORT is already in use; set LOCAL_GATEWAY_HOST_PORT to a free port."
  fi
}

build_apps() {
  local app
  # FRONTEND_API_BASE_URL stays at the Dockerfile default: on localhost /
  # 127.0.0.1 the apps always call same-origin /api/v1 (_defaultApiBaseUrl in
  # lib/core/helpers.dart), which the gateway forwards to the remote.
  for app in "${APPS[@]}"; do
    log "Building ${app}_app web image ${APP_VERSION} (sequential, timeout ${BUILD_TIMEOUT_SECONDS}s)..."
    timeout "$BUILD_TIMEOUT_SECONDS" docker build --progress=plain \
      --build-arg "APP_BASE_HREF=/${app}/" \
      --build-arg "APP_VERSION=${APP_VERSION}" \
      -t "notechondria-local-${app}:latest" \
      -f "$ROOT_DIR/frontend/${app}_app/Dockerfile" "$ROOT_DIR/frontend" \
      || fail "Local deploy not started: LocalDeploy/build — docker build of ${app}_app failed or exceeded ${BUILD_TIMEOUT_SECONDS}s (see the build output above)."
  done
}

start_stack() {
  local app code=''
  remove_containers
  docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create "$NETWORK" >/dev/null
  for app in "${APPS[@]}"; do
    # App containers publish no ports; only the gateway reaches them. Their
    # own /api/ block is unused here, so point it at an IP literal that needs
    # no DNS at nginx startup.
    docker run -d --name "notechondria-local-${app}" --network "$NETWORK" --memory 256m \
      --restart unless-stopped \
      -e FRONTEND_BACKEND_ORIGIN=http://127.0.0.1:9 \
      "notechondria-local-${app}:latest" >/dev/null \
      || fail "Local deploy not started: LocalDeploy/start — could not start container notechondria-local-${app}."
  done
  docker create --name "$GATEWAY" --network "$NETWORK" --memory 128m \
    --restart unless-stopped \
    -p "127.0.0.1:${HOST_PORT}:80" \
    -e "NOTECHONDRIA_REMOTE_ORIGIN=${REMOTE_ORIGIN}" \
    "$GATEWAY_IMAGE" >/dev/null \
    || fail "Local deploy not started: LocalDeploy/start — could not create $GATEWAY on 127.0.0.1:${HOST_PORT}."
  # docker cp instead of a bind mount so this also works with a remote daemon.
  # The image has no /etc/nginx/templates, so copy a whole directory.
  STAGING_DIR="$(mktemp -d)"
  trap 'rm -rf "$STAGING_DIR"' EXIT
  mkdir "$STAGING_DIR/templates"
  cp "$ROOT_DIR/deployment/docker/nginx/local_remote.conf.template" \
    "$STAGING_DIR/templates/default.conf.template"
  docker cp "$STAGING_DIR/templates" "$GATEWAY:/etc/nginx/" >/dev/null \
    || fail "Local deploy not started: LocalDeploy/start — could not copy the gateway config into $GATEWAY."
  docker start "$GATEWAY" >/dev/null \
    || fail "Local deploy not started: LocalDeploy/start — could not start $GATEWAY."

  for (( i = 0; i < READY_TIMEOUT_SECONDS; i++ )); do
    code="$(curl -sS -m 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HOST_PORT}/portal/" 2>/dev/null || true)"
    [[ "$code" == 200 ]] && break
    sleep 1
  done
  if [[ "$code" != 200 ]]; then
    docker logs --tail 50 "$GATEWAY" >&2 || true
    fail "Local deploy unusable: LocalDeploy/wait — http://127.0.0.1:${HOST_PORT}/portal/ did not return 200 within ${READY_TIMEOUT_SECONDS}s (last status '${code}')."
  fi

  code="$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${HOST_PORT}/api/v1/handshake/" 2>/dev/null || true)"
  [[ -z "$code" || "$code" == 000 ]] && code='no response'
  if [[ "$code" == 200 ]]; then
    log "Remote backend reachable through the gateway (handshake 200 from ${REMOTE_ORIGIN})."
  else
    log "Apps will start in offline/fallback mode: LocalDeploy/wait — handshake via ${REMOTE_ORIGIN} returned '${code}' within 10s."
  fi
  log "Portal:  http://127.0.0.1:${HOST_PORT}/portal/"
  log "Editor:  http://127.0.0.1:${HOST_PORT}/editor/"
  log "Planner: http://127.0.0.1:${HOST_PORT}/planner/"
  log "Stop with: scripts/local_remote_deploy.sh down"
}

case "${1:-}" in
  up)
    preflight
    build_apps
    start_stack
    ;;
  down)
    remove_containers
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
    log "Stopped and removed $GATEWAY and the app containers (images kept for fast rebuilds)."
    ;;
  *)
    fail "Nothing done: LocalDeploy/usage — expected 'up' or 'down', got '${1:-}'."
    ;;
esac
