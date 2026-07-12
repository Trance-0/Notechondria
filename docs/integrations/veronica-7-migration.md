# Veronica-7 → Notechondria course migration

Runbook for binding the public VitePress site
[`colorful-numbers/Veronica-7`](https://github.com/colorful-numbers/Veronica-7)
as a Notechondria course, using the course-repo adapter
(`backend/courses/course_repo.py`) and the lazy-sync engine
(`backend/courses/git_service.py`, shipped 0.1.174).

## Adapter validation (done, read-only)

The adapter was run against the **real** Veronica-7 tree (211 blobs, 195
markdown files) — read-only, no fork, no writes — reproducing production
behaviour by feeding it the GitHub tree API's path list (which, unlike a
local `glob`, includes dotfiles such as `docs/.vitepress/`):

- `infer_preset` → **`vitepress`** (detects `docs/.vitepress/config.mts`).
- `.vitepress/**` and `public/**` are excluded; repo-root `README.md` /
  `TODO.md` never leak in (content root is `docs`).
- **module_depth: 1** → 6 modules, all 193 course notes, **0 warnings**:
  `cv` → "Modern CV — Overview", `dnn` → "Deep Neural Networks",
  `fundamentals` → "Fundamentals & History", `llm` → "Large Language
  Models", `transformer-era` → "The Transformer Era", plus the landing
  pages (`docs/index.md`, `docs/about.md`, `docs/templates.md`).
- **module_depth: 2** → 37 fine-grained modules (e.g. `cv/advances`,
  `dnn/rl`, `transformer-era/2023-2024`).
- Frontmatter (`title`, `order`, …) round-trips through
  `compose_markdown`, so a later sync re-emits it and doesn't disturb the
  site's rendering.

**Result: no adapter bug.** Depth 1 is the recommended grouping (clean,
index-titled modules that mirror the VitePress sidebars).

## The config to add (validated)

Add this as `notechondria.course.yaml` at the repo root. The preset is
auto-inferred, so this file only pins intent and titles:

```yaml
version: 1
preset: vitepress          # docs root, .vitepress/** + public/** excluded
course:
  title: "Project Veronica — Modern ML/CV"
  slug: veronica-7
  description: "A living survey of modern computer vision and deep learning."
content:
  module_depth: 1          # 6 modules mirroring the VitePress sidebars
sync:
  write: ["**/*.md"]       # sync writes markdown only; never .vitepress/**, code, or CI
```

## Execution (DONE — 2026-07-12, on production)

All steps ran end-to-end against `https://notechondria.trance-0.com`:

1. **Forked** `colorful-numbers/Veronica-7` → `Nesbitt-bot/Veronica-7`
   (bot PAT).
2. **Added `notechondria.course.yaml`** to the fork `main` (the config
   above) via the Contents API — no restructuring needed (the adapter
   reads the repo as-is).
3. **App installed** on the fork (installation `146096524`);
   `connect_github_app` linked it → `list_github_repos` confirmed the fork
   reachable → course **#22** created → `set_course_git` bound it →
   `import_course_git`: **193 notes / 6 modules / 0 warnings**, and a
   re-import was a clean **no-op (idempotent, matched by `git_path`)**.
4. **Sync verified**: `sync_course_git` pushes back as **one atomic Git
   Data API commit** (~5 s for 193 files; the 0.1.174 per-file version
   timed out — fixed in 0.1.176). A note edit → sync round-trips
   byte-identically, frontmatter preserved; a no-change sync is a no-op
   (no empty commit). Lazy sync is enabled (10-min debounce).
5. **PR to the original**: `colorful-numbers/Veronica-7#1` — the
   config-only diff (one new file, additive, VitePress build untouched).

Known cosmetic follow-up: the first sync normalized YAML frontmatter in a
few files (quote style, long-line wrap, trailing newline) — semantically
lossless, one-time. Byte-faithful frontmatter would require storing the
raw block on import (see docs/TODO.md).

The bot PAT was used transiently (stored only in the session scratchpad,
outside the repo, then shredded) and never committed or logged — rotate
it now that the migration is done.
