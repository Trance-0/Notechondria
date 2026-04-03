# Render backend deployment

Use Render for the Django backend and PostgreSQL, and GitHub Pages for the frontends.

## Backend
- Start script: `scripts/render_backend_start.sh`
- Environment example: `.env.example`

## Required services
- Render web service for backend
- Render PostgreSQL (or another managed PostgreSQL)

## Build command
```bash
pip install -r backend/requirements.txt
```

## Start command
```bash
bash deployment/render/scripts/render_backend_start.sh
```

## Frontend
See `github-pages/README.md` for GitHub Pages setup.
