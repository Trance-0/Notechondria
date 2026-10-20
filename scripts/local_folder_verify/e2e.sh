#!/usr/bin/env bash
# Browser end-to-end run of local folder mode in headless Chromium:
# drivers/e2e_editor_driver.dart (editor) or drivers/e2e_driver.dart
# (planner, portal) serve the app's OPFS hook build on 127.0.0.1:8099 and
# drive the real UI over DevTools on 127.0.0.1:9222. Headless Chromium
# answers the real directory picker with AbortError (U3), so the driver
# makes window.showDirectoryPicker return an OPFS directory; everything
# after the picker is the production path. The container runs with
# --network none and no published port.
set -euo pipefail
CHECK_NAME=e2e
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [LOCAL_ROBOTO=1] [REBUILD=1] [OVERLAY="..."]
       scripts/local_folder_verify/e2e.sh <editor|planner|portal>

  LOCAL_ROBOTO=1  answer fonts.gstatic.com Roboto requests with the Flutter
                  SDK's Roboto (planner/portal driver) so screenshots show text
  REBUILD=1       rebuild the hook build even if a current one exists
  OVERLAY         working-tree paths for the hook build (forces a rebuild)

Uses $NC_VERIFY_DIR/lfv_sites/hook_<app>_app (from ci.sh, or built here).
Baselines: editor 7/7 steps (0.1.201), planner 6/6 and portal 6/6 steps
(0.1.202), 0 /api/ requests after the boot phase.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") usage >&2; not_run "no app given." ;;
esac
app="$1"
check_app "${app}"
CHECK_NAME="e2e.${app}"

require_docker
require_image "${CHROMIUM_IMAGE}"
ensure_site hook "${app}"

driver=e2e_driver.dart
[ "${app}" != editor ] || driver=e2e_editor_driver.dart
run_driver "e2e_${app}" "${SITES_DIR}/hook_${app}_app" "${driver}" e2e_result.json \
  -e APP="${app}" -e LOCAL_ROBOTO="${LOCAL_ROBOTO:-0}"
