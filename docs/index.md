# Notechondria — Long-Form Agent Handoff

Project-local agent rules and the open-work / caution list. The
canonical cross-project rules live in the
[`AGENTS.md/`](../AGENTS.md/) submodule (pinned to
[`Trance-0/AGENTS.md`](https://github.com/Trance-0/AGENTS.md)).

Read in order:

1. [`AGENTS.md/AGENTS.md`](../AGENTS.md/AGENTS.md) — shared dev
   contract (tone, scope discipline, per-stack expectations, commit
   rules).
2. §0 below — **project-specific overrides** that beat the shared
   contract when they conflict.
3. The rest of this file — repo map + open-work list.
4. [`readme.md`](readme.md) — human-facing project overview.
5. [`client/`](client/) and [`server/backend.md`](server/backend.md)
   — the per-component deep dives (three frontend apps + backend).
6. [`../LLM_CHECK.md`](../LLM_CHECK.md) — end-of-round checklist.

---

## 0. Project-specific overrides

Rules in this section **override** the shared ruleset in
[`AGENTS.md/AGENTS.md`](../AGENTS.md/AGENTS.md) when they conflict.
Keep this section short; deeper explanations belong in the per-component
docs.

- **Upstream target branch is `codex`, not `main`.** Any PR to upstream
  targets `Trance-0/Notechondria:codex`.
- **Frontend is three standalone Flutter apps** under
  `frontend/editor_app/`, `frontend/planner_app/`, `frontend/portal_app/`.
  Do not merge them back into a monolith. Per-app docs:
  [editor](client/editor_app.md), [planner](client/planner_app.md),
  [portal](client/portal_app.md).
- **Backend tests run with
  `DJANGO_SETTINGS_MODULE=notechondria.settings_test`**; that settings
  file must define a non-empty `SECRET_KEY`. See
  [`server/backend.md#tests`](server/backend.md#tests).
- **Vendor SDK clients (OpenAI, etc.) must initialize lazily at call
  time**, never at module import. As of 0.1.18 the OpenAI SDK is
  removed entirely — future AI goes through an external microservice
  over HTTP. See
  [`development/ai_integration.md`](development/ai_integration.md).
- **`backend/requirements-render.txt` stays free of heavy ML packages**
  (`torch`, `llvmlite`, `numba`, etc.) for Render free-tier
  compatibility. `backend/requirements.txt` itself is also now pruned
  of that stack; `dj-database-url` is required (Northflank + Render
  both use `DATABASE_URL`).
- **GitHub Pages builds use the project-site base paths**
  `/Notechondria/editor/`, `/Notechondria/planner/`,
  `/Notechondria/portal/`.
- **Never assume host ports** (`80`, `443`, `8080`, `5432`, …) are
  free; verify on the target machine before assigning.
- **Target Python 3.9.** The Dockerfile pins
  `python:3.9.18-bullseye`, so do NOT use PEP 604 unions (`X | Y`) in
  runtime annotations — use `typing.Optional` / `typing.Union`. This
  overrides `AGENTS.md/AGENTS.md` §4.1's "target 3.11+" default.
- **Never edit `.gitignore`.** Owner-enforced rule. If a new tracked
  template/config needs to be added, use a path the existing ignore
  rules already permit. If a tracked file drifted into holding
  secrets, copy the secrets out to a gitignored path and reset the
  tracked file — do not unlock via a new `!`-whitelist.

---

## 1. Repository map

```text
<repo>/
├── AGENTS.md/              ← git submodule (Trance-0/AGENTS.md)
├── backend/                ← Django project (see server/backend.md)
├── frontend/
│   ├── editor_app/         ← see client/editor_app.md
│   ├── planner_app/        ← see client/planner_app.md
│   ├── portal_app/         ← see client/portal_app.md
│   └── notechondria_shared/ ← shared UI primitives consumed by the
│                              three apps via path: ../notechondria_shared
├── deployment/             ← per-target CI/CD scripts (jenkins/,
│                             docker/, render/, northflank/)
├── docs/                   ← this directory
├── sample/                 ← seed course content + media
├── course_template/        ← older course template artifacts
├── LLM_CHECK.md            ← end-of-round checklist and pitfall log
├── README.md               ← repo-root overview
├── TODO.md                 ← (symlink/alias target; live TODO lives
│                             in docs/TODO.md)
├── VERSION                 ← bump third digit per round
├── northflank.json         ← Northflank infra template
├── render-deploy.sh        ← Render start wrapper
├── Jenkinsfile             ← Jenkins pipeline
└── docker-compose.yml      ← full-stack local compose
```

Not every folder is described here — see the per-component docs.

## 2. Component pointers

Instead of duplicating architecture narrative here, the long-form
detail lives next to the code:

- **Backend** — [`server/backend.md`](server/backend.md). Django
  apps (`creators`, `notes`, `mcp`, `gptutils` [stubbed]), URL
  topology, model/view/service inventory with cross-refs, the
  handshake and request-timing middleware, entrypoint flow, deploy
  paths.
- **Frontend** — [`client/editor_app.md`](client/editor_app.md),
  [`client/planner_app.md`](client/planner_app.md),
  [`client/portal_app.md`](client/portal_app.md). Role, library
  layout, local-store keys, API client contract, build/deploy, and
  known drift per app.

## 3. Backend verification reality

- Python dependencies install successfully with local `uv`/`pip`
  inside a 3.9 env.
- `manage.py test` requires a reachable PostgreSQL (or
  `settings_test.py`'s in-memory sqlite). Docker is the supported
  full-stack path locally.

## 4. Frontend verification reality

Each of `editor_app`, `planner_app`, `portal_app` passes:

- `flutter test test/smoke_test.dart`
- `flutter build web --release --base-href /Notechondria/<app>/
  --no-web-resources-cdn`

Shared UI now lives in `frontend/notechondria_shared/` and is consumed
by all three apps via a path-package dependency. Per-app `app_shell.dart`
and `modules/settings.dart` still own each app's screen-level behavior;
extract more shared widgets only when a duplication bug actually shows up.

## 5. Deployment topology (short)

Four supported paths — per-target detail lives in `deployment/`:

- **Render free-tier (backend only)** —
  [`deployment/render_free_tier.md`](deployment/render_free_tier.md).
- **Northflank (backend only)** —
  [`deployment/northflank.md`](deployment/northflank.md) +
  repo-root `northflank.json`.
- **Jenkins (full-stack self-hosted)** —
  [`deployment/deploy.md`](deployment/deploy.md).
- **GitHub Pages (frontend only)** —
  [`.github/workflows/frontend-pages.yml`](../.github/workflows/frontend-pages.yml).

Plus local Docker compose for dev.

## 6. Open work / caution list

- Shared UI primitives (sidebar, splash, error-state, debug card, auth
  dialogs, app-preferences rows, plus the `ActionFeedback` /
  `ApiDebugSnapshot` models and `showBlurDialog` /
  `formatCompactTimestamp` helpers) now live in
  `frontend/notechondria_shared/`. Per-app `app_shell.dart` and
  `modules/settings.dart` still hold their own behavior — extract more
  shared widgets only when a real second-source-of-truth bug appears,
  not preemptively.
- Backend local verification still needs a reachable PostgreSQL
  service to complete full Django test runs.
- Any future PR to upstream should target
  `Trance-0/Notechondria:codex`, not the fork's `main`.
- Render free-tier `SECRET_KEY` is a placeholder; rotate before any
  real production traffic.
- `requirements-render.txt` must stay free of heavy ML packages
  (`torch`, etc.) for free-tier compatibility.
- `portal_app` and `planner_app` still contain stale modules
  (`front.dart`, `course.dart`, `activity.dart`, `learner.dart`)
  that their `visibleIndices` don't use; removing these requires
  rewriting their `app_shell.dart`.
- `editor_app/app_shell.dart` (~2500 lines) and `client.dart`
  (~812 lines) remain above the 500-LOC target; further splits
  would need mixin-based architecture changes.
- Portal Settings is only partially at feature parity with editor
  Settings. Tracked as deferred in
  [`versions/0.1.18.md`](versions/0.1.18.md).
- Frontend compile-time default API URL
  (`_kDefaultApiUrl` in each app's `core/helpers.dart`) is baked at
  build time and doesn't react to "I changed my backend" at runtime
  for fresh visits. Use `--dart-define=DEFAULT_API_URL=...` in the
  Pages workflow or bump the fallback constant when the backend
  hostname changes. Handshake guard in Settings prevents accidental
  commits to a wrong server on runtime URL edits.
- A cosmetic `manage.py migrate --check` warning about unreflected
  `notes` app changes is non-blocking; investigate only if it
  becomes load-bearing.

## 7. Prompt recipe for the next engineer

> Work on `Trance-0/Notechondria` using the `codex` branch as the
> upstream target. Keep frontend as three standalone Flutter apps
> under `frontend/editor_app`, `frontend/planner_app`, and
> `frontend/portal_app`. Keep the Jenkins pipeline full-stack with
> backend/frontend test and deploy branches running in parallel.
> Verify each app locally with Flutter before claiming success. Run
> backend tests with
> `DJANGO_SETTINGS_MODULE=notechondria.settings_test`, keep
> `SECRET_KEY` defined there, and avoid import-time vendor SDK
> initialization. Target Python 3.9 — no PEP 604 unions at runtime.
> Follow the shared rules in
> [`AGENTS.md/AGENTS.md`](../AGENTS.md/AGENTS.md); this file's §0
> wins on conflicts.
