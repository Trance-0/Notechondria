# Render free-tier backend deployment

This document describes the minimal backend-only deployment path for Render free-tier.

## What this covers

- Django backend only
- PostgreSQL provided by Render or an external managed database
- Gunicorn web service
- Static files collected at boot

## Required environment variables

Set these in the Render dashboard:

- `SECRET_KEY`
- `DATABASE_URL`
- `ALLOWED_HOSTS`
- `CSRF_TRUSTED_ORIGINS`
- `OPENAI_API_KEY` (if needed)
- any `GITHUB_APP_*` values if that integration is enabled

Render also provides:
- `PORT`

Recommended extras:
- `PYTHONUNBUFFERED=1`
- `WEB_CONCURRENCY=2`

## Build command

Use one of these:

```bash
pip install -r backend/requirements.txt
```

or if the service root is `backend/`:

```bash
pip install -r requirements.txt
```

## Start command

Preferred:

```bash
bash deployment/render/scripts/render_backend_start.sh
```

If the service root is `backend/`, use:

```bash
bash ../deployment/render/scripts/render_backend_start.sh
```

## What the start script does

`deployment/render/scripts/render_backend_start.sh` runs:

1. `python manage.py migrate --noinput`
2. `python manage.py bootstrap_platform || true`
3. `python manage.py collectstatic --noinput --clear`
4. `gunicorn notechondria.wsgi:application --bind 0.0.0.0:$PORT`

## Cloudflare R2 storage (required)

Render free-tier has an ephemeral filesystem — user-uploaded media files are
lost on every restart. Cloudflare R2 provides S3-compatible persistent storage.

### Setup

1. **Create an R2 bucket** in the Cloudflare dashboard.
2. **Create an API token** under R2 > Manage R2 API Tokens with read/write
   access to the bucket.
3. **(Optional)** Connect a custom domain or enable the `r2.dev` subdomain for
   public access to the bucket.
4. **Set these environment variables** in the Render dashboard:

| Variable | Description |
| --- | --- |
| `CLOUDFLARE_R2_BUCKET_NAME` | R2 bucket name |
| `CLOUDFLARE_R2_ACCOUNT_ID` | Cloudflare account ID (found in the dashboard URL or API section) |
| `CLOUDFLARE_R2_ACCESS_KEY_ID` | R2 API token access key |
| `CLOUDFLARE_R2_SECRET_ACCESS_KEY` | R2 API token secret key |
| `CLOUDFLARE_R2_CUSTOM_DOMAIN` | *(optional)* Public hostname for the bucket (e.g. `cdn.example.com`) |

When `CLOUDFLARE_R2_BUCKET_NAME` is set, Django automatically uses R2 for both
static files (`collectstatic`) and media files (user uploads, avatars, course
images). If the bucket name is set but any of the three required credentials
are missing, the app will fail to start with a clear error message.

### How it works

- `collectstatic --noinput --clear` uploads built static assets to
  `<bucket>/static/` on every deploy.
- User-uploaded media is stored under `<bucket>/media/`.
- URLs are generated pointing to the custom domain (if set) or the R2 S3
  endpoint.

### Docker Compose (local)

When deploying with Docker Compose, **do not** set `CLOUDFLARE_R2_BUCKET_NAME`.
The backend will use the local filesystem with persistent Docker volumes, and
nginx will serve static and media files directly.

## Notes

- This is backend-only. The three frontend apps deploy separately to GitHub Pages.
- Free-tier instances may cold-start slowly.
- If migrations are slow, startup time may increase.
- If `bootstrap_platform` is not needed for a given environment, it safely tolerates failure in the script.
