# Casdoor login setup (auth.trance-0.com)

Step-by-step runbook for wiring the Notechondria backend to a
Casdoor instance — covers the admin-UI walkthrough, the env-var
contract on the Notechondria side, and the per-app redirect URIs.
Pairs with [`casdoor-migration.md`](casdoor-migration.md), which
covers the *why* + the phased migration plan.

This document assumes:

- The Casdoor instance is deployed at
  [`https://auth.trance-0.com`](https://auth.trance-0.com).
  (Self-hosted via `docker-compose` from a separate Gitea repo;
  see `auth.trance-0.com.conf` + `docker-compose.yml` next to
  `init_data.json` for the reverse-proxy + container topology.)
- The backend is on 0.1.96 or later
  ([`docs/versions/0.1.96.md`](../versions/0.1.96.md)) — that's
  the round that landed `CasdoorJWTAuthentication` and the
  `/api/v1/auth/casdoor/{config,exchange}/` endpoints.
- The frontend is on 0.1.97 or later
  ([`docs/versions/0.1.97.md`](../versions/0.1.97.md)) for the
  shared `launchOAuth('casdoor', ...)` plumbing, and ideally
  0.1.99+
  ([`docs/versions/0.1.99.md`](../versions/0.1.99.md)) for the
  Casdoor-primary login surface.

## 1. Casdoor admin-UI walkthrough

Sign in to `https://auth.trance-0.com` with the bootstrap admin
user (set at first boot via `init_data.json` or the seeded
`built-in/admin` account).

### 1a. Create the organization

Top nav → **Organizations** → **Add**.

| Field | Value |
| --- | --- |
| Name | `notechondria` |
| Display name | `Notechondria` |
| Tags | (optional, e.g. `notes`, `productivity`) |

Save. The organization name is the value of `CASDOOR_ORG_NAME` on
the backend.

### 1b. Create the application

Top nav → **Applications** → **Add**.

| Field | Value |
| --- | --- |
| Organization | `notechondria` (the one you just created) |
| Name | `notechondria` |
| Display name | `Notechondria` |
| Logo URL | (optional) |
| Login URL | `https://auth.trance-0.com/login/oauth/authorize` (Casdoor sets this automatically) |
| **Redirect URIs** | one entry per Flutter app — see §1d |
| Token format | `JWT` |
| Token signing algorithm | `RS256` |
| Token expire | `2 hours` (the Notechondria SDK only needs ~9 minutes; longer is fine) |
| Refresh token expire | `7 days` (or per your security policy) |
| **Providers** | (optional) attach Google / GitHub / etc. so Casdoor itself can act as the OAuth proxy; otherwise it will accept username/password against the Casdoor user table only |

Save. Casdoor reveals a `Client ID` and `Client secret` for this
application — those are the next two env vars you'll need.

### 1c. Generate (or pick) the signing certificate

If the application doesn't already show a certificate under the
**Cert** field, create one: top nav → **Certs** → **Add**.

| Field | Value |
| --- | --- |
| Name | `notechondria-cert` |
| Display name | `Notechondria signing cert` |
| Type | `x509` |
| Crypto algorithm | `RS256` |
| Bit size | `4096` |
| Expire in years | `5` (or longer; Casdoor lets you rotate) |

Save, then **download** the public key half. The Notechondria
backend verifies inbound JWTs against this PEM.

Back on the **Applications → notechondria** screen, set the
**Cert** field to `notechondria-cert`.

### 1d. Per-app redirect URIs

Casdoor's redirect-URI allow-list is centralised on the
application. Each Flutter frontend lives at a different origin,
so add **one entry per app**:

| App | Redirect URI |
| --- | --- |
| Editor | `https://trance-0.github.io/Notechondria/editor/` |
| Planner | `https://trance-0.github.io/Notechondria/planner/` |
| Portal | `https://trance-0.github.io/Notechondria/portal/` |

For local dev add the `localhost` equivalents too:

| App | Redirect URI |
| --- | --- |
| Editor | `http://localhost:8001/` |
| Planner | `http://localhost:8002/` |
| Portal | `http://localhost:8003/` |

(The exact ports depend on what `flutter run -d chrome` picks for
each app — pin them via `--web-port` if you want stable values.)

The Notechondria backend computes the `redirect_uri` from the
caller's `Origin` header per the
`launchOAuth('casdoor', ...)` flow, so each app's outbound
authorization URL ends with the matching origin. Any URI **not**
on Casdoor's allow-list above will be rejected with a
`redirect_uri mismatch` error.

### 1e. (Optional) configure email + invitation gates

If you want Casdoor to send the verification / password-reset
emails (Notechondria's own SMTP path stops being used after the
phase-4 cutover):

- Top nav → **Providers** → **Add** → category `Email`,
  type `SMTP`. The instance ships with a sample
  `provider_email_smtp` row preloaded by `init_data.json`; reuse
  or replace.
- Application → **notechondria** → **Email provider** = the SMTP
  provider above.

If you want sign-up gated by an invitation code (matches the
existing `InvitationCode` table on Notechondria):

- Application → **notechondria** → **Enable signup** = off.
- Top nav → **Invitations** → **Add** → assign to the
  `notechondria` org.

Until phase 4 ships, the legacy invitation flow on Notechondria
keeps working in parallel — Casdoor doesn't need to take this
over yet.

## 2. Notechondria backend env vars

Drop these into the backend `.env` (or the deployment-method
equivalent — see [`deploy.md`](../deployment/deploy.md),
[`render_free_tier.md`](../deployment/render_free_tier.md),
[`northflank.md`](../deployment/northflank.md)):

```text
CASDOOR_ENDPOINT=https://auth.trance-0.com
CASDOOR_CLIENT_ID=<from the application "Client ID" field>
CASDOOR_CLIENT_SECRET=<from the application "Client secret" field>
CASDOOR_ORG_NAME=notechondria
CASDOOR_APP_NAME=notechondria
CASDOOR_CERTIFICATE=<single-line PEM with literal \n escapes>
# Optional: how long to cache JWT-verification results in seconds
# (default 300). The verifier itself is stateless; this just
# amortises the cert-parsing cost when the same token shows up
# again within the window.
CASDOOR_TOKEN_CACHE_TTL=300
```

`CASDOOR_CERTIFICATE` is the public-key PEM you downloaded in
§1c. The newline-to-`\n` escape is so the PEM survives a
single-line shell `.env`. `_normalize_pem` in
`backend/creators/casdoor_auth.py` converts the escaped form back
to multi-line at signing time. Same trick used by the GitHub
data-sync app's private key.

When any of the first four are empty, every Casdoor surface on
the backend is a no-op (auth class returns `None`, exchange
endpoint returns 503, config endpoint returns
`{configured: false}`). That's the **shadow mode** the migration
plan calls out — safe default until you're ready to flip the
switch.

## 3. Verify

After `pip install -r backend/requirements.txt && python
manage.py migrate creators` (the
`0030_creator_casdoor_sub.py` migration must have run):

```bash
# Backend reports configured:
curl -s http://localhost:8000/api/v1/auth/casdoor/config/
# -> {"configured": true,
#     "endpoint": "https://auth.trance-0.com",
#     "client_id": "...",
#     "organization": "notechondria",
#     "application": "notechondria",
#     "signin_url": "https://auth.trance-0.com/login/oauth/authorize"}
```

Hit `/api/v1/handshake/` and confirm `version` matches the
deployed `VERSION` file (this surface was fixed in
[`0.1.95`](../versions/0.1.95.md) — if it returns `"0.0.0"` your
container didn't ship `VERSION` to `/home/VERSION`).

On the frontend:

1. Open any of the three apps. Sign-out.
2. The Account card should now lead with a full-width "Continue
   with Casdoor SSO" button (since 0.1.99). Legacy
   email / password sits behind the
   "Use email / password instead" expander.
3. Click the SSO button → redirects to
   `https://auth.trance-0.com/login/oauth/authorize?client_id=…&state=casdoor&...`.
4. Casdoor authenticates → redirects back with `?code=...`.
5. Frontend calls
   `POST /api/v1/auth/casdoor/exchange/` automatically; the SPA
   ends up signed in the same way as the legacy login flow.
6. Inspect `Settings → Connected accounts` — the Casdoor row
   shows "Linked".

For the bind path (link Casdoor to an *existing* legacy account
when the emails differ): sign in legacy first, then in Settings
→ Connected accounts click **Link Casdoor** on the Casdoor row.
Casdoor is opened with `state=casdoor` + `intent=bind`; the
callback hits `POST /api/v1/auth/casdoor/bind/` with the
existing session token, and the link is recorded on
`Creator.casdoor_sub`. The legacy session keeps working.

## 4. Failure modes

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Frontend SSO button missing | `/auth/casdoor/config/` returned `{configured: false}` | Backend env vars not populated, or container hasn't been rebuilt since they were added |
| `redirect_uri mismatch` on the Casdoor login page | URI not in §1d allow-list | Add the exact origin (scheme + host + port + trailing slash) under Application → Redirect URIs |
| `Cannot sign in: ...JWT verification failed` | `CASDOOR_CERTIFICATE` doesn't match the application's signing cert | Re-download the PEM in §1c, re-escape newlines, redeploy |
| `409 Conflict` on bind | The Casdoor `sub` is already linked to a different Notechondria account | Unlink that side first; or sign in with that account directly via SSO |
| `503 Service Unavailable` from `/auth/casdoor/exchange/` | One of the four required env vars is still empty | Re-check `CASDOOR_ENDPOINT`, `CASDOOR_CLIENT_ID`, `CASDOOR_ORG_NAME`, `CASDOOR_APP_NAME` |
| Backend `version` returns `"0.0.0"` | `VERSION` file isn't shipped to the container | The Dockerfile copies it to `/home/VERSION` since 0.1.95; for non-Docker deploys set the `BACKEND_VERSION` env var |

## 5. What gets stored where

After a successful Casdoor sign-in:

- `Creator.casdoor_sub` (TextField on
  `backend/creators/models.py`) holds the Casdoor user id /
  `sub` claim. Used as the fast-path key on subsequent JWT
  verifies.
- `creators.Session` row is still minted by
  `auth_payload(user, request)` so the existing
  `MultiSessionAuthentication` keeps working — the SPA uses the
  same `Authorization: Token <session-key>` header it always
  did. Casdoor JWTs are only used at sign-in time; the per-
  request hot path stays on the legacy session token until the
  phase-4 cutover.

Once cutover lands, `Session` becomes a read-only audit table
populated from Casdoor session-events webhooks; the per-request
hot path moves entirely onto JWT verification by
`CasdoorJWTAuthentication`. That's the next major version.
