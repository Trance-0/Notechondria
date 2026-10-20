#!/usr/bin/env bash
# CI-equivalent run of .github/workflows/frontend-pages.yml for local folder
# mode, in one Flutter container: per app pub get, smoke test, and release
# web build (APP_VERSION from VERSION, base href /Notechondria/<app>/); then
# the shared `flutter test test/local_folder/ -r compact` without a pub get,
# as CI runs it; then the OPFS hook builds (base href "/") that e2e.sh and
# u3_spike.sh serve. On the host it greps every release main.dart.js for
# the hook strings (must be 0) and checks the dominant version string.
set -euo pipefail
CHECK_NAME=ci
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [APPS="editor planner portal"] [HOOK_APPS="..."] [SKIP_SHARED=1]
       [OVERLAY="frontend/planner_app ..."] scripts/local_folder_verify/ci.sh

  APPS        apps to smoke-test and release-build (default: all three)
  HOOK_APPS   apps to hook-build for e2e.sh/u3_spike.sh (default: $APPS;
              set it empty to skip the hook builds)
  SKIP_SHARED 1 skips the shared test/local_folder/ step
  OVERLAY     working-tree paths copied over the HEAD scratch copy

Baselines at 0.1.202: smoke editor 15, planner 22, portal 23 passed;
shared local_folder 353 passed; 0 hook strings in every release bundle.
Logs: $NC_VERIFY_DIR/lfv_ci/logs/ (default /tmp/nc_verify/lfv_ci/logs/).
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; not_run "unexpected argument '$1'." ;;
esac

require_docker
APPS="${APPS:-editor planner portal}"
HOOK_APPS="${HOOK_APPS-${APPS}}"
for a in ${APPS} ${HOOK_APPS}; do check_app "${a}"; done

work="${NC_VERIFY_DIR}/lfv_ci"
scratch_copy "${work}"

# Each step is bounded inside the container; the outer timeout is their sum.
napps=$(wc -w <<< "${APPS}")
nhook=$(wc -w <<< "${HOOK_APPS}")
limit=$((600 + napps * 2100 + 900 + nhook * 1200))

script="$(cat <<'EOF'
flutter --version 2>&1 | head -1
for a in ${APPS}; do
  cd "/work/frontend/${a}_app"
  step "pubget_${a}_app" 300 flutter pub get
  step "smoke_${a}_app" 900 flutter test test/smoke_test.dart -r compact
  step "build_${a}_app" 900 flutter build web --release --base-href "/Notechondria/${a}/" \
    --no-web-resources-cdn --dart-define=APP_VERSION="${APP_VERSION}" \
    && rm -rf "/work/release_${a}_app" && cp -r build/web "/work/release_${a}_app"
done
if [ "${SKIP_SHARED}" != 1 ]; then
  cd /work/frontend/notechondria_shared
  step shared_local_folder 900 flutter test test/local_folder/ -r compact
fi
for a in ${HOOK_APPS}; do
  cd "/work/frontend/${a}_app"
  [ -f .dart_tool/package_config.json ] || step "pubget_${a}_app_hook" 300 flutter pub get
  step "hookbuild_${a}_app" 900 flutter build web --release --base-href / --no-web-resources-cdn \
    --dart-define=APP_VERSION="${APP_VERSION}" --dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true \
    && rm -rf "/work/hook_${a}_app" && cp -r build/web "/work/hook_${a}_app"
done
EOF
)"

say "apps: ${APPS}; hook builds: ${HOOK_APPS:-none}; shared: $([ "${SKIP_SHARED:-0}" = 1 ] && echo skipped || echo yes); APP_VERSION ${APP_VERSION}"
run_heavy "$(lfv_name ci)" "${limit}" "${FLUTTER_DOCKER[@]}" \
  -e APPS="${APPS}" -e HOOK_APPS="${HOOK_APPS}" -e SKIP_SHARED="${SKIP_SHARED:-0}" \
  -v "${work}:/work" -w /work/frontend "${FLUTTER_IMAGE}" bash -c "${CONTAINER_PRELUDE}
${script}" || fail "the CI container did not finish: exit $? (137 = killed by the ${limit} s timeout)."

summarize "${work}"

# Release bundles must not contain the OPFS test hook (testing.md 8.3, Q13)
# and must report APP_VERSION most often (docs/AGENTS.md round-end checks).
hook_re='NOTECHONDRIA_TEST_OPFS_FOLDER|notechondria-opfs-test-hook'
ver_re="${APP_VERSION%.*}"
ver_re="${ver_re//./\\.}\\.[0-9]+"
bad=""
for a in ${APPS}; do
  js="${work}/release_${a}_app/main.dart.js"
  [ -f "${js}" ] || { bad+=" ${a}(no release bundle)"; continue; }
  hits=$( (grep -oE "${hook_re}" "${js}" || true) | wc -l)
  top=$( (grep -oE "${ver_re}" "${js}" || true) | sort | uniq -c | sort -rn | awk 'NR == 1 {print $2}')
  say "release ${a}: hook strings ${hits}, dominant version ${top:-none}"
  [ "${hits}" -eq 0 ] || bad+=" ${a}(hook strings ${hits})"
  [ "${top}" = "${APP_VERSION}" ] || bad+=" ${a}(version ${top:-none})"
  publish_site "${work}/release_${a}_app" release "${a}"
done
for a in ${HOOK_APPS}; do
  js="${work}/hook_${a}_app/main.dart.js"
  [ -f "${js}" ] || { bad+=" ${a}(no hook bundle)"; continue; }
  say "hook build ${a}: hook strings $( (grep -oE "${hook_re}" "${js}" || true) | wc -l) (0 expected while no app code calls the hook)"
  publish_site "${work}/hook_${a}_app" hook "${a}"
done
[ -z "${bad}" ] || fail "bundle check failed:${bad}."
say "all steps passed (scratch HEAD $(cat "${work}/base_head.txt"))"
