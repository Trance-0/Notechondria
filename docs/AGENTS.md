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
