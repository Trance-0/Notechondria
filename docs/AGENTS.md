# docs/AGENTS.md — Notechondria project-specific agent rules

This file extends the canonical rules at the repo root's `AGENTS.md`
(which inherits from the `github.com/Trance-0/AGENTS.md` submodule).
Only project-specific overrides and conventions live here.

## Branch workflow override

Work directly on `main` unless the owner explicitly names another
branch. Other branches in this repository are backup / provenance
branches before major changes, not active collaboration lanes. Codex is
the only active coding worker here, so this project overrides the shared
branch-discipline default that normally prefers feature branches when a
repo has branches other than `main`.

## Host resource budget (IMPORTANT — a violation crashed the dev host)

NEVER RUN TEST CASES OR CONTAINERS THAT THE HOST MAY NOT AFFORD. On
2026-07-10 an agent launched `docker compose up --build -d` (three
parallel Flutter web builds + seven services) on the shared dev host
(3.3 GiB RAM, 2 cores, ~half already used by other stacks) and took
the machine down. Rules, in force for every future round on any host:

1. **Measure before you launch.** Run `free -h` and `nproc`, and list
   running containers, before starting any build, test suite, or
   container. You do not know the host's headroom until you check —
   same discipline as the host-port rule.
2. **Never take more than 70% of the *remaining* RAM.** Budget the
   worst-case footprint of what you are about to start (a Flutter web
   build can spike well past 1.5 GiB; a Django test container needs
   ~300 MiB). If the worst case exceeds 70% of currently-available
   memory, do not run it — split it, cap it, or declare it not
   runnable on this host and say so in the round summary.
3. **Hard-cap everything you start.** Containers get an explicit
   `--memory` limit sized within the budget; builds and test runs are
   wrapped in `timeout` (or an equivalent) so nothing runs unbounded.
4. **Terminate after 5 minutes of silence.** Any process with no
   output for 5 minutes is presumed wedged: kill it, record what
   happened, and fall back — do not wait and do not retry the same
   invocation at the same scale.
5. **Sequential, never parallel, heavy jobs.** One Flutter build or
   one test container at a time. Parallel heavy builds are what
   crashed the host.
6. **Always have a fallback plan** stated before the heavy step: what
   you will do if it OOMs or hangs (smaller target, backend-only
   verification, or explicitly deferring to a bigger machine / CI).
   "Rebuild everything and hope" is not a plan.

On this specific dev host (2 cores / 3.3 GiB, shared with frps,
portainer, openresty, openclaw): backend-only Docker verification is
affordable; **frontend Flutter Docker builds and the full-stack
compose are NOT** — defer those to CI (GitHub Actions Pages workflow)
or an owner-approved window where other stacks are stopped.

## Deployment topology & no-local-containers rule (owner, 2026-07-10)

This project does NOT deploy locally. The live topology is:

- **Frontend** — GitHub Pages, built by
  `.github/workflows/frontend-pages.yml` on push to `main`.
- **Docs** — GitHub Pages `docs/` subtree, built by
  `.github/workflows/docs-pages.yml` (split from the frontend leg in
  0.1.161 so a failure in either cannot block the other; both publish
  disjoint subtrees of `gh-pages` with `keep_files: true` under one
  concurrency group). The docs leg fails if `docs/SUMMARY.md` does not
  list `versions/<VERSION>.md` — **every round that adds a version doc
  must also add its SUMMARY.md entry.**
- **Backend** — Northflank CI/CD deploys on commit. Backend + CLI test
  suites run in `.github/workflows/backend-tests.yml` on push.

**Do NOT create local containers for this project on any machine with
less than 16 GB RAM** (this dev host has 3.3 GiB). No `docker compose
up`, no image builds, no test containers — the deployment paths above
are the only build/run environments. Pre-push verification on a small
host is limited to what runs on the host Python (the `cli/` unit
tests) and static checks; everything else is proven by CI after the
owner pushes, and any check not run locally is called out per
LLM_CHECK. The docker-compose files stay in the repo for CI and for
≥16 GB self-host targets only.

## Round-end verification convention (owner, urgent)

Because the suites cannot run on this host (no Flutter SDK; host Python
is 3.14 while the backend pins 3.11-era deps; local containers are
banned), verification is split between local static checks and
CI-after-push. Do these every round:

**Before pushing (local):**

- `cd cli && python3 -m unittest discover -s tests` when `cli/` changed
  (stdlib only — no network, no MCP SDK).
- `python -m py_compile <files>` for every changed backend file;
  a bracket-balance pass for every changed Dart file (catches the
  syntax errors CI would otherwise be the first to see).
- Confirm bookkeeping: `VERSION` bumped, `docs/versions/<v>.md` **and**
  its `docs/SUMMARY.md` entry added in the same commit, `LLM_CHECK.md`
  round log appended. Skip the version bump for repo-tooling-only
  changes (e.g. `.mcp.json`) so it doesn't trigger a no-op rebuild.
- State explicitly which checks were NOT run locally (per LLM_CHECK).

**After pushing (CI + deployed artifacts).** There is no `gh` CLI or
GITHUB token here, but the repo is public, so read status from the
GitHub REST API (unauthenticated, ~60 req/hr):

- **CI conclusions:**
  `GET /repos/Trance-0/Notechondria/actions/runs?per_page=N`, filter by
  `head_sha` + `name` (`backend-tests` / `frontend-pages` /
  `docs-pages`), read `status`/`conclusion`. On a failure,
  `…/actions/runs/<id>/jobs` names the failing step (raw logs need auth
  → 403, but the step name is usually enough to localise the bug).
  `backend-tests` is path-filtered — it only runs when `backend/`
  changed.
