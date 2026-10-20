#!/usr/bin/env bash
# One-time build of the Chromium + Flutter image (Dockerfile.chromium),
# tagged $CHROMIUM_IMAGE (default nc-flutter-chromium:local). Pulls the
# Flutter and Playwright base images (about 7 GB) and runs
# `flutter precache --web`; needs network access. The build context is
# empty: the Dockerfile copies nothing from the repo.
set -euo pipefail
CHECK_NAME=build_image
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [CHROMIUM_IMAGE=nc-flutter-chromium:local] [FLUTTER_IMAGE=ghcr.io/cirruslabs/flutter:stable]
       scripts/local_folder_verify/build_image.sh

Pin FLUTTER_IMAGE to a versioned tag that matches CI if :stable has moved
past 3.44.0, the version these checks were verified with.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; not_run "unexpected argument '$1'." ;;
esac

require_docker
mkdir -p "${NC_VERIFY_DIR}"
say "building ${CHROMIUM_IMAGE} from ${FLUTTER_IMAGE} (waiting for ${NC_VERIFY_DIR}/flutter.lock)"
flock "${NC_VERIFY_DIR}/flutter.lock" timeout --signal=KILL 3600 \
  docker build --build-arg FLUTTER_IMAGE="${FLUTTER_IMAGE}" -t "${CHROMIUM_IMAGE}" - \
  < "${LFV_DIR}/Dockerfile.chromium" \
  || fail "image ${CHROMIUM_IMAGE} not built: docker build exited $? (137 = killed after 3600 s)."

timeout 120 docker run --rm --network none --memory "${NC_MEMORY}" "${CHROMIUM_IMAGE}" sh -c \
  'flutter --version 2>&1 | head -1; /usr/local/bin/chromium-no-sandbox --version; ls /ms-playwright' \
  || fail "image ${CHROMIUM_IMAGE} built but its self-check failed (flutter, Chromium wrapper, or /ms-playwright missing)."
say "image ${CHROMIUM_IMAGE} ready"
