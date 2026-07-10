# `mcp` app

Path: [`backend/mcp/`](../../backend/mcp/).
Responsibility: Model-Context-Protocol server. 41 tools that wrap
the [`creators`](creators.md) and [`notes`](notes.md) APIs so an
external LLM client can read and mutate a user's workspace.

Index: [`server/backend.md`](backend.md).

> **Parity rule.** Every MCP tool must exist in **both**
> `backend/mcp/tools.py` (this in-backend server) **and**
> `cli/notechondria_mcp/tools.py` (the standalone stdio CLI). When you
> add or change a tool, change it in both. See
> [`docs/integrations/mcp-cli-migration.md`](../integrations/mcp-cli-migration.md).

## Mounting

`backend/notechondria/urls.py` includes
`path('mcp/', include('mcp.urls'))`. The MCP endpoint is at
`/mcp/` (no `/api/v1/` prefix, by design — MCP is a separate
protocol surface).

**Reverse-proxy note (bug fixed in 0.1.160):** any gateway in front
of the backend must route `/mcp/` explicitly. The Docker full-stack
gateway (`deployment/docker/nginx/default.conf`) only proxied
`/api/` + `/admin/`, so `/mcp/` returned the gateway's 404 and the
MCP server was unreachable on that deployment path even though the
backend served it. Mirror the `/mcp/` location block when
configuring any other reverse proxy (Cloudflare, 1Panel, etc.).

## Server instructions (`initialize`)

Both servers return an `instructions` string in the `initialize`
result: the baseline operating manual in
`backend/mcp/instructions.py` (data model, workflows, batch
guidance), with the user's per-account `skill.md`
(`Creator.mcp_skill_md`) appended under a `## User skill.md` heading
when present. Parity rule: `cli/notechondria_mcp/instructions.py`
keeps the identical `BASE_INSTRUCTIONS` text.

## Agent test identity

`python manage.py seed_agent_user` (guarded: `DEBUG=True` or
`ALLOW_AGENT_SEED=1`) idempotently creates the `agent-tester` user
and prints a fresh `ntc_` key — the non-interactive path agents use
against a local stack. See
[`../testing/agent_remote_testing.md`](../testing/agent_remote_testing.md).

## Authentication

