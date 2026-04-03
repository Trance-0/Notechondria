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
bash deployment/scripts/render_backend_start.sh
```

If the service root is `backend/`, use:

```bash
bash ../deployment/scripts/render_backend_start.sh
```

## What the start script does

`deployment/scripts/render_backend_start.sh` runs:

1. `python manage.py migrate --noinput`
2. `python manage.py bootstrap_platform || true`
3. `python manage.py collectstatic --noinput --clear`
4. `gunicorn notechondria.wsgi:application --bind 0.0.0.0:$PORT`

## Notes

- This is backend-only. The three frontend apps deploy separately to GitHub Pages.
- Free-tier instances may cold-start slowly.
- If migrations are slow, startup time may increase.
- If `bootstrap_platform` is not needed for a given environment, it safely tolerates failure in the script.
