# Local folder storage mode: unverified items and sources

Part of the design in [`../local_folder_mode.md`](../local_folder_mode.md)
(section 11). Same conventions: repo-root-relative paths, `file:line` at
HEAD `48988a20` (VERSION 0.1.199), and global section numbers (the file
list is at the top of the main document). Section 11 moved here from the
main document in revision 2, so that the main document stays under the
1000-line cap (AGENTS.md 1.6).

## 11.1 Unverified items

| # | Item | Where it matters | How to close |
|---|---|---|---|
| U1 | Flutter web `Image.network` with `blob:` URLs | 3.6 (avoided by the `nc-folder:` provider) | Spike |
| U2 | `idb_shim` storing a raw `FileSystemDirectoryHandle` | Handle store (avoided by using `package:web` IndexedDB) | Spike |
| U3 | Transient user activation survives Flutter web `onPressed` until `showDirectoryPicker` | 1.2, 1.3 | Closed in Phase 2 (below) |
| U4 | Chrome blocks the home directory root (the brief's claim); only OS folders are confirmed | 1.4 | Manual check 3 |
| U5 | `FileSystemFileHandle.move()` overwrite behavior | 3.4 (not relied on) | Spike |
| U6 | Scan time for large folders | 2.9, 3.8 | Measure in Phase 1 |
| U7 | Installability of the three apps as PWAs and the scope of an installed app's persisted grant | 6.1 | Spike |
| U9 | CORS headers of iCloud and Outlook published calendars (Google verified: none) | F42, F43 | Probe real URLs |
| U10 | `queryPermission` on OPFS handles | 8.3 (hook bypasses it) | Spike |
| U12 | Ranking parity of a Dart `SequenceMatcher` port | F25 | Fixture tests |
| U14 | Android picker and permission behavior | Q2 | Only if Q2 changes |
| U16 | Attachments in a folder export imported into browser-local mode after the one-shot attachment migration | 3.3 | Phase 4 test |
| U17 | Chrome names the `createWritable` swap file `<name>.crswap` in the target's directory | 3.1, 3.4 (the ignore rule is harmless if the name differs) | Spike |
| U18 | Web Locks held by a tab are released when its renderer crashes. Release on tab close is specified: the unloading document cleanup steps terminate the document's remaining locks (Web Locks spec, section 2.6) | 3.4.1 (roll-forward by another tab) | Spike: kill the renderer from Chrome's task manager while a lock is held |

No longer needed in revision 2: U13 (posting a handle over
`BroadcastChannel`), because v1 has no handle handoff (6.2).

Closed in revision 1:

- U8: planner and portal already keep a failed save as a browser-local
  draft (`frontend/planner_app/lib/core/note_crud.dart:139-158`,
  `frontend/portal_app/lib/core/note_crud.dart:135-150`).
- U11: `prune_recent_versions` keeps the 12 newest versions
  (`backend/notes/services.py:339-344`); the backend snapshots only on an
  explicit snapshot and before a restore (`backend/notes/api.py:1899`,
  `:1918`). Storage rules 3.8 states the resulting bound.
- U15: the planner pushes the deadline weights into `app_settings` and
  the settings payload (`frontend/planner_app/lib/core/settings_actions.dart:102-103`,
  `:138-139`, `:186-188`), so in folder mode they land in
  `profile/settings.json`; locale is not in its payload
  (`frontend/planner_app/lib/core/settings_helpers.dart:16-23`) and stays
  per device.

Closed in Phase 2 (2026-10-20, the U3 part of the Phase 0 spike):

- U3: verified in headless Chromium 131 (Playwright build 1148, the
  `nc-lf1a-flutter-chromium:local` image, Flutter 3.44.0). The editor's
  release web build with the Phase 2 wiring and the option (built at
  `ada0555c` plus the option commit; an earlier build gave the same
  result) was served on `http://127.0.0.1:8099` in a `--network none`
  container, so the page was a secure context and the only listeners were
  127.0.0.1:8099 and Chromium's DevTools on 127.0.0.1:9222. A script added
  before the page loaded wrapped `window.showDirectoryPicker` to record
  `navigator.userActivation.isActive` at call time and the promise outcome.
  Trusted DevTools mouse input clicked the real "Use a local folder (no
  account)" button on `#/settings`, twice: once with Flutter semantics on
  (the button's `flt-semantics` node took the click), and once on a fresh
  page load with semantics off (0 `flt-semantics` nodes), which is
  Flutter's pointer path for a mouse user. Both clicks called
  `showDirectoryPicker({id: 'notechondria-folder', mode: 'readwrite'})`
  with `isActive: true`, and both promises rejected with `AbortError`
  ("The user aborted a request."; headless Chromium has no picker UI).
  The control call on the same page, made without a gesture, rejected
  with `SecurityError` ("Must be handling a user gesture to show a file
  picker."), so the browser does enforce activation. The real picker
  dialog on desktop Chrome stays manual check 2 (8.6). Evidence (outside
  the repo): `/tmp/nc_verify/agentb_u3/u3/u3_result.json`, the driver
  `/tmp/nc_verify/agentb_u3/u3_driver.dart`, and screenshots
  `u3_1_before_semantics_click.png` to `u3_4_after_pointer_click.png` in
  the same directory.
- U1, U5, U7, U10, U17, and U18 stay open; they are on the manual check
  list in `docs/TODO.md` ("Deferred from Phase 2").

## 11.2 Sources (checked 2026-10-17)

- MDN browser-compat-data 8.1.6 (2026-10-15), `api/Window.json`,
  `FileSystemHandle.json`, `FileSystemDirectoryHandle.json`,
  `FileSystemFileHandle.json`, `FileSystemObserver.json`,
  `LockManager.json`, `NavigatorUAData.json`, via
  https://unpkg.com/@mdn/browser-compat-data/data.json
- MDN: https://developer.mozilla.org/en-US/docs/Web/API/Window/showDirectoryPicker,
  https://developer.mozilla.org/en-US/docs/Web/API/FileSystemDirectoryHandle/removeEntry,
  https://developer.mozilla.org/en-US/docs/Web/API/FileSystemFileHandle/createWritable,
  https://developer.mozilla.org/en-US/docs/Web/API/FileSystemHandle/isSameEntry,
  https://developer.mozilla.org/en-US/docs/Web/API/Web_Locks_API,
  https://developer.mozilla.org/en-US/docs/Web/Security/Secure_Contexts,
  https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy,
  https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria
- Chrome: https://developer.chrome.com/blog/persistent-permissions-for-the-file-system-access-api
  (three-way prompt, auto-revocation of backgrounded tabs, prompt limit),
  https://developer.chrome.com/docs/capabilities/web-apis/file-system-access
  (restricted folders, Brave behind a flag, permission persistence),
  https://developer.chrome.com/blog/file-system-observer,
  https://developer.chrome.com/release-notes/133,
  https://groups.google.com/a/chromium.org/g/blink-dev/c/6oOaFmia2dc
  (Intent to Ship, desktop 133),
  https://developer.chrome.com/blog/new-in-chrome-video-q1-2025 (Android 132)
- Dart: https://dart.dev/interop/js-interop/package-web (conditional
  imports, mocking, callbacks not zone-bound); `package:web` 1.1.1 API
  pages under https://pub.dev/documentation/web/1.1.1/web/ (including
  `LockManager.request`, `LockGrantedCallback = JSFunction`, and
  `AbortSignal.timeout`);
  https://pub.dev/documentation/http/latest/http/BaseRequest/send.html;
  https://api.dart.dev/stable/dart-async/Zone/bindUnaryCallback.html and
  https://api.dart.dev/stable/dart-async/Zone/bindUnaryCallbackGuarded.html
  (return types).
