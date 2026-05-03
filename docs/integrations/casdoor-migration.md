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

1. **Survey + design** (this round, version 0.1.95). Inventory the
   auth surface; ship `docs/integrations/casdoor-migration.md`.
2. **Casdoor SDK + JWT auth class.** Add `casdoor` Python SDK,
   wire JWKS-cached JWT verification as a new DRF authentication
   class. Run alongside `MultiSessionAuthentication` (shadow mode):
   the new class is added LAST in `DEFAULT_AUTHENTICATION_CLASSES`
   so it's a no-op until a JWT shows up.
3. **Frontend Casdoor SDK.** Add the Flutter Casdoor package to
   `notechondria_shared`; route the existing `_AuthDialog` and
   `launchOAuth` paths through Casdoor's `/login/oauth/authorize`
   instead of the per-provider Google/GitHub URLs. Backend
   endpoints stay backwards-compatible during this phase.
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

## Open questions

- **Username migration.** Casdoor users are keyed by an opaque
  `name` (Casdoor) plus an `id` (UUID). The mapping table from
  existing `auth_user.username` to Casdoor `name` must be
  pre-populated before cutover or first-login users will end up
  duplicated. Plan: a one-shot management command that imports
  the existing user table into Casdoor via its `add-user` API and
  records the mapping on `Creator.casdoor_sub`.
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
