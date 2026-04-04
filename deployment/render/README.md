# Render backend deployment

Use Render for the Django backend and PostgreSQL, and GitHub Pages for the frontends.

## Backend
- Start script: `scripts/render_backend_start.sh`
- Root wrapper: `../../render-deploy.sh`
- Environment example: `.env.example`

## Build command

The Render root directory must be the repo root (leave Root Directory blank in dashboard).

```bash
pip install -r backend/requirements-render.txt
```

**Important**: `requirements-render.txt` excludes heavy ML packages (torch, etc.) that
exceed free-tier limits. Keep those only in `requirements.txt` for self-hosted builds.

The repo includes:
- `backend/requirements-render.txt` for Render/runtime installs
- Root-level `runtime.txt` and `.python-version` pinned to Python 3.11.4

## Start command
```bash
bash render-deploy.sh
```

## Environment options
You can configure Render in either of two ways:

### Option A: normal environment variables
Set values directly in the Render dashboard:
- `DATABASE_URL`
- `SECRET_KEY`
- `CUSTOM_DOMAIN` — custom domain pointing to backend (e.g. `notenextra.trance-0.com`)
- `FRONTEND_ORIGIN` — frontend origin for CORS (e.g. `https://trance-0.github.io`)
- `DJANGO_SUPERUSER_PASSWORD` — admin account password (required for bootstrap)
- optional `DJANGO_SUPERUSER_USERNAME`, `DJANGO_SUPERUSER_EMAIL`
- optional `ALLOWED_HOSTS`, `CSRF_TRUSTED_ORIGINS` (override auto-detection)
- optional `OPENAI_API_KEY`, `GITHUB_APP_*`

> **Note**: `RENDER_EXTERNAL_HOSTNAME` is set automatically by Render.
> `CUSTOM_DOMAIN` and `FRONTEND_ORIGIN` auto-populate `ALLOWED_HOSTS` and
> `CSRF_TRUSTED_ORIGINS` defaults, so you typically don't need to set those manually.

### Option B: Render secret file
Render can mount plaintext secret files under `/etc/secrets/<filename>`.

Supported by `render-deploy.sh`:
- explicit file path argument
- repo root `.env`
- `/etc/secrets/.env`
- first matching `/etc/secrets/*.env`

Example Render secret file content:
```env
DATABASE_URL=postgresql://...
SECRET_KEY=change-me
CUSTOM_DOMAIN=notenextra.trance-0.com
FRONTEND_ORIGIN=https://trance-0.github.io
DJANGO_SUPERUSER_PASSWORD=your-admin-password
WEB_CONCURRENCY=2
PYTHONUNBUFFERED=1
```

## Frontend
See `github-pages/README.md` for GitHub Pages setup.
