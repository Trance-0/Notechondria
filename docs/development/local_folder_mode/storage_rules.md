# Local folder storage mode: storage rules

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(sections 3.4 to 3.8). Same conventions: repo-root-relative paths,
`file:line` at HEAD `48988a20` (VERSION 0.1.199), and section numbers that
refer to the main document unless they start with 3.4 to 3.8. The folder
tree and file formats are in main 3.1 and 3.2. The locking rules R1 to R5
that every operation below runs under are in
[`security_and_tabs.md`](security_and_tabs.md) (section 6.2).

## 3.4 Writes

- **Single file.** `createWritable()`, then `write()`, then `close()`.
  The browser writes to a temporary file and the target changes only when
  `close()` succeeds; `abort()` discards (MDN `createWritable`). A crash
  mid-write leaves the old file. `mode: 'exclusive'` is passed when
  available (Chrome 121+) as a second guard behind the folder lock.
  `package:web` 1.1.1 has no `mode` member on
  `FileSystemCreateWritableOptions` (only `keepExistingData`), so the
  option is set through the hand-written binding (9.2).
- **Swap files.** Chrome places the temporary file next to the target,
  named `<name>.crswap` (U17). It disappears on `close()` or `abort()`;
  a tab that crashes mid-write can leave one behind. The scanner (3.8),
  the index, the folder counts in the status card (F48), the `.nchron` export, and the
  GitHub push ignore every `*.crswap` entry. The app never deletes one,
  because Chrome owns it.
- **Why not temp file plus rename.** `FileSystemHandle.move()` exists only
  on file handles in Chrome and its overwrite behavior is unverified (U5).
  `createWritable` already gives replace-on-close, so a separate rename
  adds nothing.
- MDN lists an `AbortError` from implementation-defined malware and
  safe-browsing checks among the `createWritable` exceptions. Attachment
  uploads surface it as
  "Attachment not saved: Shared.LocalFolder.Backend/attachments — the
  browser rejected the file on save (AbortError from a safe-browsing
  check)."

### 3.4.1 Multi-file operations and the journal

Multi-file operations use a write-ahead journal. They are: create a note
(`.md`, `.meta.json`, manifest counter), delete, restore, and empty trash
(3.5), delete a course, identity reassignment (3.7), and any write to a
shared JSON file together with another file. Each one runs inside a
single exclusive hold of the folder lock (6.2 R1):

1. Re-read from disk every file the operation rewrites, `manifest.json`
   included (6.2 R2). The in-memory index is never the base of a write.
2. Write `.notechondria/journal/<op-id>.json`:
   `{"schema_version": 1, "op_id", "app", "created_at", "writes": [{"path", "text", "expect"}], "removals": [{"path", "expect"}]}`.
   `writes` carries the full new text of every text file the operation
   changes, note bodies included. `expect` is present only for note
   bodies (`notes/*.md`, `trash/notes/*.md`): the `size` and
   `lastModified` the operation read in step 1, used by roll-forward to
   detect a later external edit. Attachment bytes are never journaled:
   they are written to their final path before the journal record, so
   nothing references bytes that do not exist yet. `<op-id>` is
   `<UTC milliseconds, 13 digits>-<4-digit per-tab sequence>-<8 random hex>`,
   so lexical order is creation order.
3. Apply `writes` in a fixed order: note bodies, then sidecars, then the
   shared index files (`recycle_bin.json`, `planner/*.json`,
   `attachments.json`, `history/<hex>/index.json`), then `manifest.json`.
4. Check that every write target exists with the journaled length. Only
   then apply `removals`, files first and directories
   (`removeEntry(name, {recursive: true})`) last. Removals always come
   last, so an interrupted move leaves the source in place and never loses
   the note.
5. Delete the journal record. The lock is released only after this step.

**Roll-forward.** A leftover record is replayed from step 3. Rewriting
identical text is a no-op, and removing a path that is already gone
(`NotFoundError`) is ignored, so a replay is idempotent and can itself be
interrupted and replayed. Rules:

- Roll-forward needs the exclusive lock. Once the lock is held it
  re-lists `.notechondria/journal/` and skips any record that no longer
  exists. A record that another tab is still applying never reaches
  roll-forward, because that tab holds the lock until step 5. A record is
  left over only when its tab closed or crashed mid-operation, which
  releases the lock (U18; a tab that stays alive holds the lock, so other
  tabs wait at most 5 s and fail cleanly, 6.2 R5).
