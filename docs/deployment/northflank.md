# Northflank backend deployment

This document describes deploying the Notechondria Django backend to
[Northflank](https://northflank.com/) with Northflank's managed PostgreSQL
addon. Cloudflare R2 continues to handle static and media storage, since
Northflank service filesystems are ephemeral across redeploys.

## What this covers

- Django backend only (one Northflank `Combined Service`)
- Managed PostgreSQL via the Northflank `postgres` addon
- Gunicorn web service on the Dockerfile-declared port `8000`
- Static and media files on Cloudflare R2

The three Flutter frontends still deploy separately to GitHub Pages via
`.github/workflows/frontend-pages.yml`.

## Files in this repo

| Path | Purpose |
| --- | --- |
| `northflank.json` | Northflank `apiVersion: v1.2` template: `Project` step, nested `Workflow` with an `Addon` (PostgreSQL, `type: postgresql`) and a `CombinedService` built from the repo's `backend/Dockerfile`. Import via `northflank template create --file northflank.json` or the dashboard `Templates > Create` UI. |
| `sample.northflank.env` | Copyable env block for the backend service. Paste into `Service > Environment > Edit as text`. |
| `deployment/northflank/scripts/northflank_start.sh` | Optional start script. Use this as the Combined Service custom command if you prefer not to keep the boot logic inline. |
| `backend/Dockerfile` | Unchanged — build context is the repo root with `dockerFilePath: /backend/Dockerfile`. |

## Option A — Apply the template (recommended)

1. **Install the Northflank CLI** and authenticate:

   ```bash
   npm install -g @northflank/cli
   northflank login
   ```

2. **Edit the VCS URL** if you want to build from your fork. Open
   `northflank.json` and change `steps[1].spec.steps[1].spec.vcsData.projectUrl`
   to your repo URL, then apply the template:

   ```bash
   northflank template apply --file northflank.json
   ```

   This creates a project named `notechondria`, a `notechondria-postgres`
   addon (PostgreSQL, TLS on, 4 GB SSD), and a `notechondria-backend`
   Combined Service that builds from `backend/Dockerfile`. The template wires
   the PostgreSQL addon into the service's `runtimeEnvironment` via
   `${refs.database.*}` so `POSTGRE_HOST`, `POSTGRE_PORT`, `POSTGRE_DB`,
   `POSTGRE_USERNAME`, `POSTGRE_PASSWORD`, and `DATABASE_URL` are populated
   automatically at deploy time.

3. **Configure secrets** — the template seeds `DJANGO_SECRET_KEY` with
   `REPLACE_ME_FROM_SECRET_GROUP`. Create a Secret Group
   (`Project > Secrets > Create`), add the sensitive variables from
   `sample.northflank.env` (`DJANGO_SECRET_KEY`, `SMTP_PASSWORD`, OAuth
   secrets, R2 keys), and link it to the service under
   `Service > Environment > Link secret group`.

4. **Trigger the first build** from `Service > Builds > Start build`.

## Option B — Manual setup in the dashboard

1. **Create a project.** `Create project > notechondria`, pick a region close
   to your users.

2. **Provision PostgreSQL.** `Addons > Add addon > PostgreSQL` (addon type
   key is `postgresql`). Pick `latest`, 1 replica, at least 4 GB SSD storage.
   Name it `notechondria-postgres`. Enable TLS. Wait for `Running`.

3. **Create the backend service.** `Create new > Combined service`.
   - **Name:** `notechondria-backend`
   - **VCS:** select your fork of this repo, branch `main` (or `codex`).
   - **Build method:** Dockerfile
     - **Dockerfile path:** `/backend/Dockerfile`
     - **Build context / work dir:** `/` (repo root — required because the
       Dockerfile `COPY backend/` and `COPY sample/` commands run from there)
   - **Port:** `8000`, HTTP, public.
   - **Resources:** `nf-compute-20` is enough for a smoke deployment.

4. **Link the PostgreSQL addon** to inject `POSTGRE_*` and `DATABASE_URL`.

5. **Add the backend env variables** from `sample.northflank.env` (paste into
   `Environment > Edit as text`). Put every credential into a Secret Group and
   link it instead of pasting plaintext secrets.

6. **Build and deploy.** First build pulls Python 3.9, installs requirements,
   then the container starts. The Dockerfile's `ENTRYPOINT ["/entrypoint.sh"]`
   waits for Postgres, runs `migrate`, `bootstrap_platform`, and
   `collectstatic --clear`, then execs the container command. Northflank sets
   that command (via the template's `customCommand`) to launch gunicorn on
   `${PORT}`. If you configure the service manually, set Docker config to
   **Custom command only** and paste:

   ```text
   gunicorn notechondria.wsgi:application --chdir /home/notechondria --bind 0.0.0.0:${PORT} --workers ${WEB_CONCURRENCY} --timeout 120
   ```

## Required environment variables

Set these in the Northflank dashboard (or via the Secret Group):

### Django core

- `DJANGO_SECRET_KEY` — 50-char random string
- `DJANGO_ALLOWED_HOSTS` — e.g. `*` or `<service>--notechondria.<region>.code.run,notechondria.example.com`
- `DJANGO_CSRF_TRUSTED_ORIGINS` — e.g. `https://*.code.run,https://notechondria.example.com`
- `DJANGO_DEBUG=False`
- `BACKEND_CUSTOM_DOMAIN` *(optional)* — custom domain attached via
  `Project > Domains`

### Database

Provided by the addon link:

- `DATABASE_URL`
- `POSTGRE_HOST`, `POSTGRE_PORT`, `POSTGRE_DB`, `POSTGRE_USERNAME`, `POSTGRE_PASSWORD`

### Cloudflare R2 (required)

Same five variables as the Render deployment — the code paths are identical:

| Variable | Description |
| --- | --- |
| `CLOUDFLARE_R2_BUCKET_NAME` | R2 bucket name |
| `CLOUDFLARE_R2_ACCOUNT_ID` | Cloudflare account ID |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 API token access key |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 API token secret key |
| `CLOUDFLARE_R2_CUSTOM_DOMAIN` *(optional)* | Public R2 hostname |

When `CLOUDFLARE_R2_BUCKET_NAME` is set, Django auto-switches to R2 for both
static and media files. **If the bucket name is set but any of the three
required credentials are missing, the app will fail to start.**

### SMTP and OAuth

Optional but required if you use email verification or social sign-in — see
`sample.northflank.env` for the full list (`SMTP_*`, `GOOGLE_OAUTH_*`,
`GITHUB_APP_*`).

## Runtime behaviour

- Northflank injects `PORT`; the Dockerfile `EXPOSE 8000` must match the
  service port setting. The template uses `8000` for both.
- `entrypoint.sh` waits up to 300 s for `POSTGRE_HOST:POSTGRE_PORT` before
  running `migrate`. If the addon link is missing or the password is wrong, the
  container exits with a clear error.
- `collectstatic --noinput --clear` uploads built assets to
  `<bucket>/static/` on every deploy; user uploads live under `<bucket>/media/`.
- Health check: hit `/api/health/` (returns `200 OK`). Configure under
  `Service > Advanced > Health checks`.

## Custom domains

Northflank publishes services at
`https://<service>--<project>.<region>.code.run`. To use a custom domain:

1. `Project > Domains > Add domain`, enter the apex or subdomain.
2. Add the DNS records Northflank shows you.
3. Set `BACKEND_CUSTOM_DOMAIN` and update `DJANGO_ALLOWED_HOSTS` +
   `DJANGO_CSRF_TRUSTED_ORIGINS` to include it.
4. Update your GitHub Pages frontend config so the portal/editor/planner call
   the new hostname.

## Troubleshooting

- **Build fails on `COPY backend/`** — build context is the repo root. Confirm
  `buildSettings.dockerfile.dockerWorkDir` is `/`, not `/backend`.
- **`migrate` hangs on `Waiting for postgres...`** — the addon link is missing
  or the service can't reach it. Verify the `POSTGRE_HOST` env var resolves
  inside the container (`Service > Exec > nslookup`).
- **Static files 404** — `CLOUDFLARE_R2_CUSTOM_DOMAIN` probably isn't set;
  URLs fall back to the S3 endpoint which the browser won't load cross-origin.
  Either set the custom domain or enable the `r2.dev` public subdomain.
- **First login returns 403** — `DJANGO_CSRF_TRUSTED_ORIGINS` must include
  the exact origin (scheme + host) of the frontend making the POST.

## Notes

- This is backend-only. Frontends still deploy via GitHub Pages.
- The Dockerfile is shared across Jenkins, Render, and Northflank — no
  platform-specific build image.
- To tear everything down, delete the Combined Service first, then the
  addon, then the project. Addon data is not retained once deleted.
