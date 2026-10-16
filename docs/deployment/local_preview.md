# Local preview against the remote backend

A loopback-only deploy of the three web apps, built from the current
checkout and backed by the production API at
`https://notechondria.trance-0.com`. It runs no local backend or database
and stores no credentials. Use it to check frontend changes against real
data before they reach Pages.

Added at the owner's request on 2026-10-15. It is allowed only on hosts
with at least 16 GB RAM; the resource-budget rules in
[`../AGENTS.md`](../AGENTS.md) still apply.

## Commands

```bash
free -h && nproc && docker ps          # budget check first
scripts/local_remote_deploy.sh up      # build 3 images one at a time, then (re)start
scripts/local_remote_deploy.sh down    # stop and remove the containers (images kept)
```

`up` prints the URLs when the gateway answers:

- `http://127.0.0.1:9068/portal/` (`/` redirects here)
- `http://127.0.0.1:9068/editor/`
- `http://127.0.0.1:9068/planner/`

## Shape

| Container | Image | Published |
| --- | --- | --- |
| `notechondria-local-gateway` | `nginx:1.27-alpine` + `deployment/docker/nginx/local_remote.conf.template` | `127.0.0.1:9068` only |
| `notechondria-local-{portal,editor,planner}` | `notechondria-local-<app>:latest` from `frontend/<app>_app/Dockerfile` | nothing |

- All four containers share the private `notechondria-local` network.
- The gateway forwards `/api/`, `/media/`, and `/static/` to the remote with
  the remote's own Host header and verified TLS. The apps call same-origin
  `/api/v1` on loopback, so the proxy is required.
- Images are stamped with the repo-root `VERSION` through the `APP_VERSION`
  build arg, so the version banner stays hidden when the backend runs the
  same version.
- Containers run with `--restart unless-stopped` and come back after a
  Docker daemon or devspace restart. `down` removes them.
- Env vars: `LOCAL_GATEWAY_HOST_PORT` (default `9068`, always bound to
  `127.0.0.1`) and `REMOTE_BACKEND_ORIGIN` (default
  `https://notechondria.trance-0.com`, `scheme://host[:port]` only).

## Verify

```bash
docker ps --format '{{.Names}}\t{{.Ports}}'      # only 127.0.0.1:9068->80/tcp
curl -sS --max-time 20 -o /dev/null -w '%{http_code} %{content_type}\n' \
  http://127.0.0.1:9068/api/v1/front-page/       # 200 application/json
for app in portal editor planner; do
  curl -s http://127.0.0.1:9068/$app/main.dart.js \
    | grep -oE '"0\.1\.[0-9]+"' | sort | uniq -c | sort -rn | head -1
done                                             # each shows "$(cat VERSION)"
```

Signed-in use touches production data. Tokens stay in the browser's
storage for the `127.0.0.1:9068` origin. To reach the preview from another
machine, use an SSH local port forward; do not widen the bind.

The full runbook, including backend-down checks and what the version banner
means, is in
[`../development/local_dev.md`](../development/local_dev.md#web-apps-against-the-remote-backend-loopback).