`ApiKeyAuthentication` from
[`creators/authentication.py`](creators.md#authentication). The key
prefix is `ntc_` and the scheme keyword is `Bearer`:

```http
Authorization: Bearer ntc_<secret>
```

Calls without a valid API key return `401`. The same
`ApiKeyAuthentication` is in `DEFAULT_AUTHENTICATION_CLASSES`, so an
`ntc_` key authenticates every `/api/v1/` endpoint too — the CLI uses
exactly this to talk to the REST API.

The frontend Settings UI mints API keys via
`POST /api/v1/auth/rotate-api-key/` (see
[`creators` app — Password / email / identity](creators.md#password--email--identity))
and shows the user the resulting MCP endpoint URL plus the
plaintext key (once). The `mcp_endpoint` field in the rotation
response is the absolute URL clients should configure. One key per
user; rotating issues a new key and invalidates the old one.

## Tools (`mcp/tools.py`)

41 tools, registered at import time via `register_tool(name, description,
input_schema, fn)`. Each `fn` has signature `(user, creator, params) ->
dict` and delegates to the same `notes.services` / model logic the REST
views use — the MCP layer adds no business rules of its own, so if the
underlying API would 401/403/404 the tool returns the same error.

- **Profile / account**: `get_profile`, `update_profile`.
- **Notes**: `list_notes`, `get_note`, `get_note_by_uuid`,
  `create_note`, `update_note`, `delete_note`, `search_notes`.
- **Note versions**: `list_note_versions`, `snapshot_note`,
  `restore_note_version`.
- **Attachments**: `list_attachments`, `delete_attachment`.
- **Recycle bin**: `list_deleted_notes`, `restore_deleted_note`,
  `empty_recycle_bin`.
- **Courses**: `list_courses`, `get_course`, `create_course`,
  `update_course`, `delete_course`, `list_course_notes`,
  `reorder_courses`, `subscribe_course`, `unsubscribe_course`.
- **Activity / heatmap**: `get_heatmap`, `get_recent_activity`,
  `get_activity`, `get_activity_week`.
- **Note sessions**: `list_note_sessions`, `create_note_session`,
  `end_note_session`.
- **Planner events**: `list_events`, `create_event`, `update_event`,
  `delete_event`.
- **Calendar feeds**: `list_calendar_feeds`, `create_calendar_feed`,
  `update_calendar_feed`, `delete_calendar_feed`.

## REST coverage (Phase 1 audit, 0.1.145)

Every tool operation above is also reachable over `/api/v1/`, so the
standalone CLI (which speaks plain REST with the same `ntc_` key) can
offer identical functionality. Representative mapping:

| Tool(s) | `/api/v1/` endpoint |
| --- | --- |
| `get_profile` / `update_profile` | `GET` / `PATCH` `settings/` |
| `list_notes` / `create_note` | `GET` / `POST` `notes/` |
| `get_note` / `update_note` / `delete_note` | `GET` / `PATCH` / `DELETE` `notes/<id>/` |
| `search_notes` | `GET notes/?q=&scope=` |
| `get_note_by_uuid` | `GET notes/uuid/<uuid>/` |
| `list_note_versions` | `GET notes/<id>/history/` |
| `snapshot_note` | `POST notes/<id>/snapshot/` |
| `restore_note_version` | `POST notes/<id>/restore/<version_id>/` |
| `list_attachments` / `delete_attachment` | `notes/<id>/attachments/[<aid>/]` |
| `list_deleted_notes` | `GET notes/deleted/` |
| `restore_deleted_note` | `POST notes/<id>/restore/` |
| `empty_recycle_bin` | `notes/deleted/empty/` |
| courses CRUD | `courses/[<id>/]` |
| `list_course_notes` | `GET courses/<id>/notes/` |
| `reorder_courses` | `POST courses/reorder/` |
| `subscribe_course` / `unsubscribe_course` | `POST` / `DELETE` `courses/<id>/subscribe/` |
| `get_heatmap` | `GET heatmap/` |
| `get_recent_activity` / `get_activity` | `GET activity/` |
| `get_activity_week` | `GET activity/week/` |
| `list_note_sessions` | `GET note-sessions/?note_id=&limit=` |
| `create_note_session` / `end_note_session` | `POST` / `PATCH` `note-sessions/[<id>/]` |
| planner events | `planner-events/[<id>/]` |
| calendar feeds | `calendar-feeds/[<id>/]` |

Result: one gap found and filled. The `list_note_sessions` tool had no
REST list endpoint (`NoteSessionListCreateApiView` was POST-only); a
`GET` (with `?note_id=` + `?limit=` filters) was added in 0.1.146. Every
other tool already had a REST equivalent. The standalone CLI
(`cli/notechondria_mcp/`) is at **full 41-tool parity** as of 0.1.146.

## Tests

`mcp/tests.py` — 53 tests across 4 `TestCase` classes covering:
API-key auth happy-path and failure modes, every tool's
request/response shape, the tool-discovery handshake, and the
planner-event window normalization / reopen parity with REST
(0.1.160).

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
- Portal and planner reached MCP-skill / GitHub-sync card parity
  with the editor in 0.1.91 — see
  [`docs/versions/0.1.91.md`](../versions/0.1.91.md).

## Notes

- The MCP server does not depend on the stubbed
  [`gptutils`](backend.md#gptutils-app-stubbed) app. They live in
  the same project but are independent surfaces.
- API keys are revoked by `rotate-api-key` issuing a new one —
  there is no separate revoke endpoint yet (TODO).
