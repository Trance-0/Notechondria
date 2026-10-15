# notechondria-mcp (CLI)

A standalone [MCP](https://modelcontextprotocol.io) server for
Notechondria. It runs as a local process and talks to the Notechondria
backend over the public `/api/v1` surface using an `ntc_` API key —
the **same credential and the same tools** as the in-backend `/mcp/`
endpoint, just decoupled from the Django app.

This lives in the repo for now but is an **independent program**
(its own `pyproject.toml`, no imports from `backend/`); it may move to
its own repository later. See
[`docs/integrations/mcp-cli-migration.md`](../docs/integrations/mcp-cli-migration.md)
for the full migration plan and phasing.

> **Parity rule (agent-oriented development):** every new tool or
> behavior must be implemented in **both** this CLI
> (`notechondria_mcp/tools.py`) and the backend MCP
> (`backend/mcp/tools.py`). The two servers must stay interchangeable.

## Install

```bash
cd cli
pip install -e .
```

## Configure

One API key per user. Mint it in the web app: **Settings → API
settings → rotate API key** (`POST /api/v1/auth/rotate-api-key/`),
copy the `ntc_…` value (shown once).

Provide it via env vars:

```bash
export NOTECHONDRIA_API_URL="https://notechondria.trance-0.com/api/v1"
export NOTECHONDRIA_API_KEY="ntc_xxxxxxxx"
```

…or a config file at `~/.notechondria/config.json` (override the path
with `NOTECHONDRIA_CONFIG`):

```json
{ "api_url": "https://notechondria.trance-0.com/api/v1", "api_key": "ntc_xxxx" }
```

## Run

```bash
notechondria-mcp check    # verify config + backend connectivity
notechondria-mcp          # serve MCP over stdio (default)
notechondria-mcp batch tasks.jsonl   # bulk tool calls (see below)
```

### Batch mode (bulk imports)

For bulk jobs — importing a syllabus of deadlines, creating many
notes — skip the per-call JSON-RPC envelope and feed `batch` a
newline-delimited JSON file (or stdin with `-`), one
`{"tool": <name>, "arguments": {...}}` per line. Blank lines and
`#` comments are skipped; one JSON result is printed per line and
per-item failures do not stop the run (add `--stop-on-error` to
abort on the first failure). Exit code 0 = all items succeeded.

```bash
cat > syllabus.jsonl <<'EOF'
{"tool": "create_event", "arguments": {"title": "Read chapter 4", "event_date": "2026-07-15"}}
{"tool": "create_event", "arguments": {"title": "Problem set 2", "event_date": "2026-07-17", "difficulty_weight": 3}}
EOF
notechondria-mcp batch syllabus.jsonl
```

List before creating in bulk (`list_events` / `list_notes`) so reruns
do not duplicate existing items.

### Wire into an agent host

Most desktop agent hosts launch an MCP server over stdio. Example
(generic `mcpServers` config shape):

```json
{
  "mcpServers": {
    "notechondria": {
      "command": "notechondria-mcp",
      "env": {
        "NOTECHONDRIA_API_URL": "https://notechondria.trance-0.com/api/v1",
        "NOTECHONDRIA_API_KEY": "ntc_xxxxxxxx"
      }
    }
  }
}
```

### Claude Code (repo `.mcp.json`)

This repo ships a project-scoped [`.mcp.json`](../.mcp.json) at its root,
so a Claude Code session opened here picks up all 41 tools automatically —
no per-session wiring. It runs the installed `notechondria-mcp` console
script against the **deployed** backend by default.

Two one-time prerequisites (the config file holds **no secret** — the key
is read from your environment, never committed):

```bash
cd cli && pip install -e .          # puts `notechondria-mcp` on PATH
export NOTECHONDRIA_API_KEY="ntc_xxxxxxxx"   # your rotated key
# optional: point at a different backend (defaults to the deployed one)
# export NOTECHONDRIA_API_URL="http://localhost:9080/api/v1"
```

`NOTECHONDRIA_API_URL` defaults to
`https://notechondria.trance-0.com/api/v1` via `${VAR:-default}`
expansion; set the env var to override. If `NOTECHONDRIA_API_KEY` is
unset the server simply fails to connect (Claude Code reports it and
continues) — nothing else is affected.

## Tools

Full parity with the in-backend MCP since 0.1.146: all 41 tools from
`backend/mcp/tools.py` are implemented over REST with matching names,
schemas, and descriptions. The `initialize` result carries the same
baseline `instructions` operating manual
(`notechondria_mcp/instructions.py`) plus the user's `skill.md`.

## Develop / test

```bash
cd cli
python -m unittest discover tests   # no network, no MCP SDK needed
```

## Design notes

- **Transport:** newline-delimited JSON-RPC 2.0 over stdio (the MCP
  stdio convention), implemented directly (`server.py`) — no external
  MCP SDK dependency yet, so the skeleton is self-contained and
  testable. It can adopt the official `mcp` Python SDK later without
  changing the tool layer.
- **Auth:** `Authorization: Bearer ntc_<key>` on every request; the
  backend validates it with `ApiKeyAuthentication` — the same path
  `/mcp/` uses.
- **Skill.md:** `initialize` fetches the user's `mcp_skill_md` (from
  `GET /api/v1/settings/`) and returns it as the MCP `instructions`
  field, matching the in-backend server.
