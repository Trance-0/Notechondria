# Local Development Guide

This page describes how to set up and run each component locally for
development and debugging.

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | stable channel (>=3.24) | `flutter doctor` to verify |
| Python | 3.11+ | Backend only |
| Docker & Docker Compose | latest | Full-stack or individual services |
| Node.js | 20+ | GitHub Actions only (not needed locally) |

## Frontend (Flutter Web)

All three frontend apps live under `frontend/` and share the same workflow.

### Install dependencies

```bash
cd frontend/editor_app
flutter pub get
```

Repeat for `planner_app` and `portal_app` if needed.

### Run in development mode

```bash
# Editor app (default port 9060)
cd frontend/editor_app
flutter run -d chrome --web-port 9060

# Planner app
cd frontend/planner_app
flutter run -d chrome --web-port 9061

# Portal app
cd frontend/portal_app
flutter run -d chrome --web-port 9062
```

The dev server supports hot-reload. Press `r` in the terminal to reload,
`R` for full restart.

#### Pointing at a local backend

By default the frontend reads `API_BASE_URL` from the compile-time
`--dart-define`. During `flutter run` you can override it:

```bash
flutter run -d chrome --web-port 9060 \
  --dart-define=API_BASE_URL=http://localhost:9090/api/v1
```

### Run tests

```bash
cd frontend/editor_app
flutter test test/smoke_test.dart -r compact
```

### Build for production (local preview)

```bash
cd frontend/editor_app
flutter build web --release --no-tree-shake-icons
# Output: build/web/
# Serve with any static server:
cd build/web && python3 -m http.server 8080
```

## Backend (Django)

### Set up Python environment

```bash
cd backend
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

pip install -r requirements.txt
```

### Configure environment

```bash
cp ../sample.env ../.env
# Edit ../.env with your database credentials and secrets
```

### Run migrations and create superuser

```bash
cd backend
python manage.py migrate
python manage.py createsuperuser
```

### Start the development server

```bash
cd backend
python manage.py runserver 0.0.0.0:9090
```

The admin panel is at `http://localhost:9090/admin/`.

### Run backend tests

```bash
cd backend
python manage.py test --settings=notechondria.settings_test
```

Or with pytest:

```bash
cd backend
python -m pytest
```

## Full Stack (Docker Compose)

To run everything together:

```bash
cp sample.env .env
# Edit .env as needed

docker compose up --build -d
```

This starts the backend, database, nginx gateway, and all three frontend
apps. The editor is at `http://localhost:8080/editor/`, planner at
`/planner/`, portal at `/portal/`.

### Viewing logs

```bash
# All services
docker compose logs -f

# Single service
docker compose logs -f app
```

### Rebuilding after code changes

```bash
# Backend only
docker compose build app nginx && docker compose up -d app nginx

# Frontend only (e.g. editor)
cd frontend/editor_app
docker compose build && docker compose up -d
```

## Debugging Tips

### Frontend: WebGL fallback warning

If you see `WARNING: Falling back to CPU-only rendering. Reason:
webGLVersion is -1`, this is expected in environments without GPU
acceleration (CI, some VMs). Flutter automatically falls back to the HTML
renderer, which works correctly but may feel slower in dev tools.

### Frontend: CORS issues with avatars

When running the frontend dev server against a remote backend, avatar
images from Cloudflare R2 may fail to load due to CORS. Configure the
R2 bucket CORS policy to allow your local origin (`http://localhost:9060`).

### Backend: Django import warnings in IDE

If your IDE shows unresolved import warnings for `django` or
`rest_framework`, make sure the Python interpreter is set to the virtual
environment at `backend/.venv/`.

### Backend: checking OAuth logs

OAuth binding issues are logged at INFO/WARNING level. To see them:

```bash
# In Docker
docker compose logs -f app | grep -i "bind\|oauth"

# Local dev
# Logs go to the file configured by DJANGO_LOG_FILE_NAME in .env
tail -f logs/notechondria.log | grep -i "bind\|oauth"
```
