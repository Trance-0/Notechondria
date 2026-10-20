# Local folder storage mode: next phase and session handoff

Handoff written 2026-10-20 at VERSION 0.1.202 (code at `5efd96ff`), so
that a new agent session on a new machine can continue from GitHub alone.
Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md).
Paths are repo-root-relative; `lf/` is short for
`frontend/notechondria_shared/lib/src/local_folder/`. Line counts were
taken at `5efd96ff`; run `wc -l` again before relying on them.

## Where things stand

- Repo `github.com/Trance-0/Notechondria`, branch `main`. CI
  (`backend-tests`, `frontend-pages`, `docs-pages`) is green at 0.1.202.
  GitHub Pages serves 0.1.202 for the editor, planner, and portal, and
  the backend handshake reports 0.1.202.
- Done (`implementation_plan.md` 9.1): Phase 1, the foundation, in
  0.1.200 with the option hidden; Phase 2 in 0.1.201, where the editor
  shows "Use a local folder (no account)"; Phase 3 in 0.1.202, where the
  planner and portal show it too.
- Folder mode runs on desktop Chrome and Edge over https or
  `http://127.0.0.1`; Firefox, Safari, mobile, and plain http show the
  option disabled with the reason.
  - Editor: notes, courses, trash with the empty-trash cascade,
    attachments, covers, avatar, history and snapshots, study sessions,
    search (the `note_search_score` port), front page, heatmap, settings.
  - Planner: the note and course routes, plus events with recurrence,
    deadlines, the week view, and calendar feeds (`.ics` import; URL
    subscribe with the CORS fallback message). At connect it pushes
    browser-local courses, events, and feeds into the folder with the
    `client_local_id` upsert.
  - Portal: front page, notes, courses, planner events, and the same
    connect-time push. Each route shell starts the folder session itself
    (design review 3 T1), so a cold `#/note/<uuid>` opens the folder first.
- Not done: Phases 4 and 5 (sections B and C below); the open findings and
  deferred items in [`deferred.md`](deferred.md), ending with "Deferred
  from the 0.1.202 final review" (N1 to N15); U1, U5, U7, U10, U17, and
  U18 ([`unverified_and_sources.md`](unverified_and_sources.md) 11.1),
  which need real desktop Chrome; and the 17 manual checks of
  [`testing.md`](testing.md) 8.6 with a real disk folder, which no agent
  has run and the owner should. Code-versus-design differences are in
  [`revision_log.md`](revision_log.md) 12.4 to 12.6; Phase 3 has no entry
  yet.
- Not on GitHub: the agent reports in `.agents/tasks/` (design reviews 1
  to 3, phase reviews, progress notes), excluded through
  `.git/info/exclude`, and the run logs under `/tmp/nc_verify/`. Their
  findings are summarized in `deferred.md` and `revision_log.md`; design
  doc references to those paths name files a new machine will not have.

## How to resume on a new machine

1. Clone and initialize the submodule. The root `AGENTS.md` is a
   submodule directory (rules in `AGENTS.md/AGENTS.md`), empty until
   initialized:

   ```
   git clone git@github.com:Trance-0/Notechondria.git
   cd Notechondria
   git submodule update --init
   ```

2. Read `AGENTS.md/AGENTS.md` (1.6 has the 1000-line cap, 1.8 the message
   shape), `docs/AGENTS.md` (host budget, no local containers under 16 GB
   RAM, round-end convention, module and process names),
   `frontend/AGENTS.md`, `docs/development/local_folder_mode.md` with the
   part files the step needs, `deferred.md`, and this file.
3. Check the host before any build: `free -h`, `nproc`, `docker ps`.
   Flutter containers need at least 16 GB RAM. Take at most 70% of the
   free RAM, run one heavy container at a time, and wrap every run in
   `timeout`. On a smaller host, run static checks only and let CI prove
   the rest after the push.
