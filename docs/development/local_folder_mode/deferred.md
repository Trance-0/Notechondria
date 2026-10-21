# Local folder storage mode: deferred items and follow-ups

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md).
The phase checklist (Phases 1 to 5, Q13, and the manual desktop Chrome
checks) is in [`docs/TODO.md`](../../TODO.md) under "Local folder storage
mode". These lists moved here from that section in 0.1.202 to keep
`docs/TODO.md` under the 1000-line cap (AGENTS.md 1.6); the bullets are
unchanged. "Above" and "below" in them refer to this file, and
"## Planner" to `docs/TODO.md`.

## Review follow-ups, open items, and deferred lists

- [x] Phase 0 spike, U3 (Phase 2): a real click on the Flutter "Use a
  local folder" button keeps transient activation until
  `showDirectoryPicker`, on both the semantics and the pointer path, in
  headless Chromium 131 (`unverified_and_sources.md` 11.1). The other
  spike items are on the manual list under "Deferred from Phase 2".
- [x] Phase 1b review follow-ups (`.agents/tasks/phase1b-review.json`),
  landed before Phase 2 shows the option (design `revision_log.md` 12.5):
  - P1B-1 (MEDIUM): note and course lookups read every note inside the
    lock. Lookups now go through the in-memory index (schema 2 holds the
    note summary fields) and re-read only the note served or rewritten.
    Chromium timing over 2,000 OPFS notes
    (`test/local_folder_opfs_timing_test.dart`): single-note GET 27 ms,
    PATCH 59 ms; 0.1.200 answered the same GET with a 503 after 8 s.
  - P1B-2: "Check for updates" no longer counts a locally answered
    handshake (`x-notechondria-backend: local-folder`) as a cloud answer.
  - P1B-3: after a failed roll-forward, write lookups skip nothing, so a
    PATCH, DELETE, or draft upsert of the pending note answers
    `writeBlockedByJournal`.
  - P1B-4: `scrubRouteDetail` on every 404 and 501 detail in
    `LocalFolderTransport._detail`.
  - P1B-5: tests for the inert folder branches, a throwing `prepare`, the
    7 s write start, and the transport R3 path.
  - P1A-7 (LOW): closed in 0.1.200; the `invalid to\u212Aen` test added,
    and overlapping sentinels are now broken too.