- Leftover records are replayed one at a time in `op-id` order, each to
  completion before the next.
- **External edits during replay.** A record left by a crash can be
  replayed long after the crash, and the user may have edited a note in
  another editor in between. Before the replay rewrites or removes a note
  body that carries `expect`, it stats the file:
  - size and `lastModified` equal `expect`, or the text equals the
    journaled text: the replay proceeds;
  - anything else: the file was edited after the crash. The replay first
    saves its current text as an `external_edit` snapshot (3.8), in the
    same exclusive hold, with the record's `op_id` in the history index
    entry, and then proceeds. A second replay of the same record finds
    that entry and does not snapshot again.

  `expect` lives in the record rather than in the sidecar, because a
  crash after step 3's sidecar writes leaves the new sidecar on disk. The
  same check covers removals, so a delete or trash move interrupted by a
  crash never discards an edit made later.
- It runs in the startup step (2.9), when a GET handler or a scan page
  finds a non-empty journal directory (6.2 R3), and before any write.
- If roll-forward fails (for example `NotAllowedError` after a
  revocation), readers skip every path the pending record names, and the
  status card shows "Folder change not finished: Shared.LocalFolder/journal
  — <op-id> from <app> is incomplete (<cause>); the notes it touches are
  hidden until Reconnect or Rescan finishes it."
- Operations that could hold the lock for long are split into separately
  journaled chunks (6.2 R4).

**Tests** (8.1, `folder_journal_test.dart`, over `MemoryFolderFs`): for
each multi-file operation, inject a crash after step 2, after every single
write of step 3, after step 4, and in the middle of a replay. A fresh
transport over the same `MemoryFolderFs` must then show either the old
state (crash before the record was complete) or the complete new state,
never a mix. Two transports that both find one leftover record roll it
forward once: the second re-checks after taking the lock and skips it.
Three leftover records apply in `op-id` order. A crash after step 2 of a
note PATCH, followed by an external edit of the `.md` (the fake's
external-edit injection), replays to the journaled text with the
external text kept as one `external_edit` snapshot; a second replay adds
none. The same holds for a delete interrupted before its removals.

## 3.5 Delete and trash semantics (match the backend)

| Operation | Backend behavior | Folder behavior |
|---|---|---|
| Delete note | Makes the note's live comments private (`backend/notes/api.py:1598-1599`), sets `deleted_at`, forces `is_public = False`, upserts a `RecycleBinEntry` (`:1600-1603`) | One journaled operation: write `trash/notes/<stem>.md` and its sidecar with `deleted_at` and `is_public: false`; set `is_public: false` in every live comment note whose sidecar `source_note_uuid` names this note; add the pointer to `recycle_bin.json`; then remove `notes/<stem>.md` and its sidecar |
| Restore note | Clears `deleted_at` and removes the entry; `is_public` stays false (`backend/notes/api.py:1941-1944`) | Move back to `notes/` (journaled, removal last), drop the pointer, keep `is_public: false`. Comment notes stay private, as in the backend |
| Empty trash | Hard-deletes every trashed note and entry, no age filter (`backend/notes/api.py:1948-1965`). The delete cascades to `NoteVersion`, `NoteActivitySession`, and `NoteAttachment` (`backend/notes/models.py:178-182, 213-216, 335-339`) and sets `source_note` to null on comment notes (`models.py:86-91`, `SET_NULL`) | Per trashed note, one journaled operation: remove the trashed `.md` and sidecar, `history/<hex>/`, `assets/notes/<hex>/` (attachment files, `attachments.json`, cover), and the note's records in `planner/sessions.json`; set `source_note_uuid: null` in the sidecars of its comment notes; drop its pointer from `recycle_bin.json`. A large trash is chunked (6.2 R4). `planner/heatmap.json` holds per-day counts with no note reference, so it is unchanged |
| Retention | None; no purge constant exists in the backend | None. (The 30-day TTL in `frontend/editor_app/lib/core/local_store.dart:139` belongs to the separate browser-local recycle bin and is unchanged) |
| Create with an existing `client_draft_id` | Upserts and undeletes (`backend/notes/api.py:1399-1420`) | Same; this makes migration pushes idempotent |
| Delete course | Hard delete. Notes, planner events, and calendar feeds of the course fall to `course_id = null` through `SET_NULL` (`Note.course_id`, `backend/notes/models.py:28-31`; `PlannerEvent.course_id` and `CalendarFeed.course_id`, `backend/planner/models.py:16-19`, `:111-114`; delete at `backend/notes/api.py:933-940`). Trashed notes are included, since a trashed note is a row with `deleted_at` set (`models.py:76`) | In journaled chunks of at most 50 file writes: set `course_slug: null` in every note that names the course under `notes/` and `trash/notes/`, and `course_id: null` in every record of `planner/events.json` and `planner/feeds.json` that names it; the last chunk removes `courses/<slug>.json` (6.2 R4). `planner/sessions.json` records reference notes, and the sessions handler derives `course_id` from the note when it answers, as `note_session_payload` does (`backend/notes/services.py:367-374`), so sessions need no change. `planner/heatmap.json` has no course reference |

