# docs/AGENTS.md — Notechondria project-specific agent rules

This file extends the canonical rules at the repo root's `AGENTS.md`
(which inherits from the `github.com/Trance-0/AGENTS.md` submodule).
Only project-specific overrides and conventions live here.

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
