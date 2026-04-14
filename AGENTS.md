# AGENTS.md

This project inherits the canonical agent-handoff rules from
[`Trance-0/AGENTS.md`](https://github.com/Trance-0/AGENTS.md), pinned here as
a git submodule at [`.agents/`](.agents/).

## How to read this file

1. **Shared rules** — read [`.agents/AGENTS.md`](.agents/AGENTS.md) for the
   cross-project development contract (tone, scope, safety, docs rule,
   per-stack expectations, commit/PR defaults).
2. **End-of-round checklist** — see [`LLM_CHECK.md`](LLM_CHECK.md) at this
   repo's root for project-specific pitfalls and the round-end audit.
3. **Project-specific architecture, state, deploy topology, open-work list,
   and prompt recipe** — see [`docs/index.md`](docs/index.md) (migrated from
   the old root `AGENTS.md`).
4. **Human-facing overview** — see [`docs/readme.md`](docs/readme.md) and
   the top-level [`README.md`](README.md).

## Project-specific overrides

Rules here **override** the shared ruleset in `.agents/AGENTS.md` when they
conflict. Keep this section short; deeper explanation belongs in
`docs/index.md`.

- Upstream target branch is `codex`, not `main`.
- Frontend is three standalone Flutter apps under `frontend/{editor,planner,portal}_app`.
  Do not merge them back into a monolith.
- Backend tests run with `DJANGO_SETTINGS_MODULE=notechondria.settings_test`;
  that settings file must define a non-empty `SECRET_KEY`.
- Vendor SDK clients (OpenAI, etc.) must initialize **lazily at call time**;
  never at module import.
- `backend/requirements-render.txt` stays free of heavy ML packages
  (`torch`, `llvmlite`, `numba`, etc.) for Render free-tier compatibility.
- GitHub Pages builds use the project-site base paths
  `/Notechondria/editor/`, `/Notechondria/planner/`, `/Notechondria/portal/`.
- Never assume host ports (`80`, `443`, `8080`, `5432`, …) are free; verify
  on the target machine before assigning.

## Updating the shared ruleset

The `.agents/` submodule is pinned. To bump it:

```bash
git submodule update --remote .agents
git add .agents
git commit -m "chore: bump .agents submodule"
```

Do this only when the owner asks, or when a change to the shared rules is
required for a feature in this repo.