After empty trash, nothing of a permanently deleted note stays in the
folder: no body, no snapshot, no attachment, and no session. Copies may
remain outside the folder's control, and the confirmation says so:
"Permanent delete: Shared.LocalFolder.Backend/notes — <n> notes with
their history and attachments will be removed from '<name>'. Copies in
your OS trash, a sync service's file history, or earlier .nchron exports
are not affected."

Known difference: the backend's heatmap rows reference their note
(`HeatmapActivity.note_id`, `CASCADE`, `backend/planner/models.py:81-84`),
and `build_heatmap_payload` counts those rows (`backend/notes/services.py:112-125`).
So emptying the trash lowers the backend's past heatmap counts, while the
folder's per-day counts in `planner/heatmap.json` stay as they were.

## 3.6 Attachments and media

- Upload routes store bytes under `assets/notes/<hex>/` and return the same
  JSON shape as the backend, with `url` set to
  `nc-folder:///assets/notes/<hex>/attachments/<name>`.
- The URL must differ from `local://`. The editor's promotion flow replaces
  `local://` URLs with the returned `url` and then deletes the
  `local://` blob (`frontend/editor_app/lib/core/note_crud.dart:240-275`).
  Returning a `local://` URL would delete the file just written.
- A shared `folderAwareImageProvider(url)` returns an image provider that
  reads the bytes through the controller for `nc-folder:` and a network
  image otherwise. It replaces `Image.network` where backend media URLs
  are rendered: editor `core/helpers.dart:309`,
  `modules/settings_build.dart:287`, `components/avatar.dart:41`; planner
  `core/helpers.dart:287`, `components/avatar.dart:31`; portal
  `core/helpers.dart:331`, `modules/settings_build.dart:493`,
  `components/avatar.dart:43`; shared `components/note_cover_image.dart:53`.
  The existing `local://` builders stay
  (`frontend/editor_app/lib/core/helpers.dart:306-312`).
- **Planner and portal note viewers.** Both build `MarkdownBody` without
  `sizedImageBuilder` (`frontend/planner_app/lib/components/note_viewer.dart:116-121`,
  `frontend/portal_app/lib/components/note_viewer.dart:122-137`).
  flutter_markdown 0.7.7+1's default web builder handles only http(s),
  data, and resource URIs; for any other scheme it calls
  `Image.network(p.join(p.current, uri))` (`lib/src/_functions_web.dart:21-77`
  in the 0.7.7+1 archive), so an `nc-folder:` image would show the error
  widget. Both viewers pass `sizedImageBuilder: _localAttachmentImageBuilder`,
  the builder their note editors already use (planner
  `modules/learner_note_editor.dart:531`, portal `:534`). That builder
  reaches `folderAwareImageProvider` through the replaced lines in
  planner `core/helpers.dart:287` and portal `core/helpers.dart:331`.
  One line per viewer; smoke check in 8.5.
- **Not changed: the portal startup image**
  (`frontend/portal_app/lib/components/custom_splash_overlay.dart:71`). It
  is a device preference stored as `local://app-splash/startup-image` or a
  remote URL (`frontend/portal_app/lib/modules/settings_pages.dart:453-498`),
  never an `nc-folder:` URL, and it renders before any folder is open
  (F63).
- Object URLs (`blob:`) were considered instead; whether Flutter web's
  `Image.network` loads them is **unverified** (U1), so the scheme approach
  is the default.
- `LocalAttachmentStore` (IndexedDB `notechondria_attachments`,
  `frontend/notechondria_shared/lib/src/utils/local_attachment_store_web.dart:8-10`)
  keeps serving browser-local drafts. In folder mode new uploads go to the
  folder, and queued `local://` attachments are promoted into the folder by
  the existing promotion flow (section 7.1).
