#!/usr/bin/env bash
set -Eeuo pipefail
ENV_FILE="${1:?Deployment env path required}"
PORT="$(python3 - "$ENV_FILE" <<'PY'
import sys
values = dict(line.strip().split('=', 1) for line in open(sys.argv[1]) if '=' in line and not line.startswith('#'))
print(values.get('ROOT_HTTP_PORT', '9060'))
PY
)"
for route in /api/v1/handshake/ /editor/ /planner/ /portal/; do
  passed=false
  for attempt in $(seq 1 30); do
    if curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT$route" -o /dev/null; then
      passed=true
      break
    fi
    printf 'Verification pending: Jenkins.Deploy/health — route=%s attempt=%s/30\n' "$route" "$attempt"
    sleep 5
  done
  [[ "$passed" == true ]]
  printf 'Route verified: Jenkins.Deploy/health — http://127.0.0.1:%s%s returned HTTP success\n' "$PORT" "$route"
done
