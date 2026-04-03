# Docker full-stack deployment

This target runs the entire stack locally or on a single host via root `docker-compose.yml`.

## Services
- `db`
- `app`
- `backend_nginx`
- `editor_frontend`
- `planner_frontend`
- `portal_frontend`
- `gateway_nginx`

## Files
- `.env.example` — local full-stack environment example
- `nginx/default.conf` — root gateway reverse proxy for backend + three frontends
- `scripts/up.sh` / `scripts/down.sh` / `scripts/test.sh`

## Usage
```bash
cp deployment/docker/.env.example .env
docker compose up --build -d
```
