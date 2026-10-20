#!/usr/bin/env bash
# Firefox check: an app's release build in Playwright's Firefox 132
# (headless, driven over WebDriver BiDi on 127.0.0.1:9223 by
# drivers/ff_driver.dart) must show "Use a local folder (no account)"
# disabled with the noDirectoryPicker gap message, because Firefox has no
# window.showDirectoryPicker. The image from build_image.sh is
# Playwright-based, so it carries the same Firefox build (firefox-1466) the
# 0.1.202 check used. --network none, no published port.
set -euo pipefail
CHECK_NAME=firefox
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [REBUILD=1] [OVERLAY="..."] scripts/local_folder_verify/firefox.sh <editor|planner|portal>

Uses $NC_VERIFY_DIR/lfv_sites/release_<app>_app (from ci.sh, or built here).
Baselines: editor (0.1.201) and planner (0.1.202) passed: option disabled,
gap message names window.showDirectoryPicker. The portal was not run yet.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") usage >&2; not_run "no app given." ;;
esac
app="$1"
check_app "${app}"
CHECK_NAME="firefox.${app}"

require_docker
require_image "${CHROMIUM_IMAGE}"
ensure_site release "${app}"
run_driver "ff_${app}" "${SITES_DIR}/release_${app}_app" ff_driver.dart ff_result.json -e APP="${app}"
