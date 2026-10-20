#!/usr/bin/env bash
# Backend contract test (notes.test_api_contract) in python:3.11-slim: it
# sends each fixture request in frontend/notechondria_shared/test/fixtures/
# api_v1/ to the real Django API and compares keys and JSON types, so the
# local folder router and the backend cannot drift apart (testing.md 8.4).
# The scratch copy holds backend/ and the fixtures; the network is used
# only by pip; nothing listens and nothing is published.
set -euo pipefail
CHECK_NAME=backend_contract
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

usage() {
  cat <<'EOF'
Usage: [OVERLAY="backend frontend/notechondria_shared/test/fixtures"] [BACKEND_MEMORY=2g]
       scripts/local_folder_verify/backend_contract.sh

Baseline at 0.1.202: OK with 42 live responses (44 fixture files, 2 marked
"_backend_route": false). Live responses land in
$NC_VERIFY_DIR/lfv_backend/backend/build/contract_responses/.
EOF
}
case "${1:-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; not_run "unexpected argument '$1'." ;;
esac

require_docker
work="${NC_VERIFY_DIR}/lfv_backend"
scratch_copy "${work}" backend frontend/notechondria_shared/test/fixtures
mkdir -p "${NC_VERIFY_DIR}/pip-cache"

script="$(cat <<'EOF'
cd /work/backend
step pip 600 pip install -q -r requirements.txt
export DJANGO_SETTINGS_MODULE=notechondria.settings_test
step contract 300 python manage.py test notes.test_api_contract -v 2
EOF
)"

NC_MEMORY="${BACKEND_MEMORY:-2g}" run_heavy "$(lfv_name backend)" 1200 "${OWNER_DOCKER[@]}" \
  -e PIP_CACHE_DIR=/pip-cache -v "${NC_VERIFY_DIR}/pip-cache:/pip-cache" \
  -v "${work}:/work" -w /work/backend "${PYTHON_IMAGE}" bash -c "${CONTAINER_PRELUDE}
${script}" || fail "the backend container did not finish: exit $? (137 = killed by the timeout)."

summarize "${work}"
grep -E '^(Ran |OK|FAILED)' "${work}/logs/contract.txt" | sed 's/^/  /' || true
responses="${work}/backend/build/contract_responses"
say "live responses: $(find "${responses}" -name '*.json' 2>/dev/null | wc -l) in ${responses}"
