#!/usr/bin/env bash
# U3 user-activation spike (design 1.2, 11.1): does a real click on the
# editor's Flutter "Use a local folder (no account)" button reach
# window.showDirectoryPicker with a transient user activation? The driver
# (drivers/u3_driver.dart) wraps the real picker, clicks with trusted CDP
# input once through semantics and once through Flutter's pointer path, and
# runs a control call without a gesture, which must fail with SecurityError.
# Headless Chromium then answers the real picker with AbortError, which is
# the expected outcome. --network none, no published port.
set -euo pipefail
CHECK_NAME=u3_spike
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [REBUILD=1] [OVERLAY="..."] scripts/local_folder_verify/u3_spike.sh

Serves the editor hook build ($NC_VERIFY_DIR/lfv_sites/hook_editor_app,
base href "/"); no app code calls the hook, so it behaves like the release
build the spike first used. Baseline (Phase 2): both clicks isActive true
then AbortError; the control call SecurityError.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; not_run "unexpected argument '$1'." ;;
esac

require_docker
require_image "${CHROMIUM_IMAGE}"
ensure_site hook editor
run_driver u3 "${SITES_DIR}/hook_editor_app" u3_driver.dart u3_result.json
