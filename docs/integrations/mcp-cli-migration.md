# MCP → standalone CLI migration proposal

Proposal to move the Model Context Protocol (MCP) server out of the
Django backend and into a standalone CLI app that talks to the backend
over the public `/api/v1/` HTTP surface. Written at 0.1.135.

Status: **Phases 1–3 done (through 0.1.146)** — the audit confirmed
every MCP tool maps to `/api/v1/` (one missing `note-sessions` GET added
in 0.1.146), and the CLI in [`cli/`](../../cli/) now implements all 41
tools at parity with `backend/mcp/tools.py`. The in-backend `/mcp/`
endpoint keeps working unchanged. Remaining: Phase 4 (PyPI) + Phase 5
(deferred cutover).

## Owner decisions (locked 0.1.138)

- **Keep both.** `/mcp/` (HTTP, in-backend) and the CLI (stdio) both
  stay — separate endpoints/transports, **shared authentication** (the
  `ntc_` API key). One API key per user (already the case —
  `Creator.api_key_hash` is a single field).
- **Location:** the CLI lives in this repo's [`cli/`](../../cli/)
  directory for now but is an **independent program** (own
  `pyproject.toml`, no imports from `backend/`); it may move to its own
  repo later.
- **Language:** **Python**.
- **Cadence:** keep `/mcp/` until further notice (no cutover/deletion
  yet).
- **Parity rule (agent-oriented development):** every new tool or
  behavior is implemented in **both** `backend/mcp/tools.py` and
  `cli/notechondria_mcp/tools.py`. The two servers must stay
  interchangeable.

## 1. Why move it

Today MCP lives inside the Django backend
([`backend/mcp/`](../../backend/mcp/)): a single `POST /mcp/`
JSON-RPC 2.0 endpoint, authenticated with `Bearer ntc_<key>`
([`creators/authentication.py`](../../backend/creators/authentication.py)),
exposing ~44 tools ([`backend/mcp/tools.py`](../../backend/mcp/tools.py))
that call the Django ORM **directly** (the tool handlers import
`notes`/`courses`/`planner` models and services, not the HTTP API).

Problems with keeping it in the backend:

- **Tight coupling.** Every tool is bound to the ORM, so the MCP
  surface can only run where the full Django app + database + secrets
  run. It cannot be distributed to a user's machine.
- **Deployment weight.** Agents that want MCP must reach the
  production backend's `/mcp/` route; there is no local/offline or
  self-hosted-against-someone-else's-backend story.
- **Coupled release cadence.** MCP tool changes ship on the backend
  release train even though the protocol layer is independent of the
  business logic.
- **Doc drift.** [`docs/server/mcp.md`](../server/mcp.md) already
  describes a stale auth header (`ApiKey nch_live_…`) vs the real
  `Bearer ntc_…`, and an outdated tool count — a symptom of the
  protocol layer and the API surface living in one place but evolving
  at different speeds.

The backend already exposes a versioned `/api/v1/` REST surface that
covers the same operations the MCP tools perform. That makes a clean
split possible: **the backend stays the source of truth and the API;
the MCP protocol layer becomes a thin client.**

## 2. Target architecture

```
┌──────────────────────────────┐        ┌──────────────────────────────┐
│ notechondria-mcp (CLI app)   │        │ Notechondria backend (Django)│
│                              │        │                              │
│  MCP server (stdio / HTTP)   │        │  /api/v1/* REST surface      │
│   initialize / tools.list /  │  HTTPS │   ApiKeyAuthentication       │
│   tools.call                 │ ─────► │   (Bearer ntc_<key>)         │
│                              │  ntc_  │                              │
│  Tool handlers → API calls   │  key   │  ORM, business logic,        │
│  Config (~/.notechondria/)   │        │  storage, skill.md           │
└──────────────────────────────┘        └──────────────────────────────┘
```

- **Transport.** Use the official MCP SDK so the protocol/transport
  (stdio for desktop agent integration, optionally Streamable HTTP) is
  not hand-rolled. Python `mcp` package or TypeScript
  `@modelcontextprotocol/sdk`. **Recommended: Python**, to match the
  backend stack and reuse request/serialization idioms.
- **Tool handlers** map each MCP tool call to one or more
  `/api/v1/...` requests with the `Authorization: Bearer ntc_<key>`
  header, then format the JSON response into MCP `content`.
- **Config** lives in `~/.notechondria/config.json` (or
  `NOTECHONDRIA_API_KEY` + `NOTECHONDRIA_API_URL` env vars): the
  backend base URL and the ntc_ key.

### What stays server-side

- PostgreSQL (source of truth), identity (Casdoor), file storage.
- The `/api/v1/` HTTP API and `ApiKeyAuthentication` (ntc_ key
  hashing/validation — unchanged; `/api/v1/auth/rotate-api-key/`
  still mints keys).
- `Creator.mcp_skill_md` storage. The CLI fetches it to populate the
  MCP `initialize` `instructions` field.

### What moves to the CLI

- The MCP protocol handler ([`backend/mcp/protocol.py`](../../backend/mcp/protocol.py)),
  the tool registry + schemas + dispatch
  ([`backend/mcp/tools.py`](../../backend/mcp/tools.py)), and session
  handling — re-implemented as API-calling handlers instead of ORM
  calls.