- **Backend deploy landed:** probe
  `https://notechondria.trance-0.com/api/v1/handshake/`.
- **Frontend deploy landed with the new code:** curl the deployed bundle
  and grep the baked version —
  `curl -s https://trance-0.github.io/Notechondria/<app>/main.dart.js |
  grep -oE '0\.1\.[0-9]+'` — for editor / planner / portal. A green
  `frontend-pages` is necessary but not sufficient: a concurrency race
  once cancelled a build and left a stale bundle (0.1.190), so always
  confirm the dominant `0.1.NNN` in the bundle matches `VERSION`. CI's
  `Test <app>` step runs only `test/smoke_test.dart`, so any logic that
  must be CI-checked belongs there (the shared package's own tests are
  not CI-run).

## §1.7 compliance — canonical module / process names

The canonical `AGENTS.md` §1.7 mandates that every error, warning, info,
and diagnostic message contain three components:

1. **Consequence** — what the user or system can no longer do.
2. **Source module + process** — stable, greppable `Module / process`.
3. **Cause / triggering condition** — the specific trigger.

Informal shape: `"<consequence>: <module>/<process> — <cause>"`.

This project's canonical module / process names are:

| Module (dotted) | Surface | Example processes |
|---|---|---|
| `Editor.Auth` | editor_app auth flows | `restore`, `login`, `oauth.callback`, `logout`, `bind`, `register`, `verify`, `password.reset` |
| `Editor.Sync.Settings` | editor settings sync | `bootstrap`, `save`, `push`, `pull` |
| `Editor.Sync.Courses` | editor category sync | `create`, `update`, `delete`, `reorder`, `push`, `pull` |
| `Editor.Sync.Notes` | editor note sync | `list`, `load`, `save`, `delete`, `pull_public` |
| `Editor.LocalStore` | editor local persistence | `load`, `save`, `clear`, `seed_starter` |
| `Editor.Session` | editor token/profile handling | `restore`, `reject`, `clear` |
| `Editor.UI` | editor user-visible actions | `open_note`, `switch_course`, `feedback` |
| `Planner.Auth` | planner_app auth flows | same verbs as `Editor.Auth` |
| `Planner.Sync.Events` | planner event/course sync | same verbs |
| `Planner.LocalStore` | planner local persistence | same verbs |
| `Planner.UI` | planner user-visible actions | same verbs |
| `Portal.Auth` | portal_app auth flows | same verbs as `Editor.Auth` |
| `Portal.Sync.FrontPage` | portal front-page sync | `pull` |
| `Portal.LocalStore` | portal local persistence | same verbs |
| `Portal.UI` | portal user-visible actions | same verbs |
| `Shared.AuthDialog` | `notechondria_shared` auth dialog stack | `login.submit`, `register.submit`, `verify.submit`, `reset.request`, `reset.confirm` |
| `Shared.DebugLog` | shared debug log card / terminal | `ls`, `cd`, `clear`, `copy`, `unknown_command` |
| `Backend.Creators.Auth` | `backend/creators/api.py` auth endpoints | `register`, `login`, `verify`, `bind`, `oauth.google`, `oauth.github`, `password.reset` |
| `Backend.Creators.Settings` | creators settings endpoints | `get`, `update` |
| `Backend.Notes.Courses` | `backend/notes/api.py` course endpoints | `list`, `create`, `update`, `delete`, `reorder` |
| `Backend.Notes.Notes` | notes endpoints | `list`, `create`, `update`, `delete`, `restore`, `empty_trash` |
| `Backend.Notes.Import` | import/export endpoints | `parse`, `validate` |
| `Backend.Mcp.Protocol` | `backend/mcp/` MCP protocol plumbing | `handshake`, `tool_call`, `tool_list` |
| `Backend.Gptutils` | OpenAI/vendor client wrappers | `complete`, `embed`, `parse` |

Component-assembly convention:

- Dart host apps write structured entries with the shared `DebugLogEntry`
  — `source` field = the table row above, `message` field = the
  `<consequence> — <cause>` pair.
- User-facing SnackBars / dialogs / `ActionFeedback.message` strings
  follow the full `"<consequence>: <module>/<process> — <cause>"` shape
  so the operator can paste the string back into logs verbatim.
- Backend exception messages and `Response({"detail": ...})` payloads
  follow the same full shape. Tests that historically matched narrow
  substrings (e.g. `"bind"` in account-binding rejection detail) keep
  those substrings **intact** — rewording appends context without
  dropping the sentinel.

Preserved parser sentinels (verbatim substrings that must survive any
rewrite, documented here so future agents don't strip them):

- `invalid token` / `authentication credentials were not provided` /
  `token_not_valid` — editor `_loadInitialData` session-rejection detector.
- `not_registered` / `No account found` — OAuth registration prompt.
- `bind` — backend account-binding tests in
  `backend/creators/tests.py::test_*_bind*`.

## Bark push notifications after commit / before push

If there is any `*.bark.env` file in the project root, treat its
contents as Bark push URLs (one URL per file, possibly multiple
files). After all tests pass and you are ready to push, send a
short progress summary to every Bark URL by POSTing JSON to the
URL without the trailing `/$0` segment:

```bash
curl -sS -X POST <URL_WITHOUT_/$0> \
  -H 'Content-Type: application/json' \
  -d '{"title":"Notechondria 0.1.XX ready to push","body":"<short summary>"}'
```

`*.bark.env` files are covered by `*.env` in `.gitignore` — never
commit them, never echo their contents to logs or commit messages,
and never include them in any PR body. The URL contains a
device-specific secret.

See <https://bark.day.app/> for the Bark API reference. Keep
notifications short (1 line body) so they render on the iOS lock
screen without truncation.
