# Agent remote-testing harness

How a coding agent verifies Notechondria end-to-end on the dev host
without the owner running anything or reading logs. Companion to the
**Urgent — agent remote-test harness** section in
[`../TODO.md`](../TODO.md).

Everything runs through Docker — the host deliberately has no Flutter
SDK and its system Python is newer than the backend target, so
host-native `flutter test` / `manage.py test` are not supported paths.

## Port map (verify before assuming — LLM_CHECK rule)

Compose defaults, confirmed free on this host on 2026-07-07:

| Host port | Service |
| --- | --- |
| `8080` | `gateway_nginx` — root gateway (`/portal/`, `/editor/`, `/planner/`, `/api/v1`) |
| `9060` | `backend_nginx` — backend origin (API + static) |
| `9032` | `db` — PostgreSQL |

Re-check with `ss -tlnp` before every `up`; this host also runs frps
(6000–6099, 7000, 7500, 10080, 10443), portainer (8000, 9443), and an
openresty on 80/443.

## Full stack up / down

```bash
docker compose up --build -d          # from repo root
docker compose ps                     # all services Up
docker compose logs -f app            # backend logs, Ctrl-C safe
docker compose down                   # keep the postgres_data volume
```

The frontend images build from the `frontend/` context (fixed in
0.1.159 — the app-dir context could not see `../notechondria_shared`
and every frontend image build had been failing since the shared
package landed). App-local compose files
(`frontend/<app>/docker-compose.yml`) use `context: ..` for the same
reason.

## Backend test suite (verified 2026-07-07: 189 tests, OK)

```bash
docker compose build app
docker compose run --rm --no-deps \
  -e DJANGO_SETTINGS_MODULE=notechondria.settings_test \
  --entrypoint "" app python manage.py test
```

`settings_test` uses in-memory sqlite — no `db` service needed
(hence `--no-deps`), no secrets needed.

## Frontend smoke tests (in-Docker, no host Flutter)

Each app Dockerfile has a `frontend_test` stage that runs
`flutter test test/smoke_test.dart`:

```bash
docker compose build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  editor_frontend planner_frontend portal_frontend   # release builds
docker build --target frontend_test -f frontend/portal_app/Dockerfile frontend/
docker build --target frontend_test -f frontend/editor_app/Dockerfile frontend/
docker build --target frontend_test -f frontend/planner_app/Dockerfile frontend/
```

A green `frontend_test` build = the smoke test passed. The stages
share cached layers with the compose builds, so the marginal cost is
one `flutter test` run per app.

## API probes

With the stack up:

```bash
curl -s http://localhost:8080/api/v1/handshake/   # version + build info
curl -s http://localhost:8080/api/v1/front-page/  # front-page payload (anonymous)
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/portal/
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/editor/
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8080/planner/
```

Authenticated probes need an `ntc_` API key — until the
`seed_agent_user` management command lands (TODO, Urgent section),
mint one manually in any app: Settings → API settings → rotate API
key.

```bash
curl -s -H "Authorization: Bearer ntc_..." http://localhost:8080/api/v1/notes/
```

## MCP servers

- **In-backend** (`/mcp/`, HTTP): probe with the `ntc_` key against
  `http://localhost:8080/mcp/` — see [`../server/mcp.md`](../server/mcp.md).
- **Standalone CLI** (stdio): `pip install -e cli/` (only needs
  `requests`), then
  `NOTECHONDRIA_API_URL=http://localhost:8080/api/v1
  NOTECHONDRIA_API_KEY=ntc_... notechondria-mcp`. Unit tests:
  `python -m pytest cli/tests/ -q` (no backend required).

## Round-end convention

Before committing, a round that touched runtime code runs, in order:

1. Backend tests in-container (above) — if backend touched.
2. `frontend_test` stage per touched app.
3. Stack up + the API/page probes.
4. Anything not runnable is called out explicitly in the round
   summary with the reason (LLM_CHECK rule).
