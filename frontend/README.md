# Frontend (Flutter)

This Flutter app is the client for the Canvas-like calendar experience.

## Structure

- `lib/main.dart`: thin library entrypoint.
- `lib/app_shell.dart`: top-level app shell and shared app state.
- `lib/core/`: shared client and helper logic.
- `lib/components/`: reusable UI components.
- `lib/modules/`: independent page modules for `front`, `learner`, `course`, `activity`, and `settings`.

## Pages in MVP scaffold

- Front Page
- Learner View
- Course View
- Activity View
- Settings View

Each page is reachable from the bottom navigation bar in `lib/main.dart`.

## Run locally

```bash
flutter pub get
flutter run -d chrome
```

## Docker web build

```bash
docker compose --env-file ../sample.env -f docker-compose.yml up --build -d
```

The standalone web container serves the Flutter build on `FRONTEND_HOST_PORT`. The image compiles with `FRONTEND_API_BASE_URL` and the nginx runtime proxies `/api`, `/admin`, `/static`, and `/media` to `FRONTEND_BACKEND_ORIGIN`.

## Test

```bash
flutter test
```
