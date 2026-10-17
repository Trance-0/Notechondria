# Local folder storage mode: security and multi-tab behavior

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(section 6). Same conventions: repo-root-relative paths, `file:line` at
HEAD `48988a20` (VERSION 0.1.199), and section numbers that refer to the
main document unless they start with 6. The journal these rules protect
is in [`storage_rules.md`](storage_rules.md) (3.4.1).

## 6.1 The shared Pages origin

- An origin is scheme, host, and port; IndexedDB and Web Storage are
  separated by origin (MDN same-origin policy). GitHub serves project sites
  at `https://<owner>.github.io/<repository>` (GitHub Pages docs), so all
  Trance-0 project sites without a custom domain share one origin.
- Checked 2026-10-17: the GitHub API lists Pages enabled on `circtime`,
  `GeometryOfMusic`, `MTA-strategy-optimizer`, `Notechondria`,
  `NoteNextra`, `Trance-0.github.io`, and `upptime`. Requests to
  `https://trance-0.github.io/{circtime,GeometryOfMusic,MTA-strategy-optimizer}/`
  returned 200 (same origin as Notechondria); `NoteNextra` and `upptime`
  redirect to their own custom domains. The Notechondria docs subtree is
  also on this origin.
- Assessment: yes, another page on the origin can read a stored handle.
  It can open the same IndexedDB database, take the handle, and call
  `queryPermission`. A grant belongs to the origin (the "app" in Chrome's
  wording), not to a page path. If a Notechondria tab still holds it
  (access lasts until the last tab of the origin closes) or the user chose
  "Allow on every visit", the call returns `granted` without a prompt, and
  the page can read, change, or delete the folder. Not storing the handle
  is not a full fix: a same-origin page can open or frame a Notechondria
  app and reach its window and prototypes while it runs. Nothing inside
  the origin can separate same-origin scripts.
- Mitigations:
  1. On `*.github.io` the handle is kept for the session only by default.
     "Remember this folder on this browser" is an unchecked opt-in (Q3).
  2. Before the first connect on that origin, a one-time notice, shown as
     its own dialog whose "Choose folder" button opens the picker (1.3):
     "Folder access is shared with this web address: Shared.LocalFolder/pick
     — https://trance-0.github.io also hosts other projects, and any page
     there could use a folder you grant. Pick a dedicated, empty folder, or
     use the local preview or desktop build."
  3. The picker flow recommends an empty folder and refuses a non-empty
     folder without `manifest.json` unless the user confirms a count of its
     entries, so the grant does not cover something like Documents.
  4. Recommend an origin without other projects: the loopback preview at
     `http://127.0.0.1:9068` (a secure context, MDN; `docs/deployment/local_preview.md`,
     which needs a host with at least 16 GB RAM), a custom domain for the
     Notechondria Pages site (Q4), or an installed app, whose grant Chrome
     persists automatically (installability of the three apps is
     **unverified**, U7). The preview and the Docker self-host still serve
     uploaded media on the app origin; see the residual risk below.
  5. No cross-tab handle handoff in v1, on any origin (6.2). No tab ever
     sends a folder handle to another tab or answers a request for one.
- Residual risk on the Pages origin: while a folder is granted, a
  compromised or malicious page on any same-origin Trance-0 Pages project
  can read, modify, or delete that folder. It can do so by opening the
  remembered handle in IndexedDB when "Remember this folder" is on, or by
  opening or framing a running Notechondria app and reaching its objects.
  v1 has no `BroadcastChannel` handle handoff (6.2), so such a page cannot
  simply post a request and receive a live, granted handle: the answering
  tab could not tell a Notechondria tab from any other same-origin script.
  The cost is that in session-only mode each app asks for the folder once
  per page load (2.9; the picker's `id` option reopens it at the last
  location). The same pages can already read the cloud session token the
  editor and portal keep in localStorage
  (`frontend/editor_app/lib/core/local_store.dart:275-285`).
- Residual risk on the loopback preview and the Docker self-host: these
  origins host no other project, but they serve backend uploads on the
  app origin. The preview "forwards /api/, /media/, and /static/ to a
  remote Notechondria backend" on `127.0.0.1:9068`
  (`scripts/local_remote_deploy.sh:2-4`), and the self-host gateway
  proxies `/media/` next to `/editor/`, `/planner/`, and `/portal/`
  (`deployment/docker/nginx/default.conf:5-43`). Backend `/media/` serves
  local files through `django.views.static.serve` or proxies R2 with the
  stored `Content-Type` (`backend/notechondria/api_views.py:508-532`;
  backend nginx uses `alias` with `mime.types`,
  `backend/nginx/nginx.conf:55-57`), and attachments accept any type up
  to 20 MB (`backend/notes/api.py:2456`, `:2492`). An uploaded `.html` or
  `.svg`, opened from a shared note's link, therefore runs as a
  same-origin page there, with the same reach as another Pages project
  has on `*.github.io`: the remembered handle in IndexedDB, and any app
  window it opens or frames. Only an origin that serves no user uploads
  as active content removes this risk (Q19).

## 6.2 One folder for three apps, and concurrent writes