- [x] Loop 2a review follow-ups (`.agents/tasks/review-2a.json`, design
  `revision_log.md` 12.5; `review-2a-pass2.json` APPROVED and marks
  L2A-1 to L2A-5 and L2A-7 fixed, with the residues listed below):
  - L2A-1 (MEDIUM): `index.json` was written only by scans and trusted
    on open, so a reload listed pre-edit rows. The in-memory index is now
    flushed to `index.json` 1 s after this tab's first write of a burst,
    and stored note entries are compared with the disk by the first
    listing that meets them.
  - L2A-2: a rescan keeps the index changes this tab made while it ran.
  - L2A-3: a re-read note whose sidecar differs from its entry gets a
    fresh entry (another tab's description edit, a renumbered id).
  - L2A-4: note delete picks comments by `source_note_uuid` and checks
    `is_public` on disk.
  - L2A-5: course delete stats every note body before it selects by
    `course_slug`.
  - L2A-7: the Chromium timing test asserts every route's hold.
- [ ] Search hold: Phase 1's substring search read every body its title
  and description missed, in batches of 32, and held the shared lock 1.2
  to 1.3 s over 2,000 OPFS notes in headless Chromium. The Phase 2
  `note_search_score` port reads every body (each score needs the
  content) and was not timed in Chromium. Bound it (body cache, or
  chunked holds within the 8 s read deadline).
- [ ] Scan page size: a 500-entry page of the first full scan held the
  lock 1,993 ms, then 2,087 ms and 2,228 ms in later runs over the same
  2,000 OPFS notes, above R4's 2 s target. Use a time-bounded page
  before folders of that size are common (the timing test only prints
  this number).
- [ ] L2A-6, Phase 4: the first list after an open from `index.json`
  stats every stored note entry in one hold (1,733 ms for 2,000 notes),
  and a listing that finds many new files reads them in one hold (626 ms
  for 300). About 2,300 stored notes or 900 new files pass the 2 s
  target. Bound both per hold and leave the rest to Phase 4's paged
  rescans and change path.
- [ ] Other tabs' and outside programs' edits to an existing note made
  after this tab compared it reach this tab's lists at its next rescan,
  or when this tab reads that note, until Phase 4's change messages. A
  note another tab's identity fix renumbered answers 404 by its new id
  until its old id is asked for or a rescan runs. Course delete stats
  every note before its detach chunks, so a note moved into the course
  between that pass and its chunk keeps the slug.
- [ ] Deferred from Phase 2 (shared content routes; design
  `revision_log.md` 12.6):
  - Search ranking parity: the port matches CPython `difflib` to 1e-12 on
    ASCII, CJK, accented, and emoji cases, but Dart's `toLowerCase` and
    `\s` differ from Python's `str.lower` and `re` `\s` on a few code
    points (for example U+0130, U+001C to U+001F), and the backend scores
    stored `content` with absolute `/media/` URLs where the folder has
    `nc-folder:` URLs.
  - Heatmap edge cases: notes added by hand, adopted by a scan, or
    imported count on no day; the day is the device's local day, not the
    server's `TIME_ZONE`; recurring planner events are not expanded (as
    in the backend).
  - Cover upload does not bump the note's `last_edit` (the backend
    does); the folder leaves the note body alone.
  - History lists both retention pools (up to 24 versions); the backend
    answers 12.
  - Chromium/OPFS: binary writes (`writeBytes`) of attachments, covers,
    and the avatar, and `FolderImage` reads, are tested over
    `MemoryFolderFs` only.
  - The full-scan longest hold (2,087 ms, see "Scan page size") is
    unchanged by Phase 2.
  - Editor wiring: on desktop Chrome, check the spike items U1, U5, U7,
    U10, U17, and U18 (`unverified_and_sources.md` 11.1) with the manual
    checks of `testing.md` 8.6; headless Chromium answers the picker with
    `AbortError`, so the real dialog (check 2) is still unchecked.
  - Editor wiring: a mid-session revocation replaces the shell with the
    reconnect view (as at startup) instead of a banner over the shell
    (6.3). Edits in an open note dialog survive as browser-local drafts.
  - Editor wiring: "Browser data moved" (7.1 step 5) is a log line and a
    snackbar only; the status card does not repeat it, and the card has
    no "Folder used by the editor only" line (2.10 rule 5).
  - Editor wiring: with a cloud session that won over a folder, the
    status card still shows the folder state ("Disconnected") and the
    "Remember this folder" box; show only the precedence line there.
  - Editor wiring: `LocalFolderController.disconnect()` keeps `record`;
    the sign-in option ignores it after a Disconnect in the same tab
    (`disconnectReason == thisTab`). Clear it in the controller.
  - Editor wiring: a folder start first renders the cached cloud front
    page and categories from `local_cache` until the folder load replaces
    them.
  - Editor wiring: app-level smoke checks not written yet (8.5): startup
    with another tab holding the lock for 7 s, the "Choose again"
    refusals (other `folder_id`, empty folder, `AbortError`) through the
    app, the passthrough and the snapshot through the app, and Disconnect
    with a pending note edit. The client-level checks cover the
    passthrough, uploads, and the 503s.
  - Editor wiring: `flutter gen-l10n` still rejects `activityWeightN`;
    Phase 2 regenerated from a scratch copy with a String placeholder and
    spliced the committed member back (0.1.198 procedure). The regenerated
    doc comments of `activityWeightN` and the two heatmap strings now match
    the ARB files.
