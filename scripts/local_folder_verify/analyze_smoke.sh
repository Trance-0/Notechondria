#!/usr/bin/env bash
# Per-package `flutter analyze` plus tests in one Flutter container, on a
# scratch copy (HEAD plus $OVERLAY). Apps run test/smoke_test.dart; the
# shared package runs test/local_folder/ unless TEST says otherwise.
set -euo pipefail
CHECK_NAME=analyze_smoke
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [TEST="test/..."] [SKIP_ANALYZE=1] [SKIP_TEST=1] [OVERLAY="frontend/planner_app ..."]
       scripts/local_folder_verify/analyze_smoke.sh <editor|planner|portal|shared>

  TEST     test path(s) inside the package (default: test/smoke_test.dart
           for apps, test/local_folder/ for shared; "test/" runs everything)
  OVERLAY  working-tree paths copied over the HEAD scratch copy, e.g.
           OVERLAY=frontend/planner_app to check uncommitted planner edits

Baselines at 0.1.202: analyze editor 99, planner 105, portal 123, shared 7
issues, 0 errors each; smoke editor 15, planner 22, portal 23 passed;
shared test/local_folder/ 353 passed. The full shared suite (TEST=test/)
has 3 pre-existing failures in test/version_update_banner_test.dart.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  shared) pkg=notechondria_shared; default_test=test/local_folder/ ;;
  editor | planner | portal) pkg="$1_app"; default_test=test/smoke_test.dart ;;
  "") usage >&2; not_run "no package given." ;;
  *) usage >&2; not_run "unknown package '$1'; expected editor, planner, portal, or shared." ;;
esac
CHECK_NAME="analyze_smoke.${1}"

require_docker
work="${NC_VERIFY_DIR}/lfv_analyze_${1}"
scratch_copy "${work}"

script="$(cat <<'EOF'
cd "/work/frontend/${PKG}"
step "pubget_${PKG}" 300 flutter pub get
[ "${SKIP_ANALYZE}" = 1 ] || step "analyze_${PKG}" 300 flutter analyze
# TEST is split on spaces on purpose (several test paths).
[ "${SKIP_TEST}" = 1 ] || step "test_${PKG}" 900 flutter test ${TEST} -r compact
EOF
)"

run_heavy "$(lfv_name "analyze-${1}")" 1600 "${FLUTTER_DOCKER[@]}" \
  -e PKG="${pkg}" -e TEST="${TEST:-${default_test}}" \
  -e SKIP_ANALYZE="${SKIP_ANALYZE:-0}" -e SKIP_TEST="${SKIP_TEST:-0}" \
  -v "${work}:/work" -w /work/frontend "${FLUTTER_IMAGE}" bash -c "${CONTAINER_PRELUDE}
${script}" || fail "the analyze/test container did not finish: exit $? (137 = killed by the timeout)."

summarize "${work}"
say "done (scratch HEAD $(cat "${work}/base_head.txt"))"
