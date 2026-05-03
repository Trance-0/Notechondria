# GitHub data-sync (experimental)

Per-user backup of all server-held text + metadata into a GitHub
repository the user owns. Goal: a user can survive a complete server
wipe by `git clone`-ing their own data back. Static assets we host
(avatars, attachments, cover images) are referenced by URL; their
bytes stay on our CDN and are not committed.

This feature is experimental and gated behind a frontend
"Experimental" card in editor settings. It is **not** wired into any
automatic schedule; the user pushes manually for now.

## Why a GitHub App, not a personal access token?

- Per-user install (`installation_id`) scoped to one repository.
- Tokens rotate ~hourly automatically.
- Revoked by the user from their GitHub settings, no server work
  needed on our side.
- Survives password rotation / 2FA changes on the user's side.

## Required env vars

Drop these into the backend `.env`:

```
GITHUB_DATA_SYNC_APP_NAME=notechondria-data-sync
GITHUB_DATA_SYNC_APP_CLIENT_ID=<from GitHub App settings>
GITHUB_DATA_SYNC_APP_CLIENT_SECRET=<from GitHub App settings>
GITHUB_DATA_SYNC_APP_PRIVATE_KEY=<PEM, single-line with \n escapes>
GITHUB_DATA_SYNC_APP_INSTALL_URL=https://github.com/apps/notechondria-data-sync/installations/new
```

The App must request the following permissions:

- Repository: **Contents** read+write (write is what `commit_and_push`
  uses). Single repo per install.
- Metadata: read (default).

## Repository layout

```
/
├── README.md              brief pointer + last-sync timestamp
├── manifest.json          schema version + per-section index
├── profile/
│   ├── creator.json       Creator row (no api_key_hash, no avatar bytes)
│   ├── settings.json      app_settings_json + updated_at
│   └── skill.md           mcp_skill_md verbatim
├── courses/
│   └── <slug>.json
├── notes/
│   ├── <uuid>.md          markdown body + YAML frontmatter
│   └── <uuid>.meta.json   sidecar: system metadata + custom_meta + sharing_id
├── planner/
│   ├── events.json
│   └── feeds.json
└── recycle_bin.json
```

`manifest.json` schema versions everything. `schema_version=1` is the
shape captured by `creators.services.github_sync.materialize`. Bump
when you add fields; do not silently break older clones.

## Restore (manual, future automated)

1. `git clone` the user's repo.
2. POST `/api/v1/auth/register/` (or sign in via OAuth) to recreate
   the Creator row.
3. PATCH `/api/v1/settings/` with `mcp_skill_md`, `theme_*`, and the
   `app_settings` blob from `profile/settings.json`.
4. Recreate every course via `POST /api/v1/courses/` using its slug.
5. Recreate every note via `POST /api/v1/notes/` reading the
   markdown body + the sidecar `*.meta.json` for `metadata_json` and
   `custom_meta`.
6. Recreate planner events + feeds from `planner/*.json`.

The end-to-end restore tooling is not yet shipped; `0.1.90` only
covers the export half. Tracked under "Release / CI" in
`docs/TODO.md`.

## Wire-up flow

1. User clicks "Connect to GitHub" in editor settings → frontend
   redirects to `GITHUB_DATA_SYNC_APP_INSTALL_URL`.
2. After install, GitHub redirects back to the editor with
   `?installation_id=...&setup_action=install`.
3. Frontend POSTs `/api/v1/integrations/github/callback/` with the
   install id + chosen `repo_full_name` and `repo_default_branch`.
4. Backend persists a `GithubIntegration` row keyed by Creator.
5. User clicks "Push now" → `POST /api/v1/integrations/github/push/`.
   Backend materializes the file tree and PUTs each file via the
   GitHub Contents API using an installation-scoped access token.

## Known gaps as of 0.1.93

The push pipeline is now end-to-end functional; the remaining work
is around static assets and concurrent edits.

- **Static-asset re-bundling.** Avatars, attachments, and cover
  images are referenced by URL in the export, not committed. If a
  user restores into a fresh server with no access to the original
  CDN, those URLs 404. The next iteration should add an opt-in
  `--include-assets` flag on the restore CLI that fetches each
  asset and re-uploads it before re-creating the parent record.
- **Conflict resolution.** The Contents API PUTs we use overwrite
  the remote blob. A user editing on two devices between syncs can
  lose changes. The next iteration should fetch the existing blob
  on each path, diff it against the materialized payload, and
  surface a "remote changed" warning before overwriting.

## Closed gaps (0.1.93)

- `_refresh_installation_token` is wired: `pyjwt + cryptography`
  ship in both `backend/requirements.txt` and
  `backend/requirements-render.txt`; the signer is covered by
  `creators.tests.GithubSyncTests` against a freshly generated
  test RSA keypair.
- The frontend repo picker shipped via the shared
  `GithubSyncExperimentalCard`. Editor / planner / portal each
  expose `githubSyncStatus / githubSyncRepos / githubSyncCallback /
  githubSyncPush / githubSyncDisconnect` on their
  `NotechondriaClient`; the card itself is callback-driven and
  works from any of the three apps.
- A scriptable restore lives at
  [`backend/scripts/github_sync_restore.py`](../../backend/scripts/github_sync_restore.py).
  Stdlib-only, supports `--dry-run` and `--verbose`, and uses
  `client_draft_id` to make reruns idempotent.