## 3. Auth model

Unchanged from the user's perspective: they mint an ntc_ key in
Settings → API settings (`/api/v1/auth/rotate-api-key/`), then paste
it into the CLI config. The CLI sends it as `Bearer ntc_<key>` on
every `/api/v1/` call; the backend validates it exactly as `/mcp/`
does today. No new identity surface, no OAuth in the CLI.

## 4. Backend changes required

Small and additive — none breaks the existing `/mcp/` endpoint:

1. **Expose `mcp_skill_md` over the API.** Today it is only readable
   via the MCP `initialize` response. Add `GET /api/v1/auth/mcp-skill/`
   (returns `{"mcp_skill_md": "..."}`) so the CLI can fetch it on
   startup. (Or include it in the existing settings GET payload.)
2. **Confirm `/api/v1/` covers every MCP tool operation.** Audit the
   ~44 tools against the REST surface
   ([`docs/api/backend_api_spec.md`](../api/backend_api_spec.md));
   add endpoints for any tool that currently reaches into the ORM with
   no HTTP equivalent (e.g. note-version snapshot/restore, note
   sessions, heatmap/activity-week payloads — confirm each has a
   `/api/v1/` route).
3. **CORS / headers.** Already handled by `ApiCorsMiddleware` for
   `/api/v1/`; verify the CLI's requests (server-to-server, no
   browser) are unaffected — they will be, since CORS is a browser
   concern.
4. **API stability.** Treat `/api/v1/` as a stable public contract
   for the CLI; version-lock per release (already the convention).

No database migration is needed.

## 5. Phased plan

Each phase is independently shippable; the in-backend `/mcp/` stays
live until the final cutover.

1. **Phase 1 — API gap audit (DONE, 0.1.145–0.1.146).** Mapped all 41
   MCP tools to `/api/v1/`. Every tool had a REST equivalent except
   `list_note_sessions` (the `note-sessions/` view was POST-only); a
   filtered `GET` was added + tested in 0.1.146. Doc corrected in
   [`docs/server/mcp.md`](../server/mcp.md) (auth header, 41-tool list,
   coverage table). Backend-only, fully tested. No MCP-protocol change.
2. **Phase 2 — CLI skeleton (DONE, 0.1.138).** `notechondria-mcp` in
   [`cli/`](../../cli/): config loading (env / `~/.notechondria/
   config.json`), a `requests`-based backend client, a stdio
   JSON-RPC 2.0 server (`initialize` fetching skill.md, `tools/list`,
   `tools/call`, `ping`), and a representative tool subset
   (notes CRUD, courses, planner events) calling `/api/v1/`. Unit-tested
   without network or an MCP SDK (`python -m unittest discover tests`).
   The transport is hand-rolled for now (no SDK dependency); it can
   adopt the official Python `mcp` SDK later without changing the tool
   layer.
3. **Phase 3 — full tool parity (DONE, 0.1.146).** All 41 tools from
   `backend/mcp/tools.py` are now implemented in
   `cli/notechondria_mcp/tools.py` with matching names + input schemas,
   so connected agents see no behavior change between servers. A
   name-set diff (backend vs CLI) is asserted identical; CLI dispatch is
   unit-tested without network. (Per the parity rule, future tools land
   in both servers together.)
4. **Phase 4 — distribute.** Publish to PyPI (`pip install
   notechondria-mcp`) with a `notechondria-mcp` entry point; document
   the agent-side config (stdio command + env). Optionally ship a
   PyInstaller binary on GitHub Releases for non-Python users.
5. **Phase 5 — cutover + cleanup.** Point the docs and Settings UI at
   the CLI; keep `/mcp/` for one deprecation window, then delete
   `backend/mcp/` (the app, urls, tests) and drop the `mcp` capability
   from the handshake.

## 6. Trade-offs

- **Latency.** Each tool call becomes 1+ HTTP round-trips to the
  backend instead of a local ORM query. For an interactive agent this
  is negligible; batch-heavy tools may need a `/api/v1/` bulk endpoint.
- **Two codebases.** The CLI and backend evolve separately; mitigated
  by treating `/api/v1/` as a versioned contract and sharing the tool
  schemas via the API spec doc.
- **Distribution surface.** A pip package is a new artifact to release
  and secure; offset by decoupling MCP from the backend deploy.

## 7. Open questions — resolved

All resolved 0.1.138; see "Owner decisions (locked)" at the top:
`cli/` subdirectory (independent program), Python, both servers kept
(no cutover yet), shared `ntc_` auth (one key per user), parity rule in
force. Phases 1–3 are now done (0.1.145–0.1.146); only Phase 4 (PyPI)
and the deferred Phase 5 (cutover) remain — tracked in `docs/TODO.md`.

## 8. Related docs

- [`docs/server/mcp.md`](../server/mcp.md) — current MCP design (note:
  the auth-header example there is stale; the real header is
  `Bearer ntc_<key>`). Fix as part of Phase 1.
- [`docs/api/backend_api_spec.md`](../api/backend_api_spec.md) — the
  `/api/v1/` surface the CLI will consume.
- [`docs/integrations/casdoor-migration.md`](casdoor-migration.md) —
  precedent for a phased, independently-shippable migration in this
  repo.
