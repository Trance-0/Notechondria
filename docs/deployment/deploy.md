# Deployment Guide

## 1) Prepare environment

### Local

1. Copy `sample.env` to `.env`.
2. Fill PostgreSQL credentials, Django secret key, and optional GitHub app keys.

### Jenkins-injected deployment env

Do not commit the real deployment `.env` file. Instead, inject deployment variables in Jenkins and let the pipeline materialize `.env.deploy` during the build.

Recommended setup with the Environment Injector plugin:

1. Open the job configuration.
2. Enable `Prepare an environment for the run`.
3. Check `Keep Jenkins Environment Variables`.
4. Check `Keep Jenkins Build Variables`.
5. Leave `Override Build Parameters` enabled only if you intentionally want injected values to win over build parameters.
6. Use `Properties Content` or `Properties File Path` to define the deployment variables using the keys shown in `sample.env`.
7. Save the job.
8. Run one manual build to verify the injected variables reach the pipeline.

If your repository is public, remove SCM credentials from the Pipeline SCM job configuration. The Jenkinsfile does not require repository credentials by itself.

The pipeline writes those injected variables to `${WORKSPACE}/.env.deploy` through `deployment/scripts/prepare_env.sh`.

Example `Properties Content`:

```properties
DJANGO_SECRET_KEY=replace-with-real-secret
DJANGO_DEBUG=False
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,app.example.com
DJANGO_ALLOWED_HOSTS_COMPOSE=localhost 127.0.0.1 app.example.com
DJANGO_CSRF_TRUSTED_ORIGINS=http://localhost:9080,http://localhost:9060,http://localhost:8080
DJANGO_LOG_LEVEL=INFO
DJANGO_LOG_FILE_NAME=notechondria
DJANGO_SUPERUSER_USERNAME=admin
DJANGO_SUPERUSER_EMAIL=admin@example.com
DJANGO_SUPERUSER_PASSWORD=change-me
APP_HOST_PORT=9080
BACKEND_HOST_PORT=9090
FRONTEND_HOST_PORT=9060
FRONTEND_FLUTTER_HOST_PORT=8080
DB_HOST_PORT=9032
POSTGRE_USERNAME=postgres
POSTGRE_PASSWORD=replace-with-real-password
POSTGRE_HOST=db
POSTGRE_PORT=5432
POSTGRE_DB=postgres
PRODUCTION_STATIC_ROOT=/home/staticfiles/
PRODUCTION_MEDIA_ROOT=/home/mediafiles/
OPENAI_API_KEY=
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_USE_TLS=True
SMTP_USE_SSL=False
SMTP_FROM_EMAIL=no-reply@example.com
EMAIL_VERIFICATION_TTL_HOURS=24
FRONTEND_VERIFY_URL=http://localhost:9060/#/verify
FRONTEND_API_BASE_URL=/api/v1
FRONTEND_BACKEND_ORIGIN=http://host.docker.internal:9080
GITHUB_APP_ID=
GITHUB_APP_CLIENT_ID=
GITHUB_APP_CLIENT_SECRET=
GITHUB_APP_PRIVATE_KEY_PATH=
GITHUB_APP_WEBHOOK_SECRET=
APP_IMAGE=trancezero/notechondria:build-${BUILD_NUMBER}
NGINX_IMAGE=trancezero/nginx:build-${BUILD_NUMBER}
FRONTEND_IMAGE=trancezero/notechondria-frontend:build-${BUILD_NUMBER}
```

Important formatting notes:

- `DJANGO_ALLOWED_HOSTS` should stay comma-separated for human editing.
- `DJANGO_ALLOWED_HOSTS_COMPOSE` should stay space-separated because the Docker Compose app service passes it to Django as `ALLOWED_HOSTS`.
- Do not wrap the values in quotes in `Properties Content`.
- For Docker deployment, set `POSTGRE_HOST=db`. Do not switch database host to `localhost` just because `DJANGO_DEBUG=True`; inside the app container, PostgreSQL is reached through the Compose service network.

Jenkins must provide at least:

- `DJANGO_SECRET_KEY`
- `DJANGO_ALLOWED_HOSTS_COMPOSE`
- `APP_HOST_PORT`
- `BACKEND_HOST_PORT`
- `FRONTEND_HOST_PORT`
- `FRONTEND_FLUTTER_HOST_PORT`
- `DB_HOST_PORT`
- `POSTGRE_USERNAME`
- `POSTGRE_PASSWORD`
- `POSTGRE_HOST`
- `POSTGRE_PORT`
- `POSTGRE_DB`

## 2) Local Docker deployment

```bash
cd backend
docker compose --env-file ../.env up --build -d
```

```bash
cd frontend
docker compose --env-file ../.env up --build -d
```

## 3) Initialize database

```bash
docker compose exec app python manage.py migrate
docker compose exec app python manage.py collectstatic --noinput
```

## 4) Run tests before release

```bash
cd /workspace/Notechondria
bash deployment/scripts/test_backend.sh /workspace/Notechondria /workspace/Notechondria/.env.deploy
```