- Package sources read from the pub.dev archives of the locked versions
  (`frontend/*/pubspec.lock`), checked 2026-10-17:
  - `http` 1.6.0 (https://pub.dev/api/archives/http-1.6.0.tar.gz):
    `lib/src/client.dart:42` (`Client()` returns `zoneClient` first),
    `:167-170` (`zoneClient`), `:219-226` (Flutter zone caveat),
    `:228-232` (`runWithClient`); `lib/src/base_request.dart:141`
    (`send()` creates `Client()`); `lib/http.dart:168` (top-level calls
    create `Client()`); `lib/src/browser_client.dart:59` and `:88`
    (`withCredentials = false` maps to `credentials: 'same-origin'`).
  - `shared_preferences` 2.5.4: `lib/src/shared_preferences_legacy.dart:79-96`
    (`getInstance()` loads once and caches) and `:129` (synchronous
    `getString`).
- Specs: Web Locks, https://w3c.github.io/web-locks/ (section 2.3 modes,
  2.4 note on non-promise callbacks, 2.5 grantable requests, 2.6
  termination on document unload, 4.4 "Resolve waiting with r"); File
  System, https://fs.spec.whatwg.org/ (section 2.2.1: `isSameEntry`
  compares locators and checks no permission).
- GitHub: https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages,
  https://docs.github.com/en/rest/using-the-rest-api/using-cors-and-jsonp-to-make-cross-origin-requests;
  `GET https://api.github.com/users/Trance-0/repos` (`has_pages`).
- Probes run for this document: an `OPTIONS` request to
  `https://api.github.com/user/repos` with `Origin: https://trance-0.github.io`
  returned 204 with `access-control-allow-origin: *` and `Authorization`
  allowed; a `GET` of Google's public US holidays calendar
  (`calendar.google.com/calendar/ical/en.usa%23holiday%40group.v.calendar.google.com/public/basic.ics`)
  returned 200 `text/calendar` with no `Access-Control-Allow-Origin`
  header; `HEAD https://trance-0.github.io/Notechondria/editor/` returned
  200 with no redirect.
- RFC 6761 section 6.4: resolvers SHOULD return NXDOMAIN for `.invalid`
  names. No longer relied on (2.7).
