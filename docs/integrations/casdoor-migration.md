# Casdoor migration plan (next major)

The existing in-house auth stack (registration, email verification,
password reset, OAuth2 login + bind, multi-device session manager)
will be replaced by [Casdoor](https://casdoor.org) on the next major
version. App-level user state stays in `creators.Creator` — only
identity, credentials, and the social-provider plumbing move out.

This is a survey + plan; **no code changes ship in this round**. The
goal is to enumerate every auth surface so the cutover round can be
scoped accurately.

## What moves to Casdoor

The following endpoints / classes / templates become thin shims (or
deletions) that redirect to or proxy Casdoor:

### `backend/creators/api.py`

- `RegisterApiView` + `RegisterSerializer`
- `ValidateInvitationApiView` (Casdoor has invitation codes; reuse those)
- `VerifyEmailApiView` + `VerifyEmailSerializer`
- `ResendVerificationApiView` + `ResendVerificationSerializer`
- `LoginApiView` + `LoginSerializer` — replaced by Casdoor token exchange
- `PasswordResetRequestApiView` + serializer
- `PasswordResetConfirmApiView` + serializer
- `LogoutApiView` — Casdoor revokes sessions
- `ChangePasswordApiView` + `ChangePasswordSerializer`
- `ChangeEmailApiView` + Request/Confirm serializers
- `SendIdentityCodeApiView` + `_consume_identity_code` helper
  (Casdoor's `verify-code` API replaces the 6-digit confirm flow)
- `OAuthConfigApiView` — Casdoor's `/api/get-app-login` returns
  enabled providers + redirect URIs centrally
- `GoogleOAuthApiView`, `GitHubOAuthApiView` + their serializers
- `SocialAccountListApiView`, `SocialAccountUnlinkApiView`
- `_BindOAuthMixin`, `BindGoogleApiView`, `BindGithubApiView`
- `_pick_redirect_uri`, `_request_origin` per-app redirect logic —
  Casdoor handles allow-listing centrally
- `_get_or_create_oauth_user`
- `auth_payload()` — keep as a translator: input becomes a Casdoor
  JWT, output stays the same shape so frontends don't break

### `backend/creators/authentication.py`

- `MultiSessionAuthentication` → replaced by a JWT-validating DRF
  authentication class that calls Casdoor's JWKS to verify the
  token. Cached locally with a 5-minute TTL.
- `ApiKeyAuthentication` (the `Bearer ntc_<key>` MCP path) —
  **keep**. MCP API keys are app-internal credentials, not user
  auth, and Casdoor is not in the per-request hot path for MCP.

### `backend/creators/views.py` + `templates/`

- `login_request`, `register_request`, `edit_profile`, password
  reset views (server-rendered Bootstrap forms) — delete. The
  three Flutter apps are the only consumer of these URLs and they
  go through DRF endpoints, not the templates. Keep the templates
  directory only if `bootstrap_platform` still seeds welcome
  emails through it.

### `backend/creators/utils.py`

- `issue_registration_code`, `send_registration_email`,
  `send_password_reset_email`, `_send_code_email` — delete; Casdoor
  sends its own emails through its SMTP config.

### `backend/creators/models.py`

- `Session` — deprecate. Either drop the model (and migrate
  schema) or keep as a denormalized cache populated from Casdoor
  session events for the Settings → Active Sessions card.
- `SocialAccount` — keep, but re-key to Casdoor's `provider`/
  `providerName` shape. Mostly used for the Settings card; can be
  populated from Casdoor's `userinfo` claim.
- `VerificationCode` — delete; Casdoor owns email-code flows.
- `InvitationCode` — delete or migrate behind Casdoor's invite API.

## What stays on Creator (unchanged)

The full list of fields that remain app-level state:

```text
motto, social_link, image, editor_mode, theme_preset, theme_mode,
api_base_url, api_key_hash, api_key_prefix, mcp_skill_md,
app_settings_json, app_settings_updated_at, last_login,
date_joined, credit_remains, exp, reputation
```

Plus the related rows: `Note`, `NoteAttachment`, `Course`,
`CourseSubscription`, `PlannerEvent`, `CalendarFeed`,
`GithubIntegration`, `RotateApiKeyApiView`, `SettingsApiView`,
`GithubSync*ApiView`. None of these touch auth directly; they all
key off `Creator.user_id` which becomes a soft pointer to a Casdoor
user identifier (likely a UUID-typed `casdoor_sub` field replacing
the Django `User` FK).

## Phased migration

The cutover is too big for one round. Suggested phases (each its
own version log):

1. **Survey + design** (0.1.95 — DONE). Inventory the auth surface;
   ship `docs/integrations/casdoor-migration.md`.
2. **Casdoor SDK + JWT auth class** (0.1.96 — DONE). Adds the
   `casdoor>=1.41` Python SDK, the `CasdoorJWTAuthentication` DRF
   class (registered LAST in `DEFAULT_AUTHENTICATION_CLASSES` so
   it's a no-op until a Bearer JWT shows up that isn't an MCP key),
   `Creator.casdoor_sub`, and the public
   `/api/v1/auth/casdoor/{config,exchange}/` endpoints. Returns
   503 / `{configured: false}` when env vars aren't populated, so
   existing `MultiSessionAuthentication` + `LoginApiView` paths
   keep working unchanged.
3. **Frontend Casdoor SDK.** Add the Flutter Casdoor package to
   `notechondria_shared`; route the existing `_AuthDialog` and
   `launchOAuth` paths through Casdoor's `/login/oauth/authorize`
   instead of the per-provider Google/GitHub URLs. The frontend
   client gains a `casdoorExchange(code)` method that hits the new
   `POST /api/v1/auth/casdoor/exchange/` and reuses the existing
   `applyAuthPayload` machinery. Backend endpoints stay
   backwards-compatible during this phase.
4. **Cutover.** Disable the legacy `LoginApiView` /
   `RegisterApiView` etc. endpoints; the JWT path is now the only
   way in. Remove `MultiSessionAuthentication` + `Session` writes;
   the `Session` model becomes read-only (populated from Casdoor
   session-events webhook).
5. **Cleanup.** Delete every endpoint / serializer / template /
   helper listed above. Remove `VerificationCode` /
   `InvitationCode` models with a final migration.

Each phase is independently shippable. Steps 2 and 3 can land in
either order; both should land before step 4.

## Phase 2 wire shape (shipped 0.1.96)

### Backend authentication

- `creators.casdoor_auth.CasdoorJWTAuthentication` validates
  `Authorization: Bearer <jwt>` against
  `settings.CASDOOR_CERTIFICATE` (RS256). Audience must equal
  `CASDOOR_CLIENT_ID`. Bearer headers starting with `ntc_` are
  ignored so MCP API keys keep flowing to
  `ApiKeyAuthentication`.
- The class is no-op when any of `CASDOOR_ENDPOINT`,
  `CASDOOR_CLIENT_ID`, `CASDOOR_ORG_NAME`, `CASDOOR_APP_NAME` is
  empty. Returns `None` (not `AuthenticationFailed`) so other
  classes in the chain can still handle the same header.
- On first valid JWT, user resolution order is:
  1. `Creator.casdoor_sub == claims['id' | 'sub']` (fast path
     after the link is persisted).
  2. `User.email iexact claims['email']` — links an existing
     legacy account; `Creator.casdoor_sub` is backfilled.
  3. Auto-provision a new `User` + `Creator`, stamp the sub.
- Stamps `User.last_login` so the existing "recently signed in"
  surfaces stay accurate.

### Public endpoints

`GET /api/v1/auth/casdoor/config/` (anon):

```json
{"configured": true,
 "endpoint": "https://auth.example",
 "client_id": "...",
 "organization": "...",
 "application": "...",
 "signin_url": "https://auth.example/login/oauth/authorize"}
```

When unconfigured: `{"configured": false}` with no other fields,
so the SPA can keep showing the legacy auth surface.

`POST /api/v1/auth/casdoor/exchange/` (anon):

Request: `{"code": "<casdoor-authz-code>", "state": "..."}`.
Response (200): the standard `auth_payload` shape used by
`LoginApiView` — `token` + `session` + `user` + `app_settings`.
Response (503): `{detail: "...shadow mode..."}` when the SDK
isn't configured.

### Migration

- `creators/0030_creator_casdoor_sub.py` adds
  `Creator.casdoor_sub` (CharField, indexed, blank default).
- No data migration. Legacy users continue without a sub until
  their first Casdoor sign-in, at which point either the email
  link or the auto-provision branch records it.

## Phase-3-and-a-half — bind / unlink (shipped 0.1.98)

The phase-2 exchange endpoint resolves identity automatically via
`Creator.casdoor_sub` → email-iexact → auto-provision. The
bind/unlink path covers two cases the auto-resolve can't:

1. The Casdoor email differs from the Notechondria email, so the
   email-iexact branch can't find the legacy account.
2. The user wants to deliberately disconnect a previously linked
   Casdoor identity without losing access (the legacy session
   keeps working).

### Endpoints

`POST /api/v1/auth/casdoor/bind/` (auth required):

Request: `{"code": "<casdoor-authz-code>"}`. Backend exchanges via
`get_oauth_token`, verifies the JWT, takes the `sub`, and:

- Returns 409 if the same `sub` is already on a different Creator
  (the user must unlink that side first).
- Otherwise persists `Creator.casdoor_sub` for the current user
  and returns the standard `auth_payload`.

`DELETE /api/v1/auth/casdoor/unlink/` (auth required):

Idempotent. Clears `Creator.casdoor_sub`. Returns
`{"casdoor_linked": false, "was_linked": <bool>}`. Does NOT log
the user out — the existing legacy `Session` keeps working.

### Settings surface

`Settings` GET response now includes `casdoor_linked: bool` so the
Connected Accounts UI can render the right state without an extra
round-trip.

### Frontend

- `AuthClient` gains `casdoorBind(token, code)` +
  `casdoorUnlink(token)`. Each app's client implements them.
- `AppShellOAuthMixin.handleOAuthCallback` dispatches the
  `state=casdoor` branch on `intent`: `'login'` → exchange,
  `'bind'` → bind. The bind branch refuses to fall through to the
  legacy provider login when the session token is missing.
- All three apps' `_ConnectedAccountsSection` widgets gain a
  Casdoor SSO row with Link / Unlink controls; `onBindCasdoor`
  and `onUnlinkCasdoor` are constructed in each app shell when
  `_casdoorConfigured && _token != null`.

## Open questions

- **Username migration.** Casdoor users are keyed by an opaque
  `name` (Casdoor) plus an `id` (UUID). The mapping table from
  existing `auth_user.username` to Casdoor `name` must be
  pre-populated before cutover or first-login users will end up
  duplicated. **Resolved (cutover round):** the management command
  `python manage.py migrate_users_to_casdoor` walks
  `auth_user.is_active=True`, calls `CasdoorSDK.get_user_by_email`
  to deduplicate, then `add_user` / `update_user` for each row, and
  finally stamps `Creator.casdoor_sub` so the next JWT login takes
  the fast path. Idempotent; supports `--dry-run`,
  `--retry-existing`, `--strict`, and `--limit N` for staged rollout.
  Linked `SocialAccount` rows are pushed into Casdoor's per-provider
  fields (`user.google`, `user.github`) so prior OAuth identities
  resolve to the same Casdoor row.
- **MCP API keys.** The `ntc_<32-hex>` Bearer scheme stays
  app-internal; Casdoor is not used for the MCP per-request hot
  path. The `/api/v1/auth/rotate-api-key/` endpoint stays.
- **OAuth redirect-allow-list.** Casdoor handles per-app
  redirect_uri allow-lists centrally. The
  `GOOGLE_AUTHORIZED_REDIRECT_URIS` /
  `GITHUB_AUTHORIZED_REDIRECT_URIS` env vars added in 0.1.90
  become unused once cutover lands.
- **Email verification copy.** Casdoor's templated email is
  generic; if we want the Notechondria-branded email body, we
  need to ship a Casdoor email template via its admin API as part
  of the migration.

## Required env vars (target state)

```text
CASDOOR_ENDPOINT=https://login.notechondria.example
CASDOOR_CLIENT_ID=...
CASDOOR_CLIENT_SECRET=...
CASDOOR_ORG_NAME=notechondria
CASDOOR_APP_NAME=notechondria
CASDOOR_CERTIFICATE=<single-line PEM with \n escapes>
```

The five existing OAuth env vars
(`GOOGLE_OAUTH_CLIENT_ID`, etc.) become optional after cutover —
Casdoor stores them centrally instead.
