# `mcp` app

Path: [`backend/mcp/`](../../backend/mcp/).
Responsibility: Model-Context-Protocol server. 21 tools that wrap
the [`creators`](creators.md) and [`notes`](notes.md) APIs so an
external LLM client can read and mutate a user's workspace.

Index: [`server/backend.md`](backend.md).

## Mounting

`backend/notechondria/urls.py` includes
`path('mcp/', include('mcp.urls'))`. The MCP endpoint is at
`/mcp/` (no `/api/v1/` prefix, by design — MCP is a separate
protocol surface).

## Authentication

`ApiKeyAuthentication` from
[`creators/authentication.py`](creators.md#authentication). Header:

```http
Authorization: ApiKey nch_live_<secret>
```

Calls without a valid API key return `401`.

The frontend Settings UI mints API keys via
`POST /api/v1/auth/rotate-api-key/` (see
[`creators` app — Password / email / identity](creators.md#password--email--identity))
and shows the user the resulting MCP endpoint URL plus the
plaintext key (once). The `mcp_endpoint` field in the rotation
response is the absolute URL clients should configure.

## Tools (`mcp/tools.py`)

21 tools, each importing lazily from `notes.services` /
`creators.api` to keep startup cheap. Categories:

- **Discovery**: `list_courses`, `get_course`, `list_notes`,
  `get_note`, `search_notes`.
- **Mutation**: `create_note`, `update_note`, `delete_note`,
  `restore_note`, `create_course`, `update_course`,
  `delete_course`.
- **Blocks**: `list_blocks`, `create_block`, `update_block`,
  `delete_block`, `reorder_blocks`.
- **Planner**: `list_planner_events`, `create_planner_event`,
  `complete_planner_event`.
- **Account**: `whoami` (returns the current creator's profile +
  API-key hash prefix).

Each tool resolves the calling user from the API key, then
delegates to the existing services / view logic. The MCP layer
adds no business rules of its own — if the underlying API would
401/403/404, the tool returns the same error.

## Tests

`mcp/tests.py` — 39 tests covering: API-key auth happy-path and
failure modes, every tool's request/response shape, and the
"tool found via discovery" handshake.

Run:

```bash
DJANGO_SETTINGS_MODULE=notechondria.settings_test \
  python manage.py test mcp
```

(in-memory sqlite, no PostgreSQL required).

## Frontend cross-refs

The MCP endpoint is exposed in:

- [editor_app Settings → API Key section](../client/editor_app.md)
  — the rotate button + `mcp_endpoint` helper text.
- Portal/planner ports tracked in [TODO.md](../TODO.md) under
  "Login and account info".

## Notes

- The MCP server does not depend on the stubbed
  [`gptutils`](backend.md#gptutils-app-stubbed) app. They live in
  the same project but are independent surfaces.
- API keys are revoked by `rotate-api-key` issuing a new one —
  there is no separate revoke endpoint yet (TODO).