4. No host Flutter SDK is needed; everything ran in Docker
   (`ghcr.io/cirruslabs/flutter:stable`, Flutter 3.44.0). Build the
   Chromium image with `scripts/local_folder_verify/build_image.sh`, run
   `scripts/local_folder_verify/ci.sh`, and compare with the baselines
   below. [`scripts/local_folder_verify/README.md`](../../../scripts/local_folder_verify/README.md)
   describes the scripts.
5. Push over SSH, `git push git@github.com:Trance-0/Notechondria.git
   main:main` (the last machine had no HTTPS token), or over HTTPS with a
   token from a credential helper, never in a remote URL or a tracked
   file. Then run the "After pushing" checks of `docs/AGENTS.md`: CI
   conclusions, the backend handshake, and each bundle's version.

Baselines at 0.1.202:

| Check | Result |
|---|---|
| `flutter test test/local_folder/ -r compact` in `frontend/notechondria_shared` | 353 pass |
| Full shared suite | All pass except 3 pre-existing failures in `test/version_update_banner_test.dart` |
| `test/smoke_test.dart` per app | Editor 15, planner 22, portal 23 |
| `flutter analyze` | Editor 99, planner 105, portal 123, shared 7 issues; 0 errors each |
| Backend contract (`backend/notes/test_api_contract.py`) | 42 fixtures |
| Chromium OPFS (`test/local_folder_opfs_test.dart`, `test/local_folder_opfs_timing_test.dart`) | 8 of 8, including the timing test |

