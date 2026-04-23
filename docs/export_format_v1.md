# Notechondria local-data export format v1

The shared `.nchron` archive is a plain ZIP containing every persisted
bucket a Notechondria frontend app keeps in `_LocalAppStore`, plus any
binary attachments promoted out of draft `metadata_json`. It is the
replacement for the minimal `.env`-style config-file download.

## Layout

```
<archive>.nchron            # ZIP file with extension .nchron
├── VERSION                 # ASCII: "1"  (package format version, not app VERSION)
├── manifest.json           # required metadata (see below)
├── settings.json           # _LocalAppStore.settings bucket, verbatim
├── local_settings.json     # _LocalAppStore.local_settings bucket
├── stats.json              # _LocalAppStore.stats bucket
├── cache.json              # _LocalAppStore.cache bucket (front_page, courses, …)
├── courses.json            # _LocalAppStore.courses bucket (list of local courses)
├── drafts.json             # _LocalAppStore.drafts bucket (list of local drafts)
├── logs.json               # _LocalAppStore.logs bucket (string list)
├── planner_events.json?    # planner-app only; empty array in editor/portal exports
├── calendar_feeds.json?    # planner-app only
├── activity_week.json?     # planner-app only
├── front_page.json?        # portal-app only; empty object in editor/planner exports
└── attachments/            # present iff any draft carried queued attachments
    └── <draft-client-id>/
        └── <filename>      # raw bytes, promoted out of base64-in-metadata
```

The `?` markers are **optional**; a missing file is equivalent to an
empty JSON body (`{}` for objects, `[]` for lists). Importers must not
fail if an optional file is missing, so editor exports are legal in
planner and portal.

## `VERSION` file

- Single ASCII line, no leading/trailing whitespace, no BOM.
- Current value: `1`.
- Bumped when the layout changes incompatibly (new required file,
  schema change inside an existing file that older readers can't
  tolerate). Additions that older readers can safely ignore (extra
  optional files, extra keys inside existing objects) **do not**
  require a bump.

## `manifest.json`

```json
{
  "app": "editor" | "planner" | "portal",
  "exported_at": "2026-04-18T15:42:00Z",
  "app_version": "0.1.38",
  "package_version": "1",
  "counts": {
    "drafts": 12,
    "courses": 3,
    "logs": 80,
    "planner_events": 0,
    "calendar_feeds": 0,
    "queued_attachments": 2
  },
  "profile": {
    "username": "alice",
    "email": "alice@example.com"
  }
}
```

- `app` identifies which frontend app produced the archive. Used only
  to pick sensible defaults for optional files when importing into a
  different app.
- `exported_at` in RFC 3339 UTC.
- `app_version` mirrors `./VERSION` from the repo at export time;
  diagnostic only.
- `package_version` mirrors the `VERSION` file at the archive root.
- `counts` is an advisory summary; importers use it to show a
  confirmation dialog before replacing local state.
- `profile` carries only **read-only** fields (`username`, `email`,
  `first_name`, `last_name`, `motto`, `social_link`, `image_url`). It
  **must not** contain the auth token, API key prefix, or any secret.

## Bucket files

Each `*.json` file mirrors the in-memory shape that `_LocalAppStore`
persists today. Structure matches `shared_preferences` values 1:1 so
`jsonEncode` of the bucket is the file content.

## `attachments/` directory

When any draft's `metadata_json['queued_attachments']` list is
non-empty at export time, the exporter:

1. Walks each draft.
2. For each queued attachment, writes the base64-decoded bytes to
   `attachments/<draft-client-id>/<filename>`. The filename is
   sanitized: slashes replaced with `_`, control bytes stripped, and a
   deterministic `-<index>` suffix appended on collision within a
   draft.
3. Strips the `bytes_base64` field from the draft's queued entry and
   replaces it with a `"path": "attachments/<draft-client-id>/<safe>"`
   pointer.
4. Writes the mutated `drafts.json` with the lightweight pointers.

On import, the sequence reverses: read each draft, for every queued
entry with a `path`, read `attachments/<path>` bytes, re-encode to
base64 into `bytes_base64`, drop `path`. Drafts import cleanly even
when `attachments/` is absent — a missing file leaves the queued
entry without base64 content, which the draft sync will then drop as
empty.

## Cross-app portability

- **Editor export → Portal import**: portal treats editor as a
  subset. Extra optional buckets (planner_events, calendar_feeds,
  activity_week, front_page) missing from the archive stay at portal's
  current-session defaults.
- **Portal export → Editor import**: editor ignores portal's
  `front_page` / any planner files; everything else (settings, local
  courses, local drafts, stats, cache, logs) maps directly.
- **Planner export → Editor import**: planner-specific files are
  ignored; shared buckets map directly.
- **Editor export → Planner import**: planner-specific files default
  to empty when absent.

## Importer version gating

| `VERSION` value | This build's behavior |
|---|---|
| `""`, missing, or not parseable | Reject with `Editor.LocalStore/restore_from_import — package has no recognizable VERSION file` |
| `1` | Accept; parse all buckets. |
| `"2"` and above | Reject with `Editor.LocalStore/restore_from_import — package format version 2 ahead of this build's supported version 1` |

## Migration shim for legacy `.env`-style downloads

Builds before 0.1.38 shipped a `notechondria-<username>.env` config
file containing `api_base_url` and `api_key_prefix`. The importer
sniffs the first bytes of the chosen file:

- If it decodes as a ZIP and has `VERSION` at the root, treat as a
  v1 archive.
- Otherwise, attempt `.env` migration: parse `KEY=value` lines,
  merge recognized keys (`API_BASE_URL`, `API_KEY_PREFIX`) into
  `local_settings.json` in memory, synthesize a minimal v1 archive
  with empty buckets, and apply.

## Confirmation flow

1. User picks the file via `file_selector.openFile`.
2. Importer opens the zip, reads `VERSION` and `manifest.json`, and
   shows a `ConfirmWithDelayDialog` summarizing the counts
   (`manifest.counts`) plus the exporter's app name.
3. On confirm, the current local state is wiped (same path as
   `_clearLocalData`) and the buckets from the archive are applied.
4. After apply, `_loadInitialData` runs to refresh UI.

Every step emits log entries under
`<App>.LocalStore/{export_zip, restore_from_import}` with the
`<consequence>: <module>/<process> — <cause>` shape documented in
`docs/AGENTS.md`.
