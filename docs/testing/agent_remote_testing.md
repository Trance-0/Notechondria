# Agent remote-testing harness

How a coding agent verifies Notechondria without the owner running
anything or reading logs. Companion to the **Urgent** section in
[`../TODO.md`](../TODO.md).

**Read first:** docs/AGENTS.md "Deployment topology &
no-local-containers rule". This project does not deploy locally —
frontend + docs on GitHub Pages, backend on Northflank on commit.
**No local containers on machines with < 16 GB RAM** (the current dev
host has 3.3 GiB and was crashed once by a full-stack build). The
Docker sections at the bottom apply only to ≥ 16 GB self-host
targets and CI.

## Verification paths (small dev host)

| What | How | When |
| --- | --- | --- |
| Backend Django suite | `.github/workflows/backend-tests.yml` (python 3.11, `settings_test`, in-memory sqlite) | CI, on push to `main` touching `backend/**` or `cli/**` |
| CLI unit tests | `cd cli && python3 -m unittest discover -s tests` — stdlib only, runs on host python | locally, any time |
| Frontend smoke + web builds | `.github/workflows/frontend-pages.yml` (flutter test + build per app) | CI, on push touching `frontend/**` |
| Docs build + SUMMARY drift check | `.github/workflows/docs-pages.yml` (mdBook; fails if `versions/<VERSION>.md` is missing from SUMMARY.md) | CI, on push touching `docs/**` / `VERSION` |
| Deployed backend probe | `curl https://notechondria.trance-0.com/api/v1/handshake/` — version/build block confirms what Northflank is serving | after a push, to confirm the deploy landed |
| Deployed MCP probe | `POST /mcp/` `tools/list` with a real `ntc_` key (owner-minted; `seed_agent_user` is guarded off in production) | only with an owner-provided key |

The agent workflow is therefore: edit → run what runs on host python →
commit (never push) → the owner pushes → CI proves the suites and
Pages/Northflank deploy → probe the deployed handshake if the round
needs live confirmation.

## Local test identity (CI / big-host contexts only)

`python manage.py seed_agent_user` (guarded by `DEBUG=True` or
`ALLOW_AGENT_SEED=1`) creates the `agent-tester` user and prints a
fresh key as a greppable `NOTECHONDRIA_API_KEY=...` last line. Never
set `ALLOW_AGENT_SEED` on a production deployment.

## Reference: Docker verification (≥ 16 GB hosts and CI only)

Kept for self-host targets; forbidden on the small dev host.

```bash
docker compose build app
docker compose run --rm --no-deps \
  -e DJANGO_SETTINGS_MODULE=notechondria.settings_test \
  --entrypoint "" app python manage.py test          # backend suite
docker build --target frontend_test -f frontend/<app>/Dockerfile frontend/  # per-app smoke
docker compose up -d && curl -s localhost:8080/api/v1/handshake/            # full stack
```

Resource discipline still applies everywhere (docs/AGENTS.md "Host
resource budget"): measure `free -h` first, ≤ 70% of remaining RAM,
`--memory` caps, `timeout` wraps, kill after 5 silent minutes, one
heavy job at a time.

## Port map (historical, small dev host)

Compose defaults 8080 (gateway) / 9060 (backend nginx) / 9032 (db)
were verified free on 2026-07-07; the host also runs frps
(6000–6099, 7000, 7500, 10080, 10443), portainer (8000, 9443), and
openresty (80/443). Verify with `ss -tlnp` before any assignment on
any machine.
