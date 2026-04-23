# Deployment overview

Notechondria splits cleanly into two deployable surfaces:

| Surface | Code path | Deploy targets |
| --- | --- | --- |
| Backend (Django + DRF + Postgres) | [`backend/`](../../backend/) | Docker-compose [full stack], Render free-tier, Northflank free-tier, Railway *(untested)* |
| Frontend (3 Flutter apps) | [`frontend/editor_app/`](../../frontend/editor_app/), [`planner_app/`](../../frontend/planner_app/), [`portal_app/`](../../frontend/portal_app/) | GitHub Pages |
| Static + media storage | n/a | Cloudflare R2 (S3-compatible) |

The three Flutter apps and the backend are independently deployable.
Cross-component contracts:

- All frontends call the same backend over `/api/v1/...`. Per-app
  defaults baked at build time via `--dart-define=DEFAULT_API_URL=...`
  with a fallback constant in each app's
  `lib/core/helpers.dart` (`_kDefaultApiUrl`).
- Frontends call `/api/v1/handshake/` before committing a
  user-changed API base URL — see
  [server/backend.md#handshake](../server/backend.md#handshake).
- Backend serves static + uploaded media through Cloudflare R2 when
  `CLOUDFLARE_R2_BUCKET_NAME` is set; otherwise falls back to
  WhiteNoise (Render) or local volumes (Docker).

Pick the deploy path you need:

## 1. Docker-compose [full stack]

End-to-end self-hosted deployment. Backend + Postgres + nginx
gateway + all three frontend apps in one compose stack. Same shape
as Jenkins runs in CI.

- **Compose file:** root [`docker-compose.yml`](../../docker-compose.yml).
- **Per-component composes:** [`backend/docker-compose.yml`](../../backend/docker-compose.yml),
  per-app composes under `frontend/<app>/docker-compose.yml`,
  gateway under [`deployment/docker/gateway/`](../../deployment/docker/).
- **Pipeline:** [`Jenkinsfile`](../../Jenkinsfile) +
  [`deployment/jenkins/scripts/`](../../deployment/jenkins/scripts/)
  (env prep, postgres backup, ensure-db-ready, test/deploy backend,
  test/deploy frontends, deploy gateway).
- **Detailed runbook:** [deploy.md](deploy.md).

Run locally:

```bash
cp sample.env .env       # then fill in DB password and SECRET_KEY
docker compose up --build
```

Image tags follow `v<VERSION>.<BUILD_NUMBER>` from
[`./VERSION`](../../VERSION) (read by
`deployment/jenkins/scripts/prepare_env.sh`).

## 2. GitHub Release [Desktop + mobile archives]

Tag-triggered workflow that publishes `portal_app` builds (Linux
x64/arm64, Windows x64, macOS, Android APK, iOS unsigned) to a
GitHub Release. Trigger: push a `v*` tag.

- **Workflow:** [`.github/workflows/portal-release.yml`](../../.github/workflows/portal-release.yml).
- **Detailed runbook:** [release.md](release.md).
- **Editor + planner:** not yet wired; tracked in
  [`docs/TODO.md`](../TODO.md).

## 3. GitHub Pages [Frontend]

Builds and publishes all three Flutter web apps to `gh-pages` under
`/Notechondria/<editor|planner|portal>/`. Root `/Notechondria/`
meta-refreshes to `/Notechondria/portal/`.

- **Workflow:** [`.github/workflows/frontend-pages.yml`](../../.github/workflows/frontend-pages.yml).
- **Build flags per app** (added 0.1.19):
  - `--base-href /Notechondria/<app>/` — required for project sites.
  - `--no-web-resources-cdn` — bundle Flutter runtime locally.
  - `--dart-define=APP_VERSION=$(cat VERSION)` — propagate version
    to splash screen + debug surface.
- **Test gate:** each app's `test/smoke_test.dart` must pass before
  build.
- **Trigger:** push to `codex` (or whichever branch the workflow
  is configured for) + manual `workflow_dispatch`.

To override the backend a frontend points at (for staging or a fork
deployment), pass an extra `--dart-define=DEFAULT_API_URL=https://your-backend/api/v1`
in each `flutter build web` step.

## 4. Cloudflare R2 [CDN]

S3-compatible bucket holding static assets and user-uploaded media.
Required for Render and Northflank because both have ephemeral
container filesystems.

- **Setup:** [`https://developers.cloudflare.com/r2/`](https://developers.cloudflare.com/r2/).
  Create a bucket, mint an R2 API token with read/write, optionally
  attach a custom domain.
- **Backend env vars** (all five required if `CLOUDFLARE_R2_BUCKET_NAME`
  is set; otherwise none of them are):

  | Variable | Purpose |
  | --- | --- |
  | `CLOUDFLARE_R2_BUCKET_NAME` | Bucket name |
  | `CLOUDFLARE_R2_ACCOUNT_ID` | Cloudflare account ID |
  | `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 API token access key |
  | `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 API token secret key |
  | `CLOUDFLARE_R2_CUSTOM_DOMAIN` | *(optional)* public hostname |

- **What lives there:** `<bucket>/static/` (overwritten on every
  `collectstatic --noinput --clear`) and `<bucket>/media/` (user
  uploads, course covers, attachments).
- **Local Docker:** **do not** set `CLOUDFLARE_R2_BUCKET_NAME` —
  the backend serves static via WhiteNoise/nginx and stores media
  on a local volume.

## 5. Render free-tier [Backend]

Backend-only PaaS deploy. Render provides PostgreSQL via
`DATABASE_URL`, no persistent disk for media → R2 is required.

- **Detailed runbook:** [render_free_tier.md](render_free_tier.md).
- **Start script:** [`render-deploy.sh`](../../render-deploy.sh)
  → [`deployment/render/scripts/render_backend_start.sh`](../../deployment/render/scripts/render_backend_start.sh).
- **Required env:** `DJANGO_SECRET_KEY`, `DATABASE_URL`,
  `DJANGO_ALLOWED_HOSTS`, `DJANGO_CSRF_TRUSTED_ORIGINS`, the five
  Cloudflare R2 vars. SMTP + OAuth as needed.
- **Build command:** `pip install -r backend/requirements.txt`
  (the older `requirements-render.txt` is kept around but
  `requirements.txt` itself is now also pruned of the torch/whisper
  stack — see [`docs/development/ai_integration.md`](../development/ai_integration.md)).
- **Cold start gotcha:** free instances cold-start slowly; first
  request after idle can take ~30 s.

## 6. Northflank free-tier [Backend]

Backend-only deploy with a managed Postgres addon. Northflank
service filesystems are ephemeral across redeploys → R2 is required.

- **Detailed runbook:** [northflank.md](northflank.md).
- **Template:** [`northflank.json`](../../northflank.json) (apiVersion
  `v1.2`) provisions a Project + a `notechondria-postgres` PostgreSQL
  addon + a `notechondria-backend` Combined Service that builds
  from [`backend/Dockerfile`](../../backend/Dockerfile).
- **Apply:** `northflank template apply --file northflank.json`
  (or import via the dashboard `Templates > Create`).
- **Sample env:** [`sample.northflank.env`](../../sample.northflank.env)
  enumerates every variable the service needs (mirrors the
  `sample.test.env` shape minus the Docker-compose-only knobs).
- **Docker config gotcha:** `customCommand` overrides do not reach
  the Dockerfile ENTRYPOINT's `exec "$@"`, so the template uses
  `configType: "default"` and relies on
  [`backend/entrypoint.sh`](../../backend/entrypoint.sh)'s built-in
  gunicorn fallback (added 0.1.18).

## 7. Railway [Backend] — untested

Railway is a credit-based PaaS similar to Render and Northflank.
The maintainer is out of free-tier credits and has not validated
the recipe; treat the steps below as a starting point.

- **Backend Dockerfile** is the same as Render/Northflank — point
  Railway at `backend/Dockerfile` with the build context at the
  repo root (`Dockerfile path: backend/Dockerfile`,
  `Dockerfile context: .`).
- **Add a Postgres plugin** in the project; Railway exposes
  `DATABASE_URL` automatically. Link it to the backend service.
- **Required env vars:** same list as
  [`sample.northflank.env`](../../sample.northflank.env), minus the
  Docker-compose-only knobs and minus the addon-supplied
  `POSTGRE_*`. Add the five Cloudflare R2 keys.
- **Health check:** `GET /` (returns 200 from `health_check`).
- **Custom domain:** Railway ships HTTPS by default; map your
  domain in the service's "Settings > Networking", then add it to
  `DJANGO_ALLOWED_HOSTS` and `DJANGO_CSRF_TRUSTED_ORIGINS`.
- **CMD override:** Railway honors the Dockerfile ENTRYPOINT, so
  no override needed — the entrypoint's gunicorn fallback runs.
- **Untested:** all of the above is paper-only. If you wire it up,
  please file a PR with notes.

## See also

- [`server/backend.md`](../server/backend.md) — backend architecture
  with cross-references.
- [`client/`](../client/) — per-app frontend docs.
- [`development/ai_integration.md`](../development/ai_integration.md)
  — AI stub state and the planned external HTTP microservice.
- [`operations/postgres_migration.md`](../operations/postgres_migration.md)
  — backup/restore runbook.