## 5) Jenkins pipeline flow

The pipeline now runs in this order:

1. Checkout source.
2. Generate `${WORKSPACE}/.env.deploy` from Jenkins-injected environment variables.
3. Start the `db` service and back up PostgreSQL from the database container.
4. Run backend and frontend tests in parallel using Docker only.
5. Build and deploy backend and frontend containers in parallel.

The relevant files are:

- `Jenkinsfile`
- `deployment/scripts/prepare_env.sh`
- `deployment/scripts/backup_postgres.sh`
- `deployment/scripts/ensure_db_ready.sh`
- `deployment/scripts/test_backend.sh`
- `deployment/scripts/test_frontend.sh`
- `deployment/scripts/wait_for_stack.sh`
- `deployment/scripts/wait_for_frontend.sh`
- `deployment/scripts/deploy_backend.sh`
- `deployment/scripts/deploy_frontend.sh`

### Compose stack shape

The Docker Compose stack is named `notechondria` and contains separate containers for:

- `app`: Django/gunicorn backend
- `db`: PostgreSQL 15
- `nginx`: reverse proxy/static serving

The standalone frontend Compose stack is named `notechondria-frontend` and contains:

- `frontend`: nginx-served Flutter web build

Jenkins only needs Docker access. It does not need host `python` or host `pg_dump`.
The Django container talks to PostgreSQL through the internal Compose service host `db`.
Internal container ports stay fixed:

- `app` listens on `8000`
- `db` listens on `5432`
- `nginx` listens on `80`

Only the host-exposed ports are configurable:

- `APP_HOST_PORT` maps host -> `nginx:80`
- `BACKEND_HOST_PORT` maps host -> `app:8000`
- `FRONTEND_HOST_PORT` maps host -> `frontend:80`
- `FRONTEND_FLUTTER_HOST_PORT` maps host -> `frontend:80`
- `DB_HOST_PORT` maps host -> `db:5432`

Deployment readiness waits at most 300 seconds before failing and stopping the web containers.
The backend entrypoint now runs `collectstatic --clear`, verifies that Django admin and DRF assets exist under `/home/staticfiles`, and the stack wait step now requires both `app` and `nginx` to report healthy before Jenkins treats the deployment as ready.
The test stage does not use the postgres container; it runs Django tests with `settings_test` directly in an app container without the production entrypoint.
The app service must not mount a named volume over `/home/notechondria`, because that path contains the Django code copied into the image during build.
The Jenkins build can tag images with the current build number using `APP_IMAGE`, `NGINX_IMAGE`, and `FRONTEND_IMAGE`, for example `trancezero/notechondria:build-${BUILD_NUMBER}`.

### PostgreSQL volume behavior

The `db` container uses a persistent Docker volume. PostgreSQL reads `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` only when the data directory is initialized the first time.

If you later change `POSTGRE_USERNAME` or `POSTGRE_DB` in Jenkins but keep the same Docker volume, the container will start with the old cluster state and the new role may not exist. In that case you must do one of these:

1. keep the Jenkins credential aligned with the already-initialized database role/database, or
2. remove the existing `notechondria` postgres volume and let the cluster initialize again with the new env values.

The pipeline now validates database access over TCP with the configured username and password before deploying the app container. That check is meant to catch password mismatches before Django reaches `manage.py migrate`.

For disposable Jenkins environments, you can set:

```properties
DB_AUTO_REINIT_IF_MISMATCH=True
```

This allows the deploy step to remove and recreate the `notechondria_postgres-data` volume automatically if the configured credentials do not match the existing cluster.

For a first smoke deployment, `sample.test.env` now uses the default `postgres` role/database to reduce that mismatch risk.
On a first deployment, the backup step may skip automatically because there is no usable database state yet. That is expected and does not block the rest of the pipeline.

### Windows Jenkins checkout note

If Jenkins runs on Windows and checkout still fails before the pipeline starts, enable Git long-path support on the Jenkins host and keep the workspace path short.

Recommended host setting:

```powershell
git config --system core.longpaths true
```

If needed, also move the Jenkins workspace root to a shorter directory such as `C:\Jenkins`.

This repository now keeps only the Monaco `min/` runtime bundle under `backend/static/monaco-editor/` to reduce checkout path depth.

## 6) Frontend web build (standalone container)

```bash
cd frontend
docker compose --env-file ../.env up --build -d
```

The frontend container builds Flutter web with `FRONTEND_API_BASE_URL`, serves the resulting static site through nginx on `FRONTEND_HOST_PORT` and `FRONTEND_FLUTTER_HOST_PORT`, and proxies `/api`, `/admin`, `/static`, and `/media` to `FRONTEND_BACKEND_ORIGIN`.

## 7) Test deployment template

Use `sample.test.env` as a safe starting point for a non-production Jenkins credential or local smoke deployment. Replace placeholders before any real deploy.

## 8) Rollback

1. Restore database from latest SQL dump generated by CI backup step.
2. Redeploy previous Docker image tag.
