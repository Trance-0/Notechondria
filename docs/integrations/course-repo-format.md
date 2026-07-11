# Course-repo format (adapter standard)

Notechondria binds a **course** to a **GitHub repo** so the app is a text
editor over that repo, with the **backend as source of truth** and a
lazy commit/sync back to the repo. This document is the standard for how
an existing documentation repo is mapped onto a course.

## Principle: adapt, don't restructure

The binding is an **adapter**, not a required folder layout. You point it
at an existing docs project (VitePress, Nextra, Docusaurus, GitBook, or
plain markdown) and it reads your markdown where it already lives. It
**never** moves or renames files, and on sync it **only ever writes
markdown** files that map to course notes — build config
(`.vitepress/`, `docusaurus.config.js`, …), framework code, CI
workflows, and non-markdown assets are never touched. So a bound repo
still deploys to its own site (its CI/CD is untouched) *and* renders on
Notechondria from the same files.

> **MDX** (`.mdx`) is **not supported yet** — such files are skipped and
> reported as a warning. Tracked in `docs/TODO.md`.

## Config file: `notechondria.course.yaml`

Drop this at the repo root. It is **optional** — with no config the
framework is inferred from the file tree and preset defaults apply. YAML
or JSON (YAML is a superset) both parse.

```yaml
version: 1
preset: vitepress          # vitepress | nextra | docusaurus | gitbook | custom
course:
  title: "Veronica-7"      # optional; defaults to the repo name
  slug: veronica-7         # optional; derived from title
  description: ""
content:
  root: docs               # content root (preset default)
  include: ["**/*.md"]     # globs relative to root (supports **)
  exclude: [".vitepress/**", "public/**"]
  module_depth: 1          # group modules by the Nth path segment under root
  index_names: [index.md, README.md]        # a folder's landing note
  title_from: [frontmatter, h1, filename]   # title source preference
  order_keys: [sidebar_position, order, nav_order]  # frontmatter ordering
sync:
  write: ["**/*.md"]       # what sync may overwrite (markdown only, v1)
```

Any field you omit falls back to the preset, then to the base defaults.

### Presets (defaults, overridable)

| preset | content.root | notable excludes |
| --- | --- | --- |
| `vitepress` | `docs` | `.vitepress/**`, `public/**` |
| `nextra` | `pages` | — |
| `docusaurus` | `docs` | — |
| `gitbook` | `.` | `node_modules/**`, `.gitbook/**` |
| `custom` | `.` | — |

Every preset also excludes `**/node_modules/**` and `.git/**`, uses
`module_depth: 1`, and the title/order defaults above.

## How a repo becomes a course

1. **Modules** — each markdown file's module is the `module_depth`-th
   path segment under `content.root` (e.g. `docs/cv/...` → module `cv`).
   Files directly under the root join a default module named after the
   course.
2. **Titles** — first available of: frontmatter `title`, the first `# H1`,
   or a humanized filename. An `index.md` / `README.md` takes its title
   from its folder name and becomes the module's landing note (and names
   the module).
3. **Order** — notes sort by the first present `order_keys` frontmatter
   value (e.g. `sidebar_position`), index note first, then path;
   modules sort by their smallest note order.
4. **Opt-out** — a note with frontmatter `notechondria_ignore: true` (or
   `draft: true`) is skipped.

## Sync & auth (summary)

- **Auth**: pushes use the course owner's **GitHub App installation**
  (the same App as the profile backup). The Nesbitt-bot token is only
  used to create the canonical template repo and publish this standard.
- **Scheduler**: **lazy-on-request** — no worker/cron. Pending courses
  (idle past their `git_sync_timeout_minutes`, default 5) are flushed
  opportunistically during normal API traffic, guarded by a row lock so
  concurrent requests can't double-push. Because the backend is the
  source of truth, the repo simply lags until the next activity.
- **Overwrite policy**: our data is the source; on sync we overwrite the
  mapped markdown **after permission**, and never other files.

The reference implementation lives in
[`backend/courses/course_repo.py`](../../backend/courses/course_repo.py);
the canonical example repo is
`Nesbitt-bot/notechondria-course-template`.
