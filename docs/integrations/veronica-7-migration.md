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

## Remaining steps (need production + owner confirmation)

These are **not** done — each needs infrastructure this agent's
environment can't reach, and step 4 is an outward-facing PR to a
third-party repo:

1. **Fork** `colorful-numbers/Veronica-7` → `Nesbitt-bot` (bot PAT).
   Reversible (a fork on the bot account, deletable).
2. **Clone the fork** to a temp workspace, add the `notechondria.course.yaml`
   above, push to the fork. Stays within the bot's own fork.
3. **Bind + import** the fork as a new course — needs the *production*
   backend with the GitHub Data Sync **App installed on the fork**
   (`POST courses/<id>/git/import/`). Then edits sync back via the
   0.1.174 lazy engine (`POST courses/<id>/git/sync/`).
4. **PR the config to the original** `colorful-numbers/Veronica-7` so the
   upstream repo becomes Notechondria-bindable. **Outward-facing to a
   third party — confirm before opening.**

Steps 1–2 use the bot PAT (must never be echoed to logs or committed);
step 3 depends on the App installation; step 4 needs owner sign-off.