- [ ] Review LOW findings of loop 2a pass 2 (`.agents/tasks/review-2a-pass2.json`),
  deferred for 0.1.201:
  - L2A2-1: the rescan replays this tab's index changes over the scan's
    entries without checking order, so an identity fix or another tab's
    save that the scan read can be reverted in the index (GET by the new
    id answers 404, or the list shows the older row) until a reload. Stat
    each logged path in the final hold and keep the entry that matches
    the disk; add the two-notes-same-id test.
  - L2A2-2: purged-note summaries (title, description, excerpt) can stay
    in `.notechondria/index.json` when the tab closes within the 1 s
    flush delay, and a listing that drops entries schedules no flush.
    Write `index.json` at once after a purge or empty trash.
  - L2A2-3: a journal roll-forward, and a commit that fails partway, do
    not update the in-memory index; this tab lists the old rows until a
    rescan, a read of the note, or a reload. Re-index the replayed paths
    or mark them unverified.
  - L2A2-4: the first list after an open from `index.json` holds the
    lock 1,733 ms for 2,000 notes, and the first full scan's longest page
    2,087 ms (printed only). The review asked to close the two TODO items
    above ("Scan page size", L2A-6) before the option is shown; the owner
    deferred them for 0.1.201. Also assert the startup verification
    rescan's page hold in the timing test.
  - [x] L2A2-5 (INFO): `local_folder_controller.dart` was near the
    1000-line cap; the index cache (`_unverified`, `_scanLog`, `_scan`,
    `_scheduleFlush`, `flushIndex`, plus `_index`, `_flushTimer`,
    `_indexDirty`, `_progress`, `_setIndex`, `_scanner`, `isUnverified`,
    `updateIndex`) moved to `lf/folder_index_cache.dart` as
    `FolderIndexCache` in 0.1.203. The controller keeps thin
    `index`/`progress`/`isUnverified`/`updateIndex`/`flushIndex`/`rescan`
    delegators, so the transport, handlers, and tests are unchanged, and
    dropped from 892 to 788 lines.
- [ ] Found by the 0.1.201 browser check (headless Chromium, editor in
  folder mode):
  - Fonts: Flutter web loads Roboto and the Noto Sans Symbols fallback
    from `fonts.gstatic.com` (the bundle ships only MaterialIcons,
    CupertinoIcons, and the KaTeX fonts). With no network the first load
    draws no text, and folder mode still sends these font requests to
    Google (no note data). Bundle the fonts or set the engine's font
    fallback base URL to the app's own assets. Affects every mode, not
    only the folder.
  - Folder-mode wording: note cards say "Synced to cloud", Settings shows
    "Backend settings: Online. API URL: ...", and the recycle bin page
    says "Cloud recycle bin" and "soft-deleted note(s) on the server".
  - "Start empty" on an empty folder still put the browser's starter
    draft into the folder (the 7.1 connect-time move). By design, but the
    label suggests an empty folder; reword or skip the starter draft.
  - The empty-folder step shows "Start empty" and "Cancel" only; "Start
    from an archive" is Phase 4.
