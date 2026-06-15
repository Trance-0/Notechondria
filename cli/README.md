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
```

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

## Tools

A representative subset of the backend MCP surface is implemented:
`get_profile`, `list_notes`, `get_note`, `create_note`, `update_note`,
`delete_note`, `list_courses`, `get_course`, `create_course`,
`list_events`, `create_event`. The remaining tools are ported in
Phase 3 (keep parity with `backend/mcp/tools.py`).

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
