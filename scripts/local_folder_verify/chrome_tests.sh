#!/usr/bin/env bash
# The shared package's Chromium/OPFS tests (testing.md 8.3) in the image
# from build_image.sh, with --dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true.
# The network stays on because the web test runner runs `pub get` for
# flutter_tools; nothing is published, and /proc/net/tcp{,6} is sampled
# every second so the run proves every listener (the test server and
# Chrome's DevTools port) is on loopback.
set -euo pipefail
CHECK_NAME=chrome_tests
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [TESTS="test/... test/..."] [OVERLAY="frontend/notechondria_shared"]
       scripts/local_folder_verify/chrome_tests.sh

  TESTS    default: test/local_folder_opfs_test.dart
                    test/local_folder_opfs_timing_test.dart
  OVERLAY  working-tree paths copied over the HEAD scratch copy

Baseline at 0.1.202: 8 passed (the OPFS test 7, the timing test 1, about
30 s). The timing test fails when a timed step holds the folder lock for
2 s or more. The shared package's explicit pub get exits 1 on the known
activityWeightN gen-l10n error after resolving packages; that is accepted.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; not_run "unexpected argument '$1'." ;;
esac

require_docker
require_image "${CHROMIUM_IMAGE}"
work="${NC_VERIFY_DIR}/lfv_chrome"
scratch_copy "${work}"

script="$(cat <<'EOF'
cd /work/frontend/notechondria_shared
step pubget_shared 300 flutter pub get
( for _ in $(seq 1 1500); do
    { date +%T
      awk '$4 == "0A" {print "tcp", $2}' /proc/net/tcp
      awk '$4 == "0A" {print "tcp6", $2}' /proc/net/tcp6; } >> /work/logs/listeners.txt
    sleep 1
  done ) &
sampler=$!
# TESTS is split on spaces on purpose (several test files).
step test_chrome 1500 flutter test --platform chrome \
  --dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true ${TESTS} -r expanded
kill "${sampler}" 2>/dev/null
EOF
)"

run_heavy "$(lfv_name chrome)" 1900 "${FLUTTER_DOCKER[@]}" \
  -e TESTS="${TESTS:-test/local_folder_opfs_test.dart test/local_folder_opfs_timing_test.dart}" \
  -v "${work}:/work" -w /work/frontend "${CHROMIUM_IMAGE}" bash -c "${CONTAINER_PRELUDE}
${script}" || fail "the Chromium test container did not finish: exit $? (137 = killed by the timeout)."

summarize "${work}"
check_listeners "${work}/logs/listeners.txt"
say "done (scratch HEAD $(cat "${work}/base_head.txt")); full log ${work}/logs/test_chrome.txt"