- **Promotion failure in folder mode.** The promotion flow drops a draft's
  attachment queue whether or not each upload succeeded
  (`frontend/editor_app/lib/core/note_crud.dart:266-268`) and frees only
  the blobs it promoted (`:270`). So a failed promotion leaves a
  `local://` link in the folder note and the bytes in this browser's
  `LocalAttachmentStore`. The link keeps rendering in this browser through
  the existing builder, but not in another browser or in a file manager.
  The folder backend logs "Attachment not copied into the folder:
  Shared.LocalFolder.Backend/attachments — '<file>' stayed in this
  browser's storage (<cause>); the note keeps its local:// link." The
  status card counts folder notes whose body still contains `local://` and
  offers "Copy browser attachments into the folder". That action uploads
  each blob it finds in `LocalAttachmentStore` and rewrites the link; a
  link whose blob is gone stays as is and is listed by file name.
- Size cap: the browser-local store caps attachments at 50 MiB
  (`frontend/notechondria_shared/lib/src/utils/local_attachment_store.dart:219`).
  The folder backend applies the backend's limits once they are recorded
  in the fixtures (section 8.4).

## 3.7 IDs

- The apps treat negative IDs as browser-local records
  (`frontend/editor_app/lib/core/note_loading.dart:36-42`,
  `frontend/editor_app/lib/core/note_crud.dart:90`). The folder backend
  therefore issues positive integers per kind from
  `manifest.json.id_counters`. Each counter holds the last ID issued (0
  before the first). Allocation re-reads `manifest.json` from disk inside
  the exclusive hold of the operation that writes the new record (6.2 R2),
  never from a cached copy.
- Counters never fall behind the folder. Every full scan and every adopt
  raises each counter to the largest ID of its kind seen in sidecars,
  course files, history indexes, and `planner/*.json`, if the counter is
  lower (one journaled write).
- Note UUIDs are version-4 UUIDs from `Random.secure()`. The server never
  adopts a client UUID: `Note.uuid` is `UUIDField(default=uuid.uuid4,
  unique=True, editable=False)` (`backend/notes/models.py:35`). A later move
  to the cloud creates new server IDs and UUIDs, so local values cannot
  collide with server ones.
- **Duplicate identities.** Copying a note in a file manager produces a
  second `.md` with the same frontmatter `uuid`, sometimes with a copied
  sidecar that repeats the `id`. The scanner keeps the identity on one
  file, chosen in this order:
  1. the file whose own sidecar (`<stem>.meta.json`) carries that UUID;
  2. the file whose `<stem>` is the UUID hex;
  3. the lexicographically first path.

  Every other claimant gets a new UUID, a new note ID, a new sidecar, and
  a rewritten frontmatter `uuid`, in one journaled operation. The scanner
  logs "Note identity reassigned: Shared.LocalFolder/scan — 'notes/<file>'
  claimed uuid <old>, which 'notes/<keeper>' already uses; it now has uuid
  <new>." The same rule applies to two course files with one `id` or one
  `client_course_id`, and to duplicate `id`s inside a `planner/*.json`
  file.
- **Adopting a GitHub data-sync clone** (Phase 4). Its sidecars and course
  files carry the server's `id`s
  (`backend/creators/services/github_sync.py:167`, `:226`). They are unique
  per kind because they come from one account, so adopt keeps them and
  raises every counter above the largest one seen. A collision with a
  record already in the folder is resolved by the duplicate rule above.
  `client_draft_id` and `client_course_id` are kept.