- [ ] Deferred from the 0.1.201 final review (`.agents/tasks/review-phase2-final.json`;
  F1, F2, and N8 landed in 0.1.201):
  - N1: add an app-level test of the 7.1 connect-time push (drafts and courses land in the folder, copies in the recycle bin, zero network requests).
  - N2: `_promoteQueuedAttachments` deletes local blobs before the content patch; a failed patch leaves `local://` URLs with no blob.
  - N3: skip the cloud-copy draft path (`draft_sync.dart:244`) in folder mode; its cloud note id can name an unrelated folder note.
  - N4: purge removes `assets/notes/<hex>/` even when another note's body links to those files; document it or check references first.
  - N5: `encodeAttachments` drops unknown top-level keys and records without `id`/`filename` from `attachments.json`.
  - N6: search reads every body on every query (tracked as "Search hold").
  - N7 (fixed in 0.1.203 with 202-N6, #33): a malformed `planner/heatmap.json` is silently replaced on the next note create.
  - N9: folder sessions skip the `foreign_local_data_owner` guard, so another cloud user's browser drafts move into the folder; document as a design choice.
  - N10: `isFolderUrl` checks `nc-folder:` while `folderPathForUrl` needs `kFolderUrlPrefix`; skipped because the strict prefix would send a malformed `nc-folder:` URL to `NetworkImage` instead of the placeholder.
  - N11: `sanitizeFileName` does not rename Windows-reserved names (`CON`, `NUL`, ...) or names with a trailing dot or space; such a write fails with a 500.
  - F2 follow-up: composed and decomposed Unicode forms of one name (NFC/NFD) are one file on APFS, but `uniqueFileName` compares them as different; Dart has no built-in normalization.
- [ ] Deferred from Phase 3 (planner and portal):
  - Shared planner routes: URL feeds are downloaded only on subscribe and
    on `PATCH /calendar-feeds/{id}/` with `source_url` or the folder-only
    `refresh: true`. `GET /activity/week/` serves the cached
    `planner/feeds/<id>.ics` and never downloads, because a GET may not
    write (6.2 R1). F42's "refresh on demand and on focus" needs the
    planner and portal to send that PATCH, or a transport read path that
    downloads before it takes the lock.
  - Shared planner routes: F43 is inferred. The browser reports a host
    without `Access-Control-Allow-Origin`, a DNS failure, and no network
    as the same opaque `ClientException`, so all three answer the F43
    message (502). The tests use a fake client; a Chromium run against a
    CORS-enabled host and a Google public calendar is still to do.
  - Shared planner routes: one download is bounded by 5 s
    (`kCalendarFetchTimeout`) so it fits the 7 s write deadline with its
    lock waits (the backend allows 10 s); answers over 5 MB are refused.
  - Shared planner routes: feed events come from the shared offline
    reader (`utils/ical_events.dart`), not a port of `parse_ical_events`:
    all-day events land on the local day (the backend uses UTC midnight),
    `TZID` times are device-local, a VEVENT without SUMMARY is
    "(untitled event)" (the backend uses the feed title), and RRULE is not
    expanded (as in the backend).
  - Shared planner routes: the 7.1 recovery list (`pushed_items_store.dart`
    in implementation plan 9.2) is not built; it belongs with the planner
    and portal connect-time push.
  - Shared planner routes: design docs not updated for Phase 3:
    implementation plan 9.2 rows (`planner_records.dart` 231 lines,
    `planner.dart` 351, `calendar.dart` 411) and a revision log entry for
    the choices above, for `GET /activity/` answering the ten newest notes
    as `ActivityApiView` does (deadlines are in the week payload), and for
    the front page's `upcoming_events` built with `planner_event_payload`.
  - Planner wiring: Disconnect does not offer "Restore <n> planner items
    pushed on <date>" (7.1 step 3). The planner writes its own recovery
    list `notechondria.planner.pushed_to_folder` (`core/local_folder_push.dart`,
    entries pruned after 30 days), not a shared `pushed_items_store.dart`;
    the restore button reads it once it exists.
  - Planner wiring: a planner tab signed in to the cloud (in memory) when
    another tab connects a folder shows the 2.10 rule 5 banner ("Reload to
    use it"), and its status card has no rule 2 line: the controller sets
    `cloudSessionWins` once at boot, and the planner has no saved session.
    A reload ends that session and opens the folder.
  - Planner wiring: the shared `NoteCoverImage` uses `Image.network`, so an
    `nc-folder:` cover shows the barcode fallback (planner, and the editor
    and portal too). Give it a folder-aware provider.
  - Planner wiring: subscribing by URL in folder mode posts `source_url` to
    the folder route; no planner smoke check covers it, and the planner
    sends no `refresh: true` PATCH (see the F42 bullet above).
  - Planner wiring: folder-mode wording left as is: the course and draft
    push logs say "created on server", and the folder-failure fallback of
    an `.ics` import ends "it is not uploaded to the cloud". "Browser data
    moved" (7.1 step 5) is a log line and a snackbar only, and the push's
    lines can leave the 80-line persisted debug log behind the folder
    requests' DEBUG lines.
  - Planner wiring: a folder start first renders the cached cloud courses
    and activity from `local_cache` until the folder load replaces them;
    only `is_local_event` rows are pushed, so cloud rows cached by an
    earlier session stay in the browser (the offline planner events item
    under "## Planner").
  - Planner wiring: app-level checks not written yet (8.5): startup while
    another tab holds the lock, the "Choose again" refusals, Disconnect
    with a pending event edit, and a connect through the sign-in option's
    picker in the planner (the 7.1 check starts from a connected folder
    without `folder_pushed`). The U3 click check ran on the editor's build
    only; the planner uses the same shared option widget.
  - Portal wiring: Disconnect does not offer "Restore <n> planner items
    pushed on <date>" (7.1 step 3). The portal writes its own recovery
    list `notechondria.portal.pushed_to_folder` (`core/local_folder_connect.dart`;
    replaced after 30 days or for another folder) and nothing reads it
    yet. "Browser data moved" therefore names "a recovery list" instead of
    "Disconnect → Restore", and it is a log line and a snackbar only.
  - Portal wiring: `notechondria.portal.folder_pushed` is set only when the
    folder accepted every local event. A refused event stays in the local
    list and the push runs again at every start (the folder upserts on
    `client_local_id`, so a repeat leaves one copy).
  - Portal wiring: the reconnect view of `_NoteRoutePage` has no "Use
    browser-local mode instead" (that is the shell's `disconnectFolder`);
    Back shows the shell's reconnect view, which has it.
  - Portal wiring: a later shell route (a hash change while the app runs)
    does not open the folder again; it waits up to 30 s for the first
    shell's open and then applies the folder payload. No smoke check
    covers it.
  - Portal wiring: as in the editor, a mid-session revocation replaces the
    shell with the reconnect view instead of a banner over it (6.3), and a
    folder start first renders the cached cloud front page, courses, and
    activity from `local_cache` until the folder load replaces them.
  - Portal wiring: folder-mode wording left as is: the course push log
    says "created on server", and the Settings backend row still reads
    "Online" with the cloud API URL.
  - Portal wiring: app-level checks not written yet (8.5 "Portal"): the
    front page from folder data, course reorder, the `.nchron` export
    (Phase 4), startup while another tab holds the lock, the "Choose
    again" refusals, the passthrough through the app, Disconnect with a
    pending note edit, and a connect through the sign-in option's picker
    (the 7.1 check starts from a connected folder without
    `folder_pushed`). The U3 click check ran on the editor's build only;
    the portal uses the same shared option widget.
- [ ] Found by the 0.1.202 browser check (headless Chromium, planner and
  portal in folder mode; evidence in `.agents/tasks/rel202/`, not
  committed):
  - Portal note viewer: the title, the subtitle, and the Markdown body
    are not in the accessibility tree, in session and on a cold
    `#/note/<uuid>` (the dialog holds an unlabeled close button and an
    empty read-only text field). The editor's viewer, also inside a
    `SelectionArea`, labels its title. Screen readers get no note text;
    the e2e checked the cold route by screenshot instead.
  - Portal note viewer: the subtitle shows the folder session's user name,
    "local-folder", as the author.
  - Portal Learner list: a note created in folder mode does not appear in
    the list (default "Public" scope, "No cloud notes yet") until a
    reload; after the reload the same scope lists it as "Private".
    Folder-mode wording there: "Search your cloud notes", "No cloud notes
    yet".
  - Fonts (extends the 0.1.201 item): with no network the engine requests
    the fallback fonts again and again. One planner run sent 1,866
    requests to `fonts.gstatic.com` (Noto Sans Symbols 691, Noto Sans SC
    759, Noto Sans HK 414); the portal run, with Roboto answered in the
    browser, sent 327 for Noto Sans Symbols.
  - Planner "Start empty" on an empty folder moved the browser's starter
    course, two starter notes, and the starter event "Draft weekly study
    block" into the folder (the 7.1 connect-time push), as in the editor
    item above.
  - The Firefox check ran on the planner only; the portal uses the same
    shared option widget.

## Deferred from the 0.1.202 final review

From `.agents/tasks/review-phase3-final.json` (F1 and the N7 write order
landed in 0.1.202). `frontend/notechondria_shared/lib/src/local_folder/` is shortened to `lf/`.

- [ ] N1 (LOW): the browser follows feed redirects and the backend-host check sees only the first URL, so a feed host that redirects to the Notechondria server gets one GET without `Authorization` or cookies (`lf/handlers/calendar.dart:200-205`, `lf/transport.dart:396-415`); document it in F42 or use a fetch client with `redirect: 'manual'`.
- [ ] N2 (LOW): the backend-host check compares hostnames with the API base host only; it misses the page-origin host, a trailing-dot host, and IP aliases (`lf/handlers/calendar.dart:200-205`); on web also refuse `Uri.base.host` and strip a trailing dot.
- [x] (0.1.203, #42, backend half) N3 (LOW): the folder backend fetches loopback or LAN URLs the user typed (same reach as any page; CORS and Private Network Access apply), and the backend's `read_calendar_feed` has no private-host guard, a pre-existing server-side SSRF exposure (`backend/notes/services.py:538-565`).
- [ ] N4 (LOW): a `refresh: true` PATCH downloads the stored `source_url` without re-running `_sourceUrl`, so a hand-edited URL is fetched as-is and a `Uri.parse` throw surfaces as an unhandled error (`lf/handlers/calendar.dart:344-351`).
- [ ] N5 (LOW): `BrowserClient` buffers the whole XHR response, so the 5 MB bound applies only afterwards, and the 5 s timeout does not abort the request (`lf/transport.dart:396-415`).
- [x] (0.1.203, #33) N6 (MEDIUM): an unparsable `planner/events.json` or `planner/feeds.json` reads as empty and the next create (including the 7.1 push) replaces it (`lf/handlers/planner_records.dart:49-66`; Phase 2 has the same pattern for `sessions.json` and `heatmap.json`), and a known `client_local_id` whose record has an unreadable `event_date` gets a duplicate (`lf/handlers/planner.dart:159-164`); refuse writes with a 1.8 503 while such a file exists.
- [ ] N7 (MEDIUM, recovery-list shape): the portal's recovery list `notechondria.portal.pushed_to_folder` is a single entry that drops another folder's items early and resets `pushed_at` for every item, while the planner keeps one entry per push (`frontend/portal_app/lib/core/local_folder_connect.dart:446-470`).
- [ ] N8 (LOW): the planner sets `folder_pushed` even when items failed, so a refused item is never retried in that folder (`frontend/planner_app/lib/core/local_folder_connect.dart:234-238`), and local events with a positive (cloud) `course_id` get a 404 from the folder: stuck in the planner, retried at every start in the portal (`frontend/planner_app/lib/core/local_folder_push.dart:43-46`, `frontend/portal_app/lib/core/local_folder_connect.dart:381-384`).
- [x] (0.1.203, #34) N9 (MEDIUM): portal Disconnect clears only `_plannerEvents` (`frontend/portal_app/lib/app_shell.dart:390-392`); folder rows stay in `_frontPage`, `_courses`, `_activity`, and `_activityWeek`, and a partly failed signed-out reload writes them to `local_cache` (`frontend/portal_app/lib/core/initial_data.dart:286-307`), against 2.7; the editor does the same. Mirror the planner's `_clearPlannerSessionFields`.
- [ ] N10 (LOW): after a Disconnect, other mounted portal route shells keep the folder token and profile; their requests get the 503, but their UI shows a stale folder session (`frontend/portal_app/lib/core/local_folder_connect.dart:537`).
- [ ] N11 (LOW): 1.8 wording: the `import_summary.error` strings lack the module/process part (`lf/handlers/calendar.dart:115-133`); `calendarIsBackend` says "Calendar not subscribed" on a refresh too (`lf/folder_messages.dart:559`); the portal's course-push log says "will retry on next sync" in folder mode (`frontend/portal_app/lib/core/local_folder_connect.dart:361`); `Planner.Sync.Courses` and `Portal.Sync.Courses` are missing from the `docs/AGENTS.md` module table (pre-existing).
- [ ] N12 (LOW): secret iCal addresses (bearer URLs) are stored in plain text in `planner/feeds.json` (`lf/handlers/calendar.dart`); note it in `storage_rules.md` before Phase 5 GitHub sync.
- [ ] N13 (LOW): a planner log line written during a build, just before the shell unmounts, is dropped (`frontend/planner_app/lib/app_shell.dart:428-433`).
- [ ] N14 (LOW): near the 1.6 cap: planner `frontend/planner_app/lib/app_shell.dart` is at 979 lines (`docs/TODO.md` was at 939; these lists moved here in 0.1.202).
- [ ] N15 (LOW): leftover `Image.network` sites: the portal custom splash with the user-configured URL (`frontend/portal_app/lib/components/custom_splash_overlay.dart:71`, pre-existing) and the shared `NoteCoverImage` (`frontend/notechondria_shared/lib/src/components/note_cover_image.dart:53`, already listed above), where an `nc-folder:` URL fails in the browser without a request.
