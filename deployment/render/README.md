# Render backend deployment

Use Render for the Django backend and PostgreSQL, and GitHub Pages for the frontends.

## Backend
- Start script: `scripts/render_backend_start.sh`
- Root wrapper: `../../render-deploy.sh`
- Environment example: `.env.example`

## Build command
```bash
pip install -r backend/requirements.txt
```

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
- `ALLOWED_HOSTS`
- `CSRF_TRUSTED_ORIGINS`
- optional `OPENAI_API_KEY`, `GITHUB_APP_*`

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
ALLOWED_HOSTS=your-service.onrender.com,notenextra.trance-0.com
CSRF_TRUSTED_ORIGINS=https://your-service.onrender.com,https://notenextra.trance-0.com
WEB_CONCURRENCY=2
PYTHONUNBUFFERED=1
```

## Frontend
See `github-pages/README.md` for GitHub Pages setup.
