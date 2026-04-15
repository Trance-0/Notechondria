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
| `Creator` | `user` (FK to `auth.User`), `display_name`, `avatar`, `motto`, `social_link`, `api_key_hash`, `identity_code`, `email_verified_at`, `is_default` | Profile + API key binding. One row per `auth.User`. Use `ensure_creator(user)` from [`backend/notechondria/utils.py`](../../backend/notechondria/utils.py) anywhere a view needs the creator context. |
| `CreatorApiKey` | `creator` (FK), `key_hash`, `created_at`, `revoked_at` | Tracks issued API keys. The plaintext key is shown to the user only once at creation/rotation; only the hash is stored. |
| `CreatorInvitation` | `creator` (FK), `code`, `expires_at`, `consumed_at` | Invitation codes for closed-beta signup. |
| `CreatorOauthIdentity` | `creator` (FK), `provider` (`google` / `github`), `provider_user_id`, `email`, `display_name`, `avatar_url`, `raw_payload` | Per-provider identity binding. Lookup key is `(provider, provider_user_id)`. |

## Authentication

DRF `DEFAULT_AUTHENTICATION_CLASSES` (in
[`settings.py`](../../backend/notechondria/settings.py)) registers
two:

1. `rest_framework.authentication.TokenAuthentication` — DRF tokens
   minted by `LoginApiView` and friends. Header:
   `Authorization: Token <hex>`.
2. `creators.authentication.ApiKeyAuthentication` — long-lived
   per-creator API keys. Header: `Authorization: ApiKey <plaintext>`
   (matched against `CreatorApiKey.key_hash`). Used by the MCP
   server for tool calls.

`DEFAULT_PERMISSION_CLASSES = [AllowAny]`, so each view sets its
own `permission_classes` explicitly.

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
| POST | `/api/v1/auth/login/` | `LoginApiView` | AllowAny | Body: `{username_or_email, password}`. Returns `{token, user}`. |
| GET  | `/api/v1/auth/session/` | `SessionApiView` | TokenAuth | Returns the current session's user payload. The frontend checks this on boot to decide between online vs offline mode. |
| POST | `/api/v1/auth/logout/` | `LogoutApiView` | TokenAuth | Revokes the current DRF token. |

Example login response:

```json
{
  "token": "9bd0a4...3f12",
  "user": {
    "id": 17,
    "username": "alice",
    "email": "alice@example.com",
    "creator_id": 17,
    "display_name": "Alice",
    "avatar": "/media/avatars/alice.png",
    "is_default": false,
    "email_verified_at": "2026-04-12T17:21:09Z"
  }
}
```

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
