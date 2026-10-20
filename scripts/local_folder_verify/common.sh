# shellcheck shell=bash
# Shared settings and helpers for scripts/local_folder_verify/*.sh. Each
# script sets CHECK_NAME and sources this file; do not run it directly.
#
# Every container started through run_heavy is bounded by `timeout`, gets an
# explicit --memory, waits for $NC_VERIFY_DIR/flutter.lock so only one heavy
# job runs at a time (docs/AGENTS.md "Host resource budget"), and never
# publishes a port. The repo is never mounted: runs use scratch copies under
# $NC_VERIFY_DIR, and only gen_l10n.sh writes back into the working tree.

LFV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LFV_DIR}/../.." && pwd)"
DRIVERS_DIR="${LFV_DIR}/drivers"
NC_VERIFY_DIR="${NC_VERIFY_DIR:-${TMPDIR:-/tmp}/nc_verify}"
FLUTTER_IMAGE="${FLUTTER_IMAGE:-ghcr.io/cirruslabs/flutter:stable}"
CHROMIUM_IMAGE="${CHROMIUM_IMAGE:-nc-flutter-chromium:local}"
PYTHON_IMAGE="${PYTHON_IMAGE:-python:3.11-slim}"
NC_MEMORY="${NC_MEMORY:-6g}"
SITES_DIR="${NC_VERIFY_DIR}/lfv_sites"
CHECK_NAME="${CHECK_NAME:-common}"

say() { printf '[lfv:%s %s] %s\n' "${CHECK_NAME}" "$(date +%T)" "$*"; }

# 1.8-shaped messages: consequence, LocalFolderVerify/<check>, cause.
not_run() {
  printf 'Check not run: LocalFolderVerify/%s — %s\n' "${CHECK_NAME}" "$*" >&2
  exit 2
}
fail() {
  printf 'Check failed: LocalFolderVerify/%s — %s\n' "${CHECK_NAME}" "$*" >&2
  exit 1
}

require_tools() {
  local t
  for t in "$@"; do
    command -v "${t}" >/dev/null 2>&1 || not_run "${t} not found on PATH."
  done
}

require_docker() {
  require_tools docker git tar flock timeout
  timeout 30 docker info >/dev/null 2>&1 \
    || not_run "docker daemon not reachable ('docker info' failed or took over 30 s)."
}

require_image() {
  docker image inspect "$1" >/dev/null 2>&1 \
    || not_run "image $1 is not present; run scripts/local_folder_verify/build_image.sh first (or set CHROMIUM_IMAGE)."
}

check_app() {
  case "$1" in
    editor | planner | portal) ;;
    *) not_run "unknown app '$1'; expected editor, planner, or portal." ;;
  esac
}

if [ -f "${REPO_ROOT}/VERSION" ]; then
  APP_VERSION="${APP_VERSION:-$(tr -d '\r\n' < "${REPO_ROOT}/VERSION")}"
else
  not_run "no VERSION file at ${REPO_ROOT}; the scripts must stay in scripts/local_folder_verify/ of the repo."
fi

lfv_name() { printf 'nc-lfv-%s-%s' "$1" "$$"; }

# Docker arguments: every container hands its files back to the host user;
# the Flutter containers also share the pub cache.
OWNER_DOCKER=(-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" -e APP_VERSION="${APP_VERSION}")
FLUTTER_DOCKER=(
  "${OWNER_DOCKER[@]}"
  -e PUB_CACHE=/pub-cache -e FLUTTER_SUPPRESS_ANALYTICS=true -e CI=true
  -v "${NC_VERIFY_DIR}/pub-cache:/pub-cache"
)

# Prepended to every container script. `step <name> <timeout s> <cmd...>`
# writes the command's output to /work/logs/<name>.txt, appends
# "<name> <exit>" to /work/status.txt, and returns the exit code. The trap
# hands the scratch files back to the host user even after a failure.
CONTAINER_PRELUDE="$(cat <<'EOF'
trap 'chown -R "${HOST_UID}:${HOST_GID}" /work /pub-cache /pip-cache 2>/dev/null' EXIT
mkdir -p /work/logs
: > /work/status.txt
if command -v flutter >/dev/null 2>&1; then
  git config --global --add safe.directory /sdks/flutter 2>/dev/null
  flutter config --enable-web >/dev/null 2>&1
fi
step() {
  local n="$1" t="$2" rc
  shift 2
  echo "[container $(date +%T)] ${n} start"
  timeout "${t}" "$@" > "/work/logs/${n}.txt" 2>&1
  rc=$?
  echo "${n} ${rc}" >> /work/status.txt
  echo "[container $(date +%T)] ${n} exit ${rc}"
  return "${rc}"
}
EOF
)"

