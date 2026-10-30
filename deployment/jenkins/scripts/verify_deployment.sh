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

# A successful HTML response alone can hide missing compiled Flutter assets.
for app in editor planner portal; do
  for asset in main.dart.js flutter_bootstrap.js canvaskit/canvaskit.js; do
    curl --fail --silent --show-error --max-time 20 \
      "http://127.0.0.1:$PORT/$app/$asset" -o /dev/null
  done
done
python3 - "$PORT" "$ENV_FILE" <<'PY'
import json
import sys
import urllib.request
from pathlib import Path
port, env_path = sys.argv[1:]
values = dict(line.split('=', 1) for line in Path(env_path).read_text().splitlines()
              if '=' in line and not line.startswith('#'))
base = f'http://127.0.0.1:{port}/api/v1/'
with urllib.request.urlopen(base + 'handshake/', timeout=10) as response:
    handshake = json.load(response)
if not isinstance(handshake, dict):
    raise SystemExit('Deployment unverified: Jenkins.Deploy/handshake — API returned a non-object response')
with urllib.request.urlopen(base + 'auth/casdoor/config/', timeout=10) as response:
    config = json.load(response)
if values.get('CASDOOR_CLIENT_ID') and not config.get('configured'):
    raise SystemExit('SSO unavailable: Jenkins.Deploy/casdoor — env contains a client ID but backend reports unconfigured')
print('Integration configuration verified: Jenkins.Deploy/casdoor — backend configuration matches deployment env')
PY