- One folder serves all three apps (Q5). Which apps use it, and how that
  interacts with per-app cloud sessions, is in 2.10. A remembered handle
  lives in IndexedDB database `notechondria_local_folder`, keyed by
  `folder_id`.
- **No handle handoff in v1.** Each app tab obtains the handle by itself.
  With "Remember this folder" on, it restores the handle from IndexedDB,
  and because a grant belongs to the origin, `queryPermission` usually
  returns `granted` without a prompt while another tab of the origin
  holds it (6.1). In session-only mode each app tab chooses the folder
  once per page load (2.9). An earlier revision answered a
  `BroadcastChannel('notechondria.local_folder')` handle request on
  dedicated origins, on the claim that such an origin serves only
  Notechondria apps. That is false for both examples it named: the
  loopback preview and the Docker self-host serve uploaded `/media/`
  files on the app origin (6.1). The answering tab cannot tell a
  Notechondria tab from such a page, and posting a handle relies on
  handles being structured-cloneable over `BroadcastChannel`, which was
  never verified (U13). A future handoff would need a visible
  confirmation in the answering tab ("Share folder '<name>' with the
  planner tab?") on every origin.

Lock rules. The lock is `navigator.locks.request('notechondria.local_folder.<folder_id>', ...)`.
Locks are origin-scoped and queue across tabs (MDN Web Locks). They are
not re-entrant, so the transport takes the lock once at the request
boundary, and handlers inside a hold call `FolderFs` directly. A hold
lasts exactly as long as the promise the grant callback returns, so that
callback returns the operation's promise and is bound with the
non-guarded zone wrapper (2.5); a callback that returned nothing would
release the lock before the operation's first `await`.

- **R1 Modes.** Exclusive: every non-GET request, journal roll-forward,
  `.notechondria/index.json` writes, counter raises, and identity
  reassignment (3.7). Shared (`mode: 'shared'`): GET handlers and each
  listing page of a scan. Readers therefore never see a half-applied
  operation. A writer waits for the current readers, and readers wait for
  the current writer.
- **R2 Read-modify-write from disk.** Every mutating handler re-reads from
  disk, inside its exclusive hold, each file it rewrites: the note's `.md`
  and sidecar, `manifest.json` (ID counters), `recycle_bin.json`,
  `planner/events.json`, `planner/sessions.json`, `planner/feeds.json`,
  `planner/heatmap.json`, the note's `attachments.json`, and
  `history/<hex>/index.json`. The in-memory index is a read cache for GET
  handlers and never the base of a write. A late or lost change message
  can therefore delay another tab's refresh, but it cannot lose an update.
- **R3 Journals before reads.** A GET handler or scan page that finds a
  non-empty `.notechondria/journal/` releases its shared hold, takes the
  exclusive lock, re-lists the journal, rolls forward what is still there
  (3.4.1), takes the shared lock again, and then serves. If roll-forward
  fails, the reader skips every path the pending record names.
- **R4 Bounded holds.** One hold targets at most 2 s
  (`kFolderLockHoldTarget`) and 50 file writes. An operation that can
  exceed that runs as a sequence of separately locked and journaled
  chunks, and every state between chunks is valid:
  - Delete course: journaled chunks of at most 50 file writes. Each note that
    names the course, under `notes/` and `trash/notes/`, gets
    `course_slug: null`; `planner/events.json` and `planner/feeds.json`
    each get `course_id: null` on every record that names the course, one
    file per chunk (3.5). The last chunk removes `courses/<slug>.json`.
    If interrupted, the course still exists and repeating the delete
    continues the work.
  - Empty trash: one chunk per trashed note (its history and assets are
    removed with it), batched while the hold stays under 2 s.
  - Archive import and adopt: chunks of 50 files.
    `.notechondria/import.json` records the archive name and progress at
    the start, and `manifest.json` is written in the last chunk. An
    interrupted import is a folder with `import.json` and no manifest,
    and connecting to it offers "Restart import from '<archive>'"; the
    writes are idempotent overwrites.
  - Scans: listing pages of up to 500 entries per shared hold. Writers
    may run between pages. After the last page the scanner re-checks,
    under one more shared hold, every UUID it saw at two paths and every
    path named by a change message received during the scan, and drops
    stale entries. A scan during a trash move therefore never reports the
    note in both `notes/` and `trash/notes/`.

  While a chunked operation runs, the status card shows "Folder busy:
  Shared.LocalFolder/<process> — <operation> (<k> of <n>)." Other tabs'
  requests run between chunks.
- **R5 Bounded waits.** A request waits at most 5 s for the lock
  (`kFolderLockWait`, an `AbortSignal.timeout`), below the 10 s startup
  budget, and never past its own deadline, which runs from request start
  and covers every lock wait of the request, including the two re-locks
  of R3 (2.9). A write that times out returns 503 with "Change not saved:
  Shared.LocalFolder/lock — another tab held the folder lock for more than
  5 s." All three apps keep such a failed save as a browser-local draft
  (2.8). A read that times out returns 503 with "Folder data not loaded:
  Shared.LocalFolder/lock — another tab held the folder lock for more than
  5 s."
- `createWritable({mode: 'exclusive'})` is a second guard; the default
  `siloed` mode would let the last writer silently win (MDN).
- **Change channel.** After each operation or chunk, the tab posts
  `{folder_id, op_id, op, paths}` on
  `BroadcastChannel('notechondria.local_folder.changes')`. Other tabs drop
  those index entries and, when the change touches what they show, rerun
  their existing load path (for example `_loadInitialData`), debounced to
  one refresh per second. The listener is bound to the controller's zone
  (2.5), so its refreshes never run inside a startup budget. The same
  channel carries the connect, disconnect, and switch messages of 2.9
  and 2.10; those apply to every tab, whatever folder it has open.
- Two tabs editing one note: last writer wins, as in the backend, which
  has no optimistic-concurrency check on note PATCH. The earlier version
  survives as a `concurrent_edit` snapshot (3.8), within the 12-version
  bound.

**Tests** (8.1, `concurrency_test.dart`): two transports over one
`MemoryFolderFs`, sharing one in-process lock manager that implements the
shared and exclusive modes, with the change channel delayed or dropped:

- concurrent note creates get distinct IDs, and `manifest.json` ends with
  the higher counter;
- concurrent event creates both land in `planner/events.json`;
- concurrent PATCHes of one note leave one version in the file and the
  other as a `concurrent_edit` snapshot;
- a course delete over 120 notes interleaves with a note save from the
  other transport, and the save succeeds within 5 s;
- a scan during a trash move never reports the note twice;
- both transports finding one leftover journal roll it forward once
  (3.4.1).

## 6.3 Permission revoked, folder moved or deleted

| Situation | Detection | Behavior and message |
|---|---|---|
| Startup, handle restored, grant still live | `queryPermission({mode: 'readwrite'})` is `granted` | Load the index and continue (2.9) |
| Startup, handle restored, grant expired or auto-revoked | `queryPermission` is `prompt` | `needsPermission`; the startup pass completes with the folder pending (2.9 step 4a). The reconnect view shows "Reconnect '<name>'", whose `onPressed` calls `requestPermission` first (Chrome 122+ may offer "Allow on every visit"), and "Use browser-local mode instead", which disconnects (2.10). After more than three denials or dismissals Chrome stops showing the three-way prompt and shows the regular one (Chrome persistent-permissions post) |
| Startup, no handle: session-only mode after a reload or in a newly opened tab, or a missing IndexedDB record | Nothing to query | `needsPick` (2.9 step 4b). The view shows "Choose '<name>' again", whose `onPressed` calls `showDirectoryPicker({id: 'notechondria-folder', mode: 'readwrite'})` first and only then checks the picked folder's `folder_id`; a different `folder_id` or a folder without `manifest.json` is refused, with "Switch to this folder" for the former (2.9). Also "Use browser-local mode instead" |
| Startup, denied | `queryPermission` is `denied` | `error`: "Folder not opened: Shared.LocalFolder/permission — the browser denies access to '<name>'. Choose the folder again or switch to browser-local mode." The view offers "Choose '<name>' again" (the no-handle flow) and "Use browser-local mode instead" |
| Revoked mid-session | Any call throws `NotAllowedError`, or the focus check's `queryPermission` returns `prompt` | This is a routine path. Besides "Remove access" in the address bar, Chrome revokes access by itself when a tab has been in the background for a while (1.4). The controller enters `needsPermission`; the transport answers 503 with the `needsPermission` message (2.8), and nothing reaches the network. A banner offers Reconnect. All three apps keep the failed save as a browser-local draft (editor `core/note_crud.dart:136-160`, planner `core/note_crud.dart:139-158`, portal `core/note_crud.dart:135-150`), and Reconnect pushes it (2.9). A grant made with "Allow on every visit" persists until the user revokes it |
| Folder moved, renamed, or deleted | `NotFoundError` on the root | "Folder not found: Shared.LocalFolder/restore_handle — '<name>' was moved, renamed, or deleted (NotFoundError). Choose the folder again or switch to browser-local mode." The view offers "Choose '<name>' again"; a re-picked folder whose `folder_id` matches continues without migration, after the copy check in 3.7 |

These use 503, never 401 or 403, for the reason in 2.5. Mid-session the
handle is still in page memory, so Reconnect works there in session-only
mode too; only a new page load loses it.

## 6.4 Rescans and external edits

Rescan on connect (for startup, the verification after the pass, 2.9), on
window focus and `visibilitychange` (debounced to one rescan per 5 s per
tab), through a recursive `FileSystemObserver` where it exists (desktop
Chrome 133+, bound by hand because `package:web` 1.1.1 lacks it, 9.2;
`unknown` and `errored` records force a full rescan, per the Chrome
article), from a "Rescan folder" button, and before every note overwrite
(3.8). A rescan is a sequence of shared-lock listing pages (6.2 R4), and
it rolls forward leftover journals under the exclusive lock first (R3).
On a focus rescan the controller also calls `queryPermission`, so a grant
that Chrome revoked in the background moves the controller to
`needsPermission` before a request fails.
