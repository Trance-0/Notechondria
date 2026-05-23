# Backend API Specification

The backend now exposes a DRF-first API under `/api/v1/`. Django-rendered product pages are no longer the primary client surface; Django remains responsible for `/admin/`, API routes, and static/media delivery behind nginx.

## Authentication

Authentication uses DRF token auth.

1. `POST /api/v1/auth/register/` with `email` and `password`.
2. The backend sends a verification code through SMTP using the env-provided credentials.
3. `POST /api/v1/auth/verify-email/` with `email` and `code`.
4. Reuse the returned token in `Authorization: Token <token>`.

## Public routes

- `GET /api/v1/health/`
- `GET /api/v1/front-page/`
- `GET /api/v1/courses/`
- `GET /api/v1/courses/{course_id}/`
- `GET /api/v1/courses/{course_id}/notes/`
- `GET /api/v1/notes/{note_id}/` for notes in the default seeded course
- `GET /api/v1/activity/`

## Auth routes

- `POST /api/v1/auth/register/`
- `POST /api/v1/auth/verify-email/`
- `POST /api/v1/auth/resend-verification/`
- `POST /api/v1/auth/login/`
- `POST /api/v1/auth/logout/`
- `GET /api/v1/auth/session/`

## Authenticated user routes

- `GET /api/v1/settings/`
- `PATCH /api/v1/settings/`
- `GET /api/v1/notes/`
- `POST /api/v1/notes/`
- `PATCH /api/v1/notes/{note_id}/`
- `POST /api/v1/notes/{note_id}/blocks/`
- `PATCH /api/v1/blocks/{block_id}/`
- `DELETE /api/v1/blocks/{block_id}/`
- `POST /api/v1/notes/{note_id}/reorder/`
- `POST /api/v1/courses/{course_id}/subscribe/` subscribes the
  signed-in user to a cloud course and clears private-subscription
  visibility if the course had previously been kept private.
- `POST /api/v1/courses/{course_id}/subscribe-private/` keeps the
  course as a private sidebar subscription for the signed-in user
  (`is_private_subscription: true`) without republishing it.
- `DELETE /api/v1/courses/{course_id}/subscribe/` deactivates the
  signed-in user's subscription.

## Seed data

On startup the backend runs `python manage.py bootstrap_platform`, which:

- creates or updates the env-driven Django admin user
- seeds three sample courses if the database is empty
- creates a demo creator account named `CodeX` and logs the generated credentials
- builds the default `Vibe Coding 101` notes from `CODEX.md`
- loads per-course media metadata from the repository `sample/<slug>/` directories

## Example requests

```bash
curl -X POST http://localhost:9090/api/v1/auth/register/ \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"strong-pass-123"}'
```

```bash
curl -X POST http://localhost:9090/api/v1/auth/verify-email/ \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","code":"paste-code-from-email"}'
```

```bash
curl http://localhost:9090/api/v1/front-page/
```
