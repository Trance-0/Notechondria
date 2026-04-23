# `creators` app

Path: [`backend/creators/`](../../backend/creators/).
Responsibility: accounts, sessions, OAuth, API keys, settings,
identity-code verification.

Index: [`server/backend.md`](backend.md).
Related: [`notes`](notes.md), [`mcp`](mcp.md),
[storage model](../development/storage_model.md).

## Models (`creators/models.py`)

| Model | Key fields | Purpose |
| --- | --- | --- |
| `Creator` | `user_id` (FK to `auth.User`), `image`, `motto`, `social_link`, `api_key_hash`, `api_key_prefix`, `api_base_url`, `editor_mode`, `theme_preset`, `theme_mode`, `app_settings_json`, `app_settings_updated_at` | Profile + API key binding + user's persisted preference payload. One row per `auth.User`. Access via `ensure_creator(user)` from [`backend/notechondria/utils.py`](../../backend/notechondria/utils.py). |
| `SocialAccount` | `user` (FK), `provider` (`google` / `github`), `provider_uid`, `email`, `extra_data` | OAuth identity binding. Unique on `(provider, provider_uid)`. |
| `VerificationCode` | `code` (SHA-256 hex), `expire_date`, `usage` (`R`egister / `A`uthenticate / `F`unction), `max_use` | Email-code flow. Plaintext is emailed; only the hash is stored. |
| `InvitationCode` | `code_hash`, `label`, `max_uses`, `times_used`, `expire_date` | Admin-issued invitation codes. Plaintext entered once; stored hashed. |
| `Session` *(0.1.65)* | `user` (FK — **not OneToOne**, so many-per-user), `key` (40-hex unique), `device_label`, `user_agent`, `ip_hash`, `created_at`, `last_seen_at`, `revoked_at` | Per-device authenticated session row. Backs the multi-device login manager (Telegram-style). Two timeout constants: `SESSION_IDLE_TIMEOUT = 1 day` (rolls forward on every auth'd request via `session.touch()`) and `SESSION_ABSOLUTE_TIMEOUT = 3 days` (hard cap from `created_at`). Methods: `generate_key`, `create_for_user`, `is_active`, `touch`, `revoke`. |

## Authentication

DRF `DEFAULT_AUTHENTICATION_CLASSES` (in
[`settings.py`](../../backend/notechondria/settings.py)) registers
two classes, tried in order:

1. `creators.authentication.MultiSessionAuthentication` *(0.1.65,
   replaces `rest_framework.authentication.TokenAuthentication`)*.
   Header: `Authorization: Token <40-hex>`. Looks up
   `Session.objects.get(key=…)`, enforces idle + absolute timeouts
   via `Session.is_active()`, rejects revoked rows, and calls
   `session.touch()` on every valid request so the idle window
   rolls forward. Attaches `request.auth_session` for downstream
   views (e.g. `LogoutApiView` revokes only that session).
2. `creators.authentication.ApiKeyAuthentication` — long-lived
   per-creator MCP keys. Header: `Authorization: Bearer ntc_<hex>`.
   Matches `Creator.api_key_hash` after SHA-256. Used by the MCP
   server for tool calls.

`DEFAULT_PERMISSION_CLASSES = [AllowAny]`, so each view sets its
own `permission_classes` explicitly.

### `SessionApiView` special case

`SessionApiView` (`GET /api/v1/auth/session/`) declares
**`authentication_classes = []`** so DRF's auth chain doesn't
short-circuit it with a 401. The view inspects the Authorization
header manually, does `Session.objects.get(key=…)`, and always
returns a clean 200 with `{"authenticated": true | false, …}`.
Rationale in [versions/0.1.64.md](../versions/0.1.64.md) — if
the probe endpoint itself 401'd on stale tokens, the frontend
couldn't distinguish "stale credential" from "backend broken".

## API surface (`creators/api.py`)

Mounted under `/api/v1/auth/...` by
[`api_urls.py`](../../backend/notechondria/api_urls.py). Permission
defaults shown per-endpoint.

### Registration and verification

| Method | Path | View | Auth | Notes |
| --- | --- | --- | --- | --- |
| POST | `/api/v1/auth/register/` | `RegisterApiView` | AllowAny | Body: `{username, email, password, invitation_code?}`. Sends a verification email via `SMTP_*`. |
| POST | `/api/v1/auth/validate-invitation/` | `ValidateInvitationApiView` | AllowAny | Body: `{code}`. 200 if the code is unconsumed and unexpired. |
| POST | `/api/v1/auth/verify-email/` | `VerifyEmailApiView` | AllowAny | Body: `{email, code}`. On success calls `seed_inbox_and_welcome_note(creator)` (see [`notes`](notes.md#services-notesservicespy)). |
| POST | `/api/v1/auth/resend-verification/` | `ResendVerificationApiView` | AllowAny | Body: `{email}`. Rate-limited per email. |

Example success — verify email:

```http
POST /api/v1/auth/verify-email/ HTTP/1.1
Content-Type: application/json

{"email": "alice@example.com", "code": "482910"}
```

```json
{"detail": "Email verified.", "verified": true}
```

### Login / session / logout

| Method | Path | View | Auth | Notes |
| --- | --- | --- | --- | --- |
| POST | `/api/v1/auth/login/` | `LoginApiView` | AllowAny | Body: `{username_or_email, password}`. Returns the full `auth_payload` (token, session, multi_device, user). |
| GET | `/api/v1/auth/session/` | `SessionApiView` | `authentication_classes = []` (manual lookup) | Probe: echoes the existing session + user if the saved token is still valid, else 200 with `{"authenticated": false}`. |
| POST | `/api/v1/auth/logout/` | `LogoutApiView` | MultiSession | Revokes ONLY the current session (`request.auth_session`). Other devices stay signed in. |

Example login response *(shape shared across login / register /
verify-email / OAuth — see `auth_payload` helper at
[`backend/creators/api.py:64`](../../backend/creators/api.py#L64))*:

```json
{
  "token": "9bd0a47a3b12…",
  "session": {
    "id": 412,
    "device_label": "Mac",
    "created_at": "2026-04-14T22:10:31Z",
    "last_seen_at": "2026-04-14T22:10:31Z"
  },
  "multi_device": true,
  "other_sessions_count": 2,
  "user": {
    "id": 17,
    "username": "alice",
    "email": "alice@example.com",
    "display_name": "Alice",
    "image_url": "https://cdn.trance-0.com/user_upload/user_17/profile_pic/profile_latest.png",
    "is_staff": false,
    "is_superuser": false,
    "motto": "",
    "social_link": "",
    "editor_mode": "P",
    "theme_preset": "teal",
    "theme_mode": "S",
    "api_base_url": "https://notechondria.trance-0.com/api/v1",
    "app_settings": {"log_preferences": {"level": "Info"}},
    "app_settings_updated_at": "2026-04-14T18:02:00Z"
  }
}
```

`multi_device` flips true whenever the user already had at least
one other active (non-revoked, non-expired) `Session` at the time
this one was minted, so the frontend can surface a "you're signed
in elsewhere" banner immediately after login.

### Active sessions (multi-device) — new in 0.1.65

| Method | Path | View | Auth | Notes |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/auth/sessions/` | `SessionListApiView` | MultiSession | Lists every non-revoked, non-expired `Session` the caller owns, sorted by `-last_seen_at`. |
| DELETE | `/api/v1/auth/sessions/<int:session_id>/` | `SessionRevokeApiView` | MultiSession | Revokes a specific session. Owner-scoped (404 on cross-user attempts). Revoking the caller's current session effectively signs this device out. |

Example `GET /api/v1/auth/sessions/` response:

```json
{
  "sessions": [
    {
      "id": 412,
      "device_label": "Mac",
      "user_agent": "Mozilla/5.0 … Chrome/147",
      "ip_hash_prefix": "5f3a7c91",
      "created_at": "2026-04-14T22:10:31Z",
      "last_seen_at": "2026-04-23T03:32:23Z",
      "is_current": true
    },
    {
      "id": 403,
      "device_label": "iPhone",
      "user_agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) …",
      "ip_hash_prefix": "9b04e1d0",
      "created_at": "2026-04-12T11:05:44Z",
      "last_seen_at": "2026-04-22T20:47:18Z",
      "is_current": false
    }
  ],
  "current_session_id": 412
}
```

The response **never** includes the raw `key`; the client only
needs the id to revoke, and metadata to display. The
`ip_hash_prefix` is the first 8 hex chars of SHA-256(first
X-Forwarded-For hop) — enough to flag "different network than
usual" without storing the raw IP.

Frontend client methods for these endpoints were added in 0.1.67:
`HttpNotechondriaClient.listSessions(token)` and
`revokeSession(token, sessionId)`, declared on the shared
`AuthClient` interface at
[`frontend/notechondria_shared/lib/src/app_shell/auth_client.dart`](../../frontend/notechondria_shared/lib/src/app_shell/auth_client.dart).
The Active Sessions card + multi-device warning banner are
tracked in [`docs/TODO.md`](../TODO.md) (Login and account info).

### Password / email / identity

| Method | Path | View | Auth |
| --- | --- | --- | --- |
| POST | `/api/v1/auth/password-reset/` | `PasswordResetRequestApiView` | AllowAny |
| POST | `/api/v1/auth/password-reset/confirm/` | `PasswordResetConfirmApiView` | AllowAny |
| POST | `/api/v1/auth/send-identity-code/` | `SendIdentityCodeApiView` | TokenAuth |
| POST | `/api/v1/auth/change-password/` | `ChangePasswordApiView` | TokenAuth |
| POST | `/api/v1/auth/change-email/` | `ChangeEmailApiView` | TokenAuth |
| POST | `/api/v1/auth/rotate-api-key/` | `RotateApiKeyApiView` | TokenAuth |

`change-password` and `change-email` require a fresh identity code
(emailed via `send-identity-code`) to confirm the request — same
flow as the editor app's existing dialogs.

Example rotate-api-key response:

```json
{
  "api_key": "nch_live_e4f7c9a201bd...",
  "rotated_at": "2026-04-14T22:10:31Z",
  "mcp_endpoint": "https://notechondria.trance-0.com/mcp/"
}
```

The `api_key` field is shown **once**; the backend stores only its
hash.

### OAuth

| Method | Path | View | Auth | Purpose |
| --- | --- | --- | --- | --- |
| GET  | `/api/v1/auth/oauth-config/` | `OAuthConfigApiView` | AllowAny | Returns `{google_client_id, github_client_id, ...}` so the frontend can build the provider authorize URL. |
| POST | `/api/v1/auth/google/` | `GoogleOAuthApiView` | AllowAny | Body: `{code, state}`. Exchanges the code with Google, finds-or-creates the local user via `_get_or_create_oauth_user`, returns `{token, user}`. |
| POST | `/api/v1/auth/github/` | `GitHubOAuthApiView` | AllowAny | Same flow for GitHub. |
| POST | `/api/v1/auth/bind/google/` | `BindGoogleApiView` | **TokenAuth** | Binds an existing logged-in account to a Google identity. Requires the request to be authenticated — calling this without a token returns `401 Account binding requires authentication`. |
| POST | `/api/v1/auth/bind/github/` | `BindGithubApiView` | **TokenAuth** | Same for GitHub. |
| GET  | `/api/v1/auth/social-accounts/` | `SocialAccountListApiView` | TokenAuth | Lists `CreatorOauthIdentity` rows for the current user. |
| DELETE | `/api/v1/auth/social-accounts/<provider>/` | `SocialAccountUnlinkApiView` | TokenAuth | Removes a binding. |

Example error from `bind-google` when called unauthenticated (this
is the bug surface listed in [`docs/TODO.md`](../TODO.md) — the
endpoint is not the issue, the frontend must include the user's
DRF token):

```json
{"detail": "Account binding requires authentication. Use /api/v1/auth/bind/google/."}
```

### Settings

| Method | Path | View | Auth |
| --- | --- | --- | --- |
| GET  | `/api/v1/settings/` | `SettingsApiView` | TokenAuth |
| PATCH | `/api/v1/settings/` | `SettingsApiView` | TokenAuth |

Example GET response:

```json
{
  "username": "alice",
  "email": "alice@example.com",
  "first_name": "Alice",
  "last_name": "Z",
  "motto": "build the boring stuff well",
  "social_link": "https://github.com/alice",
  "editor_mode": "M",
  "theme_preset": "teal",
  "theme_mode": "S",
  "api_base_url": "https://notechondria.trance-0.com/api/v1",
  "app_settings": {
    "log_preferences": {"level": "Info"},
    "deadline_time_weight": 1.0,
    "deadline_importance_weight": 1.0
  },
  "app_settings_updated_at": "2026-04-14T18:02:00Z"
}
```

PATCH accepts any subset of those keys plus
`api_base_url` (enforced via the frontend [handshake guard](backend.md#handshake)).

## Frontend integration cross-refs

- Login + register forms live in each app's
  `lib/modules/settings.dart` and the auth surfaces feed into
  `_LocalAppStore.saveSession({token, user})`.
- API key + rotation UI:
  [`editor_app/lib/modules/settings.dart`](../../frontend/editor_app/lib/modules/settings.dart)
  `_ApiKeySection`. Portal/planner ports tracked in
  [TODO.md](../TODO.md) "Login and account info".
- OAuth callbacks land at `/auth/google/callback` /
  `/auth/github/callback` (project-level URLs in
  [`urls.py`](../../backend/notechondria/urls.py)) and the SPA
  exchanges the code via the API endpoints above.
