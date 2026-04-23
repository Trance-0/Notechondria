# Backend (`backend/`)

Django 4.2 + Django REST Framework + PostgreSQL. Single backend that
serves all three Flutter frontends ([editor](../client/editor_app.md),
[planner](../client/planner_app.md), [portal](../client/portal_app.md))
over one versioned API surface.

Related: [agent rules (§0)](../index.md#0-project-specific-overrides),
[Render free-tier deploy](../deployment/render_free_tier.md),
[Northflank deploy](../deployment/northflank.md),
[PostgreSQL migration](../operations/postgres_migration.md).

## Runtime shape

- Python pinned to 3.9 (the Dockerfile bases on `python:3.9.18-bullseye`).
  PEP 604 unions (`X | Y`) don't work at runtime — use `typing.Optional`.
  See [index.md §0](../index.md#0-project-specific-overrides).
- Settings: `backend/notechondria/settings.py` for prod,
  `backend/notechondria/settings_test.py` for test (in-memory sqlite,
  MD5 password hasher, LOGGING stubbed).
- ASGI/WSGI: `backend/notechondria/wsgi.py`, launched by gunicorn via
  `backend/entrypoint.sh` (which also runs `migrate --check`, seeds
  the platform, collects static, then `exec "$@"`).
- Middleware order (settings.py `MIDDLEWARE`):
  [`RequestTimingMiddleware`](#request-timing-middleware) →
  `SecurityMiddleware` → `WhiteNoiseMiddleware` →
  `SessionMiddleware` →
  [`ApiCorsMiddleware`](#api-cors-middleware) → `CommonMiddleware` →
  `CsrfViewMiddleware` → `AuthenticationMiddleware` →
  `MessageMiddleware` → `XFrameOptionsMiddleware`.

## Django apps

Four project-local apps registered in `INSTALLED_APPS`. Per-app
docs cover models, views, services, and example request/response
payloads:

| App | Path | Role | Per-app doc |
| --- | --- | --- | --- |
| `creators` | `backend/creators/` | Accounts, OAuth, API keys, settings, identity-code verification. | [creators.md](creators.md) |
| `notes` | `backend/notes/` | Notes, courses, planner events, calendar feeds, recycle bin, attachments. | [notes.md](notes.md) |
| `mcp` | `backend/mcp/` | Model-Context-Protocol server: 21 tools, API-key auth, 39 tests. | [mcp.md](mcp.md) |
| `gptutils` | `backend/gptutils/` | Parked — AI chat models stay, call sites stubbed. | [`development/ai_integration.md`](../development/ai_integration.md) |

Plus DRF (`rest_framework`, `rest_framework.authtoken`).

## URL topology

Two-level routing: project URLs at `backend/notechondria/urls.py` for
site-wide endpoints, API v1 under
`backend/notechondria/api_urls.py`.

| Route | File | Purpose |
| --- | --- | --- |
| `/` | `urls.py` → `api_views.health_check` | Liveness probe. |
| `/handshake/` | `urls.py` → `api_views.handshake` | [Handshake](#handshake) (also at `/api/v1/handshake/`). |
| `/api/v1/` | `api_urls.py` | All application endpoints. |
| `/mcp/` | `mcp/urls.py` | Model-Context-Protocol server. |
| `/auth/google/callback` | `urls.py` → `api_views.oauth_callback` | Google OAuth redirect. |
| `/auth/github/callback` | `urls.py` → `api_views.oauth_callback` | GitHub OAuth redirect. |
| `/admin/` | Django admin. | Built-in. |

Full API surface is documented in
[`docs/api/backend_api_spec.md`](../api/backend_api_spec.md).

## Per-app deep dives

The detailed model/view/services/example-payload reference for each
app lives in its own file:

- [`creators.md`](creators.md) — accounts, sessions, OAuth, API
  keys, settings, identity-code verification.
- [`notes.md`](notes.md) — notes, courses, planner events, calendar
  feeds, recycle bin, attachments, activity heatmap, version
  history. Includes `notes/services.py` helpers
  (`normalize_calendar_url`, `seed_inbox_and_welcome_note`,
  `parse_ical_datetime`).
- [`mcp.md`](mcp.md) — Model-Context-Protocol tool surface.

The remaining `gptutils` app is stubbed — see below.

## `gptutils` app (stubbed)

`backend/gptutils/`. Parked. The OpenAI SDK and `tiktoken` were
removed from both `requirements.txt` and `requirements-render.txt`
in 0.1.18; `gpt_request_parser.py` is a stub that raises
`NotImplementedError`. Models, views, forms, templates, migrations,
and URL routes are intact for future reuse when the external AI
microservice lands. See
[`docs/development/ai_integration.md`](../development/ai_integration.md).

## Handshake

Endpoint: `GET /api/v1/handshake/` (also exposed at `/handshake/` for
clients that haven't prefixed `/api/v1`).

Implementation: `backend/notechondria/api_views.py::handshake`.
Returns:

```json
{
  "service": "notechondria-backend",
  "api_version": "v1",
  "version": "<./VERSION content>",
  "capabilities": {
    "auth": 1, "notes": 1, "courses": 1, "planner": 1,
    "calendar_feeds": 1, "attachments": 1, "mcp": 1
  }
}
```

Consumers call this before committing a user-entered API base URL.
Frontend implementation lives in each
`frontend/*_app/lib/core/client.dart`'s `verifyHandshake`. See
[editor_app.md#api-client-contract](../client/editor_app.md#api-client-contract).

## Request timing middleware

`backend/notechondria/middleware.py::RequestTimingMiddleware`.

- Mounted first in `MIDDLEWARE` so it captures full end-to-end wall
  time, not just view time.
- Emits one line per request on the `notechondria.access` logger:

  ```
  <status>  <duration_ms>  <METHOD>  <path>
  ```

- Level + ANSI color:
  - 5xx OR `duration >= 2000 ms` → `logger.critical`, red.
  - 4xx OR `duration >= 500 ms`  → `logger.warning`, yellow.
  - everything else              → `logger.info`, cyan.
- Colors only emit when `stdout.isatty()` (Jenkins/Render/Northflank
  captured stdout stays clean). Force-enable with
  `DJANGO_ACCESS_LOG_FORCE_COLOR=1`.
- Thresholds (`_WARN_MS`, `_CRITICAL_MS`) are module-level constants.

## API CORS middleware

`backend/notechondria/middleware.py::ApiCorsMiddleware`.

Adds `Access-Control-Allow-*` headers on `/api/*` and `/media/*` when
the request `Origin` matches `ALLOWED_HOSTS`, `localhost`/`127.0.0.1`,
or any `CSRF_TRUSTED_ORIGINS` entry's host. Short-circuits `OPTIONS`
with a 204.

## Entrypoint (`backend/entrypoint.sh`)

Runs before gunicorn on every container start:

1. Wait up to 300 s for PostgreSQL TCP.
2. Validate DB credentials via `psycopg2.connect()`.
3. Normalize Windows-style paths in
   `DJANGO_PRODUCTION_{STATIC,MEDIA}_ROOT`.
4. `manage.py migrate --check` — if non-zero, run `migrate --noinput`.
5. `manage.py bootstrap_platform` (see
   [`resolve_codex_path` in notes.md](notes.md#management-commands)).
6. `manage.py collectstatic --noinput --clear` + a verification
   block that re-copies admin/DRF static assets if missing.
7. If `$# -eq 0`, exec a default gunicorn (added 0.1.18 so
   Northflank's `configType: "default"` works even without a CMD).
   Otherwise `exec "$@"`.

## Deploy paths

- **Render free-tier (backend only)** — `render-deploy.sh` sources
  env, then `deployment/render/scripts/render_backend_start.sh` runs
  migrate + bootstrap + collectstatic + gunicorn.
- **Docker / Jenkins (full-stack self-hosted)** —
  `backend/docker-compose.yml` + gateway nginx;
  `deployment/jenkins/scripts/` holds prep/test/deploy helpers.
- **Northflank** — `northflank.json` template provisions a
  PostgreSQL addon + a Combined Service built from `backend/Dockerfile`;
  `configType: "default"` relies on the entrypoint's gunicorn fallback.
  See [deployment/northflank.md](../deployment/northflank.md).

## Tests

- Run: `DJANGO_SETTINGS_MODULE=notechondria.settings_test python
  manage.py test` (from `backend/`).
- `settings_test.py` must keep a non-empty `SECRET_KEY` —
  [index.md §0](../index.md#0-project-specific-overrides) rule.
- See [testing/backend_test_plan.md](../testing/backend_test_plan.md)
  for the detailed plan.

## Known drift and open work

See [index.md §6](../index.md#6-open-work--caution-list). Backend-specific
live items:

- `dj-database-url` is required at runtime when `DATABASE_URL` is
  set — that's the case for Render and Northflank. Kept in
  `requirements.txt` (not render-only) after the 0.1.18 Northflank
  deploy crash.
- `manage.py migrate --check` on each boot occasionally warns
  `"Your models in app(s): 'notes' have changes that are not yet
  reflected in a migration"` — cosmetic, non-blocking, models and
  migrations were last edited in the same commit.