- **Folder identity.** `folder_id` names the lock
  (`notechondria.local_folder.<folder_id>`) and the remembered-handle
  record, so two folders must not share it.
  - A `.nchron` restore always writes a new `folder_id` (3.3).
  - A folder copied in a file manager keeps the original `manifest.json`.
    When a picked folder's `folder_id` matches a remembered handle, the
    app compares the two with `FileSystemHandle.isSameEntry()` (bound in
    `package:web` 1.1.1; Baseline since March 2023, MDN). It needs no
    permission: the File System standard compares the handles' locators
    (section 2.2.1). Same entry: it continues. Different entry: the app
    has to learn whether the remembered folder still exists, and reading
    it needs a grant on that second handle:
    - `queryPermission({mode: 'read'})` on the remembered handle is
      `granted` (common while another tab of the origin holds the grant,
      or after "Allow on every visit"): the app reads its
      `manifest.json`. Readable with the same `folder_id`: the picked
      folder is a copy, and the app asks "Folder looks like a copy:
      Shared.LocalFolder/pick — '<name>' has the same folder_id as
      '<other>'. Give it its own identity?" Yes writes a new `folder_id`
      (journaled). `NotFoundError`: the folder was moved or renamed, it
      continues without migration (6.3), and the remembered record now
      holds the picked handle.
    - Otherwise the app does not call `requestPermission` from the
      picker's click, because each browser call that needs activation is
      the first call of its own click handler (1.3). It asks instead:
      "Folder may be a
      copy: Shared.LocalFolder/pick — '<name>' has the same folder_id as
      '<other>', which this browser remembers, and checking '<other>'
      needs access to it." The buttons are "Check '<other>'", whose
      `onPressed` calls `requestPermission({mode: 'read'})` on the
      remembered handle first and then reads it as above; "Give it its
      own identity"; and "It is the same folder, moved", which continues
      and replaces the remembered record.
  - In session-only mode (the default on `*.github.io`, 6.1) no handle is
    remembered, so a copy is only detected against a handle held in the
    same tab. Two copies open at once in different tabs would share a
    lock name and change channel. That only serializes their writes and
    triggers extra refreshes; it cannot corrupt either folder, because
    every write re-reads its own folder (6.2 R2).
- Cross-system identity uses `client_draft_id = fld_<uuid-hex>` (36
  characters) and `client_course_id = fld_<course-uuid-hex>`. Both fit the
  backend's `max_length=64` (`backend/notes/api.py:550,566`), and the
  backend upserts on them (`:766-771`, `:1399-1420`), so pushing the same
  folder into an account twice does not duplicate records. Planner events
  and feeds pushed from browser-local storage carry `client_local_id`
  (7.1), a folder-only key.
- A migration to the cloud writes `.notechondria/cloud_map.json` (local
  UUID to server UUID) so deep links can be rewritten.

## 3.8 Index, external edits, and rescans

- On connect, the controller lists `notes/`, `courses/`, `planner/`,
  `trash/`, and `assets/`, and reads only files whose size or
  `lastModified` differ from `.notechondria/index.json`. The listing runs
  in pages under the shared lock (6.2 R4) and skips `*.crswap` (3.4).
  Scan cost for large folders is **unverified** (U6); the scan reports
  progress at least every 2 seconds. Startup uses the stored index and
  verifies it after the startup pass (2.9).
- Before overwriting a note, the backend compares the file's current
  `lastModified` and size with the sidecar's `md_last_modified` and
  `md_size`. If they differ, the external version is first saved as a
  history snapshot with reason `external_edit`, and the existing
  `NoteConflictDiffView`
  (`frontend/notechondria_shared/lib/src/components/note_conflict_diff.dart:5-11`)
  can show the difference.
- Concurrent edits from two tabs: the transport remembers, per note, the
  `lastModified` of the body it last served to its own tab. A PATCH that
  finds a different `lastModified` on disk first saves the disk version
  as a snapshot with reason `concurrent_edit`, then writes.
- Retention bounds both kinds of snapshot without touching the ones the
  backend would keep. The folder backend ports `prune_recent_versions`,
  which keeps the 12 newest versions of a note
  (`backend/notes/services.py:339-344`), and runs it per pool:
  - every reason except the two below keeps the backend rule, the 12
    newest of these. The apps request `manual`, `before_restore`, and
    autosave reasons today (`autosave_1m`, `autosave_10m`, `autosave_1h`;
    editor `modules/note_editor.dart:438-446`, planner
    `modules/learner_note_editor.dart:268`; labels at
    `services.py:356-363`);
  - the folder-only reasons `external_edit` and `concurrent_edit` form a
    second pool with its own 12-version cap.

  Pruning in one pool never removes a version from the other. Two tabs
  saving one note in turn can therefore push out older `concurrent_edit`
  snapshots, but never a manual or autosave snapshot; within the first
  pool, autosaves can push out manual snapshots exactly as they do in the
  backend. The backend itself snapshots only on an explicit snapshot
  request and before a version restore (`backend/notes/api.py:1899`,
  `:1918`). A note holds at most 24 versions in the folder. An
  overwritten external or concurrent edit stays recoverable until 12
  newer folder-only snapshots of that note exist. The history list shows
  both pools in one list, newest first.
- New `.md` files without a sidecar are adopted (with the duplicate rule
  in 3.7). Files that disappear are dropped from the index and logged at
  INFO: "Note dropped from index: Shared.LocalFolder/scan —
  'notes/<file>' no longer exists on disk."
