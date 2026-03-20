# CODEX Build Report

This file summarizes a pragmatic way to rebuild the current Notechondria workspace from scratch with prompt-driven iterations.

## 1. Project outcome

The repository is organized around:

- `backend/`: Django application, tests, Docker assets, deployment entrypoints.
- `frontend/`: Flutter web/client MVP shell.
- `docs/`: API, deployment, testing, and integration documentation.
- `deployment/`: CI/CD helper scripts.
- `course_template/`: course content template and validation target.

## 2. Recommended build order

Use this order when recreating or extending the project:

1. Bootstrap repository structure and top-level docs.
2. Build the Django backend and basic auth/note flows.
3. Add test-only Django settings and backend test coverage.
4. Add the Flutter shell with page-level navigation.
5. Add deployment docs, API docs, sample env, and GitHub App guidance.
6. Add Jenkins pipeline and deployment scripts.
7. Verify with backend tests and any locally available frontend tooling.

## 3. Prompt sequence

These prompts are written so a future Codex run can recreate the same shape of work with less ambiguity.

### Prompt A: repository scaffold

```text
Create a maintainable project structure for a Django backend and Flutter frontend.
Keep backend/, frontend/, docs/, deployment/, and course_template/ as first-level directories.
Preserve existing code when present and avoid destructive git operations.
```

### Prompt B: backend hardening

```text
Inspect the Django backend and add rigorous but efficient tests for creators, notes, and gptutils.
Use a dedicated test settings module that runs on sqlite in memory and disables optional apps that are not required for CI.
Prefer smoke tests for authenticated views and focused model/utility tests for behavior.
```

### Prompt C: frontend MVP shell

```text
Build a Flutter MVP shell for Notechondria with pages for front page, learner view, course view, activity view, and settings.
Include a course selector and calendar-like task strips, and make the selected course flow through learner and activity views.
Add widget tests that verify navigation and course-selection behavior.
```

### Prompt D: docs and operations

```text
Write concise operational docs for deployment, backend API usage with example requests, backend test scope, and GitHub App integration.
Add sample.env with server environment variables required by Docker and optional integrations.
Link the docs from the repository README.
```

### Prompt E: CI/CD

```text
Add a Jenkins pipeline for Django deployment triggered by GitHub webhook.
Back up the PostgreSQL database before test/deploy stages.
Place helper scripts under deployment/scripts and make sure script arguments match the Jenkinsfile invocation.
```

### Prompt F: repo hygiene and review loop

```text
Revise .gitignore so common OS junk, editor settings, local env files, Python caches, and Flutter build outputs are ignored.
Create CODEX.md summarizing how to rebuild the project with prompts.
Create LLM_CHECK.md listing common mistakes from prior rounds and use it as a final checklist before closing each modification round.
```

## 4. Environment bootstrap

### Backend

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r backend/requirements.txt
copy sample.env .env
set DJANGO_SETTINGS_MODULE=notechondria.settings_test
python backend/manage.py test creators notes gptutils
```

### Docker deployment path

```bash
cd backend
docker compose --env-file ../.env up --build -d
docker compose exec app python manage.py migrate
docker compose exec app python manage.py collectstatic --noinput
```

### Frontend

```bash
cd frontend
flutter pub get
flutter test
flutter run -d chrome
```

## 5. Prompting rules that worked

- Ask for inspection first when the repo may already be partially changed.
- Ask for concrete deliverables, not just "improve the app."
- Require verification steps and mention environment limitations explicitly.
- Call out non-negotiable constraints such as no destructive git operations.
- When adding CI scripts, require argument validation between the pipeline and the scripts.

## 6. End-of-round expectation

Every substantial modification round should end with:

1. Targeted code/doc edits.
2. Available test execution.
3. An `LLM_CHECK.md` pass against the new changes.