# scratch_copy <dest> [repo paths...]: `git archive HEAD` of the paths
# (default frontend) into <dest>, then the working-tree paths listed in
# $OVERLAY (space-separated, relative to the repo root) on top.
scratch_copy() {
  local dest="$1" d
  shift
  local paths=("$@")
  [ "${#paths[@]}" -gt 0 ] || paths=(frontend)
  case "${dest}" in
    "${NC_VERIFY_DIR}"/?*) ;;
    *) fail "scratch directory ${dest} is outside ${NC_VERIFY_DIR}; refusing to replace it." ;;
  esac
  rm -rf "${dest}"
  mkdir -p "${dest}" "${NC_VERIFY_DIR}/pub-cache"
  git -C "${REPO_ROOT}" archive HEAD "${paths[@]}" | tar -x -C "${dest}"
  git -C "${REPO_ROOT}" rev-parse --short HEAD > "${dest}/base_head.txt"
  for d in ${OVERLAY:-}; do
    case "${d}" in
      /* | *..*) fail "OVERLAY entry ${d} must be a path inside the repo, relative to its root." ;;
    esac
    if [ -d "${REPO_ROOT}/${d}" ]; then
      require_tools rsync
      mkdir -p "${dest}/${d}"
      rsync -a --delete --exclude build/ --exclude .dart_tool/ --exclude '.flutter-plugins*' \
        "${REPO_ROOT}/${d}/" "${dest}/${d}/"
    elif [ -f "${REPO_ROOT}/${d}" ]; then
      mkdir -p "$(dirname "${dest}/${d}")"
      cp "${REPO_ROOT}/${d}" "${dest}/${d}"
    else
      fail "OVERLAY entry ${d} does not exist in the working tree."
    fi
  done
  say "scratch ${dest}: HEAD $(cat "${dest}/base_head.txt") ${paths[*]}${OVERLAY:+, working tree: ${OVERLAY}}"
}

# run_heavy <name> <timeout s> <docker run args...>: one container at a time
# (flock), killed after the timeout, with --memory $NC_MEMORY and no -p.
run_heavy() {
  local name="$1" limit="$2" a prev="" status=0
  shift 2
  for a in "$@"; do
    case "${a}" in
      -p | -P | -p[0-9]* | --publish | --publish=* | --publish-all | --network=host | --net=host)
        fail "refused docker option ${a}: these checks never publish a port or share the host network." ;;
    esac
    if [ "${a}" = host ] && { [ "${prev}" = --network ] || [ "${prev}" = --net ]; }; then
      fail "refused docker option ${prev} host: these checks never share the host network."
    fi
    prev="${a}"
  done
  mkdir -p "${NC_VERIFY_DIR}"
  say "container ${name}: waiting for ${NC_VERIFY_DIR}/flutter.lock (timeout ${limit} s, --memory ${NC_MEMORY})"
  flock "${NC_VERIFY_DIR}/flutter.lock" timeout --signal=KILL "${limit}" \
    docker run --rm --name "${name}" --memory "${NC_MEMORY}" "$@" || status=$?
  if [ "${status}" -ne 0 ]; then
    docker rm -f "${name}" >/dev/null 2>&1 || true
  fi
  return "${status}"
}

# Last progress line of a `flutter test` log, e.g. "00:20 +353: All tests passed!".
test_summary() {
  tr '\r' '\n' < "$1" | grep -E '^[0-9]+:[0-9]+ \+[0-9]+' | tail -1 | sed -E 's/ +$//' || true
}

# summarize <work dir>: one line per recorded step; fails when a step
# failed. `flutter analyze` exits 1 on infos and warnings, so an analyze
# step fails only on errors or a missing summary line.
summarize() {
  local work="$1" n rc log line errs bad=""
  [ -s "${work}/status.txt" ] || fail "no step results in ${work}/status.txt; the container stopped before its first step."
  while read -r n rc; do
    log="${work}/logs/${n}.txt"
    case "${n}" in
      analyze_*)
        errs="$(grep -cE '^ *error •' "${log}" || true)"
        line="$(grep -E 'issues? found|No issues found' "${log}" | tail -1 || true)"
        [ -n "${line}" ] && [ "${errs}" = 0 ] || bad+=" ${n}(errors=${errs})"
        line="${line:-no summary line}; ${errs} errors" ;;
      smoke_* | test_* | shared_*)
        line="$(test_summary "${log}")"
        [ "${rc}" = 0 ] || bad+=" ${n}(exit ${rc})" ;;
      pubget_*)
        line="$(tail -1 "${log}" 2>/dev/null | cut -c1-100 || true)"
        if [ "${rc}" != 0 ] && grep -q 'Got dependencies!' "${log}" \
          && grep -q 'Placeholders used in selects must be of type' "${log}"; then
          # notechondria_shared: packages resolve, then the synthetic l10n
          # step stops on the activityWeightN placeholder (README gotchas).
          line="dependencies resolved; known gen-l10n activityWeightN error"
        elif [ "${rc}" != 0 ]; then
          bad+=" ${n}(exit ${rc})"
        fi ;;
      *)
        line="$(tail -1 "${log}" 2>/dev/null | tr '\r' ' ' | cut -c1-100 || true)"
        [ "${rc}" = 0 ] || bad+=" ${n}(exit ${rc})" ;;
    esac
    printf '  %-30s exit %-4s %s\n' "${n}" "${rc}" "${line}"
  done < "${work}/status.txt"
  [ -z "${bad}" ] || fail "step(s) failed:${bad}; logs in ${work}/logs/."
}

# check_listeners <file>: every hex address:port from /proc/net/tcp{,6}
# found in <file> must be loopback (127.0.0.0/8, ::1, ::ffff:127.0.0.0/8).
check_listeners() {
  local file="$1" tok addr seen="" bad=""
  [ -f "${file}" ] || fail "listener evidence ${file} is missing."
  for tok in $(grep -oE '\b[0-9A-F]{8}([0-9A-F]{24})?:[0-9A-F]{4}\b' "${file}" | sort -u); do
    addr="${tok%%:*}"
    seen+=" ${tok}"
    case "${#addr}:${addr}" in
      8:??????7F | 32:00000000000000000000000001000000 | 32:0000000000000000FFFF0000??????7F) ;;
      *) bad+=" ${tok}" ;;
    esac
  done
  [ -z "${bad}" ] || fail "non-loopback listener(s) inside the container:${bad} (hex address:port from /proc/net/tcp*, see ${file})."
  say "listeners (hex address:port):${seen:- none}; all on loopback"
}

# ensure_site <hook|release> <app>: a web build in $SITES_DIR/<kind>_<app>_app.
# hook = base href "/" plus the OPFS test-hook define (e2e, U3); release =
# the frontend-pages.yml build (base href /Notechondria/<app>/). Rebuilt when
# REBUILD=1, OVERLAY is set, or the build is from another HEAD.
ensure_site() {
  local kind="$1" app="$2" site stamp head work base defines=""
  site="${SITES_DIR}/${kind}_${app}_app"
  head="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
  stamp="${head} ${APP_VERSION}"
  if [ "${REBUILD:-0}" != 1 ] && [ -z "${OVERLAY:-}" ] && [ -f "${site}/main.dart.js" ] \
    && [ "$(cat "${site}.stamp" 2>/dev/null)" = "${stamp}" ]; then
    say "reusing ${site} (${stamp})"
    return 0
  fi
  if [ "${kind}" = hook ]; then
    base=/
    defines=--dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true
  else
    base="/Notechondria/${app}/"
  fi
  work="${NC_VERIFY_DIR}/lfv_build_${kind}_${app}"
  scratch_copy "${work}"
  run_heavy "$(lfv_name "build-${kind}-${app}")" 1500 "${FLUTTER_DOCKER[@]}" \
    -v "${work}:/work" -w "/work/frontend/${app}_app" "${FLUTTER_IMAGE}" bash -c "${CONTAINER_PRELUDE}
      step pubget_${app}_app 300 flutter pub get
      step ${kind}build_${app}_app 900 flutter build web --release --base-href ${base} \
        --no-web-resources-cdn --dart-define=APP_VERSION=\${APP_VERSION} ${defines}" \
    || fail "${kind} build of ${app} did not finish: container exit $? (137 = killed by the timeout)."
  summarize "${work}"
  publish_site "${work}/frontend/${app}_app/build/web" "${kind}" "${app}"
}

# publish_site <build/web dir> <hook|release> <app>: copies a build into
# $SITES_DIR; the stamp is written only for a pure-HEAD build (no OVERLAY).
publish_site() {
  local src="$1" site="${SITES_DIR}/$2_$3_app"
  rm -rf "${site}" "${site}.stamp"
  mkdir -p "${SITES_DIR}"
  cp -r "${src}" "${site}"
  if [ -z "${OVERLAY:-}" ]; then
    printf '%s %s\n' "$(git -C "${REPO_ROOT}" rev-parse --short HEAD)" "${APP_VERSION}" > "${site}.stamp"
  fi
  say "site ${site} ready"
}

# run_driver <label> <site dir> <driver> <result file> [docker args...]:
# runs drivers/<driver> with `dart run` in $CHROMIUM_IMAGE under
# --network none, the site read-only at /site and $NC_VERIFY_DIR/lfv_<label>
# at /work. Passes when the driver exits 0 and every listener it recorded in
# <result file> is on loopback.
run_driver() {
  local label="$1" site="$2" driver="$3" result_name="$4" work result status=0
  shift 4
  work="${NC_VERIFY_DIR}/lfv_${label}"
  rm -rf "${work}"
  mkdir -p "${work}"
  cp "${DRIVERS_DIR}/${driver}" "${work}/driver.dart"
  say "driver ${driver}, site ${site}, APP_VERSION ${APP_VERSION}, output ${work}"
  run_heavy "$(lfv_name "${label}")" 900 --network none "${OWNER_DOCKER[@]}" "$@" \
    -v "${site}:/site:ro" -v "${work}:/work" "${CHROMIUM_IMAGE}" \
    bash -c 'trap "chown -R ${HOST_UID}:${HOST_GID} /work" EXIT; timeout 840 dart run /work/driver.dart' \
    > "${work}/stdout.txt" 2>&1 || status=$?
  result="$(find "${work}" -name "${result_name}" -print -quit)"
  grep -E '"(pass|api_after_boot|driver_error)"|: (true|false)",?$' "${work}/stdout.txt" \
    | sed 's/^ */  /' || true
  [ -n "${result}" ] || fail "the driver wrote no ${result_name} (container exit ${status}); see ${work}/stdout.txt."
  check_listeners "${result}"
  [ "${status}" -eq 0 ] \
    || fail "the driver reported a failure (exit ${status}; 1 = a check failed, 137 = killed by the timeout); see ${result}."
  say "passed; evidence in $(dirname "${result}")"
}