Loopback preview: `scripts/local_remote_deploy.sh up|down` serves
`http://127.0.0.1:9068/{portal,editor,planner}/` against
`https://notechondria.trance-0.com` (runbook
`docs/deployment/local_preview.md`, 16 GB hosts only). On the last host
its containers did not restart after a reboot (containerd "file
exists"); running `up` again recreated them.

## Recommended order for the next session

### A. Hardening round, release 0.1.203

Close the highest-value follow-ups before Phase 4 builds on the same
code. IDs marked "202-" are from `deferred.md` "Deferred from the 0.1.202
final review"; the 0.1.201 review used N1 to N11 for other findings.

Do first: move the index cache (`_unverified`, `_scanLog`, `_scan`,
`_scheduleFlush`, `flushIndex`) out of `lf/local_folder_controller.dart`
(892 lines) into its own file (L2A2-5). The L2A2 fixes and Phase 4's
change handling both land in that code.

| Item | Problem | Files (lines) | Fix and test |
|---|---|---|---|
| 202-N6 | An unparsable `planner/events.json` or `planner/feeds.json` reads as empty, and the next create (the 7.1 push too) replaces it; `planner/sessions.json` and `planner/heatmap.json` behave the same | `lf/handlers/planner_records.dart` (231), `lf/handlers/planner.dart` (351), `lf/handlers/history_sessions.dart` (304), `lf/handlers/activity.dart` (171), `lf/folder_messages.dart` (572) | Refuse writes with a 1.8 503 while such a file exists; tests in `planner_routes_test.dart` (292) and `history_activity_test.dart` (248) |
| 202-N9 | Portal Disconnect clears only `_plannerEvents`; folder rows stay in memory, and a partly failed signed-out reload writes them to `local_cache`; the editor does the same | `frontend/portal_app/lib/app_shell.dart` (924), `frontend/portal_app/lib/core/initial_data.dart` (328), the editor shell | Mirror the planner's `_clearPlannerSessionFields` (`frontend/planner_app/lib/core/local_folder_push.dart:170`); smoke check: no folder row in `local_cache` after Disconnect and a failed reload |
| Scan holds | The first full scan's 500-entry page held the lock 1,993 to 2,228 ms over 2,000 OPFS notes, and the first list after an open from `index.json` 1,733 ms (L2A-6, L2A2-4), against R4's 2 s target | `lf/folder_scanner.dart` (269), `lf/handlers/lookup.dart` (220), the controller | Time-bounded pages; assert the scan page and the startup verification rescan in `test/local_folder_opfs_timing_test.dart` (230) |
| L2A2-1 to L2A2-3 | Index staleness: rescan replay can revert an identity fix or another tab's save; purged summaries can stay in `index.json`; roll-forward does not update the in-memory index | The new index-cache file, `lf/folder_index.dart` (501), `lf/folder_journal.dart` (419) | As written in `deferred.md`, including the two-notes-same-id test |
| Fonts | Flutter web loads Roboto and the Noto fallback fonts from `fonts.gstatic.com` in every mode; with no network it retries the fallbacks (1,866 requests in one planner run) | `frontend/{editor,planner,portal}_app/web/index.html`, `.github/workflows/frontend-pages.yml` | Bundle the fonts or point the engine's font fallback base URL at the app's own assets; prove it with a `--network none` browser load. Read `docs/LLM_CHECK.md` common mistake 9 before touching `flutter_bootstrap.js` |
| Covers | Shared `NoteCoverImage` uses `Image.network` (`:53`), so `nc-folder:` covers show the fallback in all three apps (202-N15) | `frontend/notechondria_shared/lib/src/components/note_cover_image.dart` (205) | `folderAwareImageProvider`; test in `folder_aware_image_test.dart` |
| Viewer semantics | The portal note viewer's title, subtitle, and body are not in the accessibility tree; the subtitle names "local-folder" as the author | `frontend/portal_app/lib/components/note_viewer.dart` (158) | Label it as the editor's viewer does; a smoke check finds the title by semantics |
| Q13 | The OPFS test-hook grep cannot fail: the compiler drops the hook, so hook and release bundles match | `.github/workflows/frontend-pages.yml` | Owner decides: a marker that survives in a hook build, or close Q13 |
| 202-N3 | Backend `read_calendar_feed` fetches any URL with no private-host guard (pre-existing server-side SSRF) | `backend/notes/services.py` (`:538-565`), `backend/notes/tests.py` | Refuse loopback, link-local, private, and reserved addresses, also after redirects; backend test; `py_compile` locally, `backend-tests` in CI |
| Docs debt | The Phase 3 rows of 9.2 and a 12.7 revision-log entry are missing | `implementation_plan.md`, `revision_log.md` | Write them from `deferred.md` "Deferred from Phase 3" (`lf/handlers/planner_records.dart`, `lf/handlers/planner.dart`, `lf/handlers/calendar.dart`) |

Done when: each row is fixed with a test, or stays in `deferred.md` with
the reason; analyze has 0 errors and no test count drops; the timing test
passes with the new assertions; the read-only final review passes; the
release step lands (VERSION 0.1.203, `docs/versions/0.1.203.md` and its
`docs/SUMMARY.md` entry, the `docs/LLM_CHECK.md` round log); CI is green
and each Pages bundle reports 0.1.203. The owner's manual checks need no
agent and can run in parallel.

### B. Phase 4: interchange and multi-tab

Read: main 3.3 (interchange rules) and 5 (secrets, denylist);
`modes_and_migration.md` 7.1 and 7.2; `storage_rules.md` 3.4.1, 3.7, and
3.8; `security_and_tabs.md` 6.2 (R1 to R5, the change channel, no handle
handoff) and 6.4; `implementation_plan.md` 9.2 (file rows, zone wrapper
table); `testing.md` 8.3; `docs/export_format_v1.md`; U16.

Four sub-steps, each committed after its own review:

| Step | Files (lines) | Work | Tests |
|---|---|---|---|
| 4a Export | New `lf/folder_archive_bridge.dart` (planned about 340), `lf/secret_denylist.dart` (51), `frontend/notechondria_shared/lib/src/components/local_folder_status_card.dart` (254), `frontend/notechondria_shared/lib/src/utils/local_archive.dart` (501), `frontend/{editor,planner,portal}_app/lib/core/local_archive_io.dart` (230, 243, 230) | Folder to the v1 buckets plus the optional `folder/` subtree (without `.notechondria/` and `*.crswap`), denylist on every exported JSON object; Export on the status card; the existing export action reads the folder in folder mode; fix the two doc-versus-code differences in `docs/export_format_v1.md` (main 3.3) | Denylist fixture in both directions (main 5); `readLocalArchive` reads the export back |
| 4b Import | The bridge, `frontend/notechondria_shared/lib/src/components/local_folder_sign_in_option.dart` (273) | "Start from an archive" on the empty-folder step, its own button whose `onPressed` opens the file picker (1.3); restore `folder/` verbatim with a new `folder_id` and `restored_from_folder_id`, else map the buckets as the 7.1 push does; chunked, `manifest.json` last (6.2 R4) | Folder to `.nchron` to folder gives the same tree except `folder_id`; an interrupted import leaves no manifest; U16; archive tests in `test/local_folder_opfs_test.dart` (200) |
| 4c Changes | `lf/change_channel.dart` (37), `lf/change_channel_web.dart` (49, planned about 190), `lf/js_bindings_web.dart` (165; `FileSystemObserver` binding at `:113`), the controller after the split, `frontend/{editor,planner,portal}_app/lib/core/local_folder_connect.dart` (363, 333, 555) | Post `{folder_id, op_id, op, paths}` after each operation or chunk; other tabs drop those index entries and rerun their load path, at most once per second; focus and `visibilitychange` rescans at most once per 5 s per tab, with `queryPermission`; observer `unknown` and `errored` records force a full rescan; listeners bound as the 9.2 table says. Also closes L2A-6 and "Other tabs' and outside programs' edits" in `deferred.md` | `concurrency_test.dart` (237) with the channel delayed and dropped; Chromium: a throwing listener reaches the zone; per-app smoke check: one change message, one reload |
| 4d Adopt | `lf/folder_identity.dart` (334), `lf/folder_scanner.dart` (269), `lf/folder_pick_flow.dart` (158) | `storage_rules.md` 3.7 "Adopting a GitHub data-sync clone": keep the server ids, raise every counter, resolve collisions by the duplicate rule; layout in `docs/integrations/github-sync.md`. A clone has no `manifest.json`, so the entry point is likely the non-empty folder confirmation (2.9); confirm in the round | A fixture tree in that layout opens with its ids kept and the counters raised |

Done when: the four sub-steps pass review; 8.6 items 5, 6, and 12 pass on
the owner's machine or are recorded as not run; the Chromium archive and
timing tests pass; baselines hold; the 9.5 docs are updated
(`docs/export_format_v1.md`, `docs/development/storage_model.md`); the
release step lands and Phase 4 is ticked in `docs/TODO.md`.

### C. Phase 5: GitHub with a fine-grained token

Read: main 5 (how the token is supplied, the three log lines, the Q6
table); `feature_matrix.md` F49 to F52 and the GitHub and course git rows
of 4.1; `implementation_plan.md` 9.2 rows and the "GitHub card gate"
paragraph of 9.3; `docs/integrations/github-sync.md`; 202-N12 (secret
iCal URLs in `planner/feeds.json` must not be pushed unprotected).

- New: `lf/credential_store.dart` and `lf/credential_store_web.dart`
  (memory store and opt-in IndexedDB store, callbacks bound as in
  `lf/handle_store_web.dart`), `lf/github_token_client.dart`, and
  `lf/handlers/github.dart`, registered in `lf/router.dart` (334).
  Routes: `GET,DELETE /integrations/github/status/`, `GET .../repos/`,
  `POST .../push/`; `POST .../callback/` answers 501 (F50); portal
  `PUT /courses/{id}/git/` and `POST /courses/{id}/git/import/` (F51).
- Card: `GithubSyncExperimentalCard` is in
  `frontend/notechondria_shared/lib/src/components/mcp_skill_section.dart`
  (699, `:173`); put the folder-mode token field in a new file. Replace
  the `cloudOnly(...)` gate at `frontend/editor_app/lib/core/build_helpers.dart:703`
  (864), `frontend/planner_app/lib/app_shell.dart:944` (979), and
  `frontend/portal_app/lib/core/build_page.dart:249` (286). The planner
  shell has 20 lines of room: first move its `_SettingsPage(...)` builder
  into a new `frontend/planner_app/lib/core/settings_page_builder.dart`
  part (9.3). Fallback card sites:
  `frontend/editor_app/lib/modules/settings_pages.dart:787` (925),
  `frontend/planner_app/lib/modules/settings.dart:542` (950). Leave
  `frontend/portal_app/lib/modules/settings_pages.dart` (1029, over the
  cap) alone; it omits a null card builder.
- Tests: a fake `api.github.com` client; one `GET /user` before a token
  is kept; the token string in no folder file, no `.nchron`, and no log
  line; the denylist on the push; memory store by default; log lines as
  in main 5; a smoke check that the folder-mode card sends nothing to the
  Notechondria backend.
- Done when: 8.6 item 13 passes on the owner's machine,
  `docs/integrations/github-sync.md` documents the token path, and the
  release step lands.

## Working method that worked

- **Ownership.** Parallel agents split work by directory: the shared
  `lf/**`, each app's `frontend/<app>/`, and the shared UI
  (`frontend/notechondria_shared/lib/src/components/`, the ARB files).
- **Locks.** `flock /tmp/nc_verify/flutter.lock` around every Flutter
  container, so one heavy job ran at a time, and
  `flock /tmp/nc_verify/git.lock sh -c 'git add <files> && git commit ...'`
  for commits, staging files by name, never `git add -A`.
- **Scratch copies.** Tests ran on `git archive HEAD frontend` unpacked
  into a scratch directory, never on the working tree. Containers had no
  `-p` mapping; browser runs used `--network none` (the OPFS unit tests
  need the network for `pub get`). On the last host `--memory` was not
  enforced and `--cpus` failed, so `timeout` was the real bound.
- **Reviews.** Larger sub-steps had their own review (Phase 1a, Phase 1b,
  loop 2a). Each phase ended with a read-only final review (the reviewer
  edits nothing), then the release step (VERSION bump,
  `docs/versions/<v>.md` with its `docs/SUMMARY.md` entry in the same
  commit, the `docs/LLM_CHECK.md` round log), then the blocking fixes,
  then the push.
- **Records.** Code-versus-design differences go to `revision_log.md` and
  deferrals to `deferred.md`, in the same commit as the code.
- **Push after tests pass,** then confirm CI and the deployed bundles.
  Docs-only commits skip the VERSION bump (`docs/AGENTS.md`).
- **l10n.** `flutter gen-l10n` still rejects `activityWeightN`; the
  workaround is in `deferred.md` ("Deferred from Phase 2").

## Owner decisions still open

From `local_folder_mode.md` 10.1 (each runs on its recommended default
until answered) and the deferred lists:

| # | Question | Default in use |
|---|---|---|
| Q1 | Did "dashboard for local services" mean a localhost daemon? | In-page backend; the router speaks `/api/v1`, so a daemon could host it later |
| Q4 | Serve the apps from a dedicated origin? | Recommended, separate round (DNS and base href) |
| Q6 | Where Phase 5 credentials live: memory only, "remember on this browser" (IndexedDB), or remembered with a passphrase (WebCrypto) | Memory only with the opt-in; decide before Phase 5 whether the passphrase variant is built |
| Q7 | Accept a user-supplied fine-grained token for GitHub in folder mode? | Yes; the GitHub App stays cloud-only (F50) |
| Q12 | Full-fidelity "move folder to cloud"? | Follow-up; interim paths in 7.3 |
| Q13 | CI grep guard for the OPFS hook marker | Guard recommended but not added; as designed it could not fail (see A) |
| Q14 | Backend contract test | Built on its default in 0.1.200; still open: refresh `docs/api/backend_api_spec.md` (9.5) |
| Q18 | Keep the connect-time moves into the recycle bin and recovery list? | Keep; also decide whether "Start empty" should skip the starter data it moves in |
| Q19 | Serve `/media/` uploads so they cannot run as same-origin pages | Separate backend hardening |
| 201-N9 | Folder sessions skip the `foreign_local_data_owner` guard | Document as a design choice, or add the guard |
| 202-N1, N2 | Feed redirects and the backend-host check | Document in F42, or fetch with `redirect: 'manual'` and widen the host check |

Q2, Q3, Q5, Q8, Q9, Q11, and Q17 also run on their defaults; none blocks
Phase 4 or 5.
