# `notechondria_shared` package

Path: [`frontend/notechondria_shared/`](../../frontend/notechondria_shared/).
Purpose: shared Dart/Flutter code consumed by all three frontend apps
(editor / planner / portal). Ships as a path-dependency package so
the three `pubspec.yaml` files import it directly from the repo
without publishing to pub.dev.

Related: [editor_app](editor_app.md), [planner_app](planner_app.md),
[portal_app](portal_app.md), [server/backend.md](../server/backend.md).

## Why this exists

The three Flutter apps used to carry 63+ byte-identical methods each
across their `app_shell.dart` files. 0.1.52/0.1.53 codified the
1000-LOC hard ceiling per file and started peeling those duplicates
up into a shared library; 0.1.65+ added the multi-device session
client surface here so the UI can be built once, not three times.
The cross-app de-dup work landed in 0.1.78–0.1.82 (eight shared
mixins under `notechondria_shared/lib/src/app_shell/`); see
[`docs/versions/0.1.82.md`](../versions/0.1.82.md) and the
adjacent rounds for per-mixin details.

## Layout

```text
frontend/notechondria_shared/
├── pubspec.yaml                     ← path-dep'd by each app
└── lib/
    ├── notechondria_shared.dart     ← public export barrel
    └── src/
        ├── app_shell/               ← State mixins used by
        │   │                          _AppShellState in all 3 apps
        │   ├── app_shell_log_mixin.dart
        │   ├── app_shell_auth_actions_mixin.dart
        │   ├── app_shell_oauth_mixin.dart
        │   ├── auth_client.dart           ← abstract AuthClient
        │   ├── url_strategy.dart          ← non-web no-op stub
        │   └── url_strategy_web.dart      ← dart:html impl
        ├── components/               ← Widget-layer UI primitives
        │   ├── auth_dialogs.dart
        │   ├── auth_dialogs_wizard.dart
        │   ├── debug_log.dart
        │   ├── debug_widgets.dart
        │   ├── error_state.dart
        │   ├── navigation.dart
        │   ├── phased_status.dart
        │   └── splash_screen.dart
        ├── models/
        │   ├── action_feedback.dart
        │   └── api_debug_snapshot.dart
        ├── settings/
        │   └── app_preferences_card.dart
        └── utils/
            ├── blur_dialog.dart
            ├── compact_timestamp.dart
            ├── local_archive.dart
            ├── local_attachment_store.dart
            ├── local_attachment_store_io.dart
            ├── local_attachment_store_web.dart
            └── ping_backend.dart
```

## `src/app_shell/` — state mixins

Mixins on `State<StatefulWidget>` with abstract getters for the
handful of fields each concern needs. The apps compose them onto
their `_AppShellState` to keep per-app `app_shell.dart` under the
1000-LOC cap.

| Mixin / file | Role |
| --- | --- |
| `AppShellLogMixin` (`app_shell_log_mixin.dart`) | UI log ring (`uiLogs`, `logController`), `log`, `appendUiLog`, `timed<T>`, `refreshState`, `showMessage`. |
| `AppShellAuthActionsMixin` (`app_shell_auth_actions_mixin.dart`) | Password-based auth callbacks: `register`, `verify`, `resendVerification`, `login`, `requestPasswordReset`, `confirmPasswordReset`. Abstract getter `logAppTag` supplies the `Editor.` / `Planner.` / `Portal.` prefix. |
| `AppShellOAuthMixin` (`app_shell_oauth_mixin.dart`) | Web-only `launchOAuth` + `handleOAuthCallback`. 0.1.67 change: `handleOAuthCallback` preserves the URL fragment when cleaning the query (so note deep-links survive an OAuth round-trip). |

`auth_client.dart` declares the abstract `AuthClient` interface
every per-app `HttpNotechondriaClient` implements: `register`,
`login`, `checkSession`, `listSessions`, `revokeSession`, `logout`,
`getSettings`, `updateSettings`, OAuth flows, etc. Session
management methods (`listSessions` / `revokeSession`) were added
in 0.1.67 to consume the 0.1.65 backend endpoints — see
[server/creators.md](../server/creators.md#active-sessions-multi-device--new-in-0165).

`url_strategy.dart` + `url_strategy_web.dart` provide
`browserPushState` / `browserReplaceState` via a conditional
import so non-web builds compile. The fragment-preservation fix
in 0.1.67 relies on this pair.

## `src/components/` — UI primitives

| File | Public widget(s) | Notes |
| --- | --- | --- |
| `auth_dialogs.dart` | `AuthHub`, `EmailPasswordDialog`, `EmailCodeDialog`, `PasswordResetDialog` | 0.1.66 dropped the "Verify email" button from `AuthHub` (verification lives inside the signup wizard now) and moved "Forgot password" into `EmailPasswordDialog`'s action row. 0.1.66 also added a `Cancel` affordance that stays enabled during a slow submit. `EmailPasswordDialog` shows `Signing in to <host>` as the subtitle when given an `apiBaseUrl`. |
| `auth_dialogs_wizard.dart` | `RegistrationWizard` | Multi-step signup flow (invitation-code → email+password → verify). |
| `debug_log.dart`, `debug_widgets.dart` | `DebugLogCard`, `ApiDebugCard` | Debug drawer surfaces on the Settings surface. |
| `error_state.dart` | `ErrorStatePanel` | "Something went wrong" screen with API base URL context. |
| `load_error_banner.dart` | `LoadErrorBanner` | Since 0.1.198: the connection / load-error bar shared by all three shells (was three copies). Renders the raw error through `friendlyError` (localized AGENTS.md §1.8 text) with Work offline / Retry / Dismiss. |
| `startup_failure_view.dart` | `StartupFailureView` | Since 0.1.198: full-page fallback when a startup step throws, with the §1.8 cause, Retry, "Copy message" (0.1.199), and an optional "Continue anyway". |
| `copyable_feedback.dart` | `CopyMessageButton`, `copyMessageToClipboard`, `showCopyableSnackBar` | Since 0.1.199. Messages must be selectable and copyable, and a page-level `SelectionArea` reaches neither SnackBars (painted by the ScaffoldMessenger) nor dialogs (separate routes). `CopyMessageButton` is an icon button with the tooltip / semantic label "Copy message" that copies the full text and switches to "Message copied to clipboard." (or the `Shared.Feedback/copy` failure). `showCopyableSnackBar` shows the text with a Copy action and a close icon (`persist: false`, 6s, 10s for errors). Message text uses the package-internal `SelectableMessageText`: a `SelectableText` whose words are given to the semantics tree as a label, because on web a bare `SelectableText` is an empty read-only text field to screen readers. Used by `showMessage` (every app's SnackBar helper), `FeedbackText` (inline dialog / form feedback), `ConfirmWithDelayDialog` (Copy action), `LoadErrorBanner` (copies the friendly text plus the raw cause), `StartupFailureView`, and the OAuth mixin's sign-in errors. |
| `wide_course_sidebar_section.dart` | `WideCourseSidebarSection` | Collapsible "Courses" list in the planner / portal wide sidebar (moved here from two identical private copies in 0.1.198). |
| `navigation.dart` | Navigation rail / bottom-bar helpers. |
| `phased_status.dart` | `PhasedStatusIndicator` — replaces a bare spinner with a labelled "Sending request to backend → Waiting for backend response → Applying response" line. Used by `EmailPasswordDialog._submit`. |
| `splash_screen.dart` | `SplashScreen` | 0.1.199: the status line accepts `'<label>: <Module>/<process>'` (localizes the label, keeps the step name), and on web the header skips its intro fade so the first frame matches each app's `#nc-boot` HTML header (one loading screen at the handoff). Splash screen backed by `src/reaction_simulator/` since 0.1.128 — a Dart port of the owner's `index` repo reaction simulator (TCA-cycle particles colliding and reacting on a toroidal world; hardcoded 128-particle target, spawn energy ~ N(250000, 60000)). Replaced the hand-drawn `splash_painter.dart` Krebs-cycle painter (deleted). |

## `src/startup/` — startup resilience (since 0.1.198)

- **`startup_budget.dart`** — `StartupRequestBudget` and
  `runWithStartupBudget`. Each app runs its cold start, the load-error
  banner's Retry, and its Work offline inside a budget. The budget travels
  as a zone value and `HttpClientInternalsMixin.send` enforces it: every
  request is capped at `kBackendStartupTimeout` (10s), and after the first
  timeout the rest of the pass fails fast with a `BackendStartupTimeout`.
  `friendlyError` renders that as the localized "did not respond within 10s"
  message. Requests made after the pass keep their previous unbounded
  behavior. Known gap: because the budget is a zone value, fire-and-forget
  work started inside the pass (portal's post-OAuth cloud pull, editor's
  legacy-Inbox migration) inherits the 10s cap and the fail-fast flag
  (tracked in [`../TODO.md`](../TODO.md)).
- **Where the fallbacks show up.** The backend-unavailable result is the
  shared `LoadErrorBanner` over local data, with Work offline and Retry. A
  startup step that throws shows `StartupFailureView` (Retry, Continue
  anyway). Before Flutter paints, each app's `web/index.html` shows a
  `#nc-boot` loading surface (since 0.1.199 a static copy of the splash
  header with no spinner, so only one loading screen shows); it turns into
  a failure message with Reload
  when the bootstrap script fails to download, the loader throws, or no
  frame appears within 20s.
- **`startup_log.dart`** (0.1.199) — `describeRequestFailure(error)` turns
  a failed request or step into a specific cause: `timeout after 10s
  (server did not respond)`, `skipped: an earlier startup request timed out
  after 10s`, `connection refused`, `DNS lookup failed`, `TLS handshake
  failed`, `connection reset before a response`, the browser's opaque
  `network error with no readable response (...)`, `HTML instead of JSON
  (HTTP 502)`, or the error's first line. It drops URL query strings and
  redacts `Token` / `Bearer` values. `StartupOutcome` is the
  `(level, message)` record a step reports.
- **`AppShellLogMixin.startupStep`** (0.1.199) — each app's
  `core/bootstrap.dart` runs every cold-start step through it:
  `local_state`, `config`, `handshake`, `session_restore`,
  `oauth_callback`, `initial_data` (source `<App>.Startup/<step>`). It logs
  a DEBUG "started" line and the outcome with its duration, or on a throw
  `<consequence>: <App>.Startup/<step> — <cause>` before rethrowing, and
  sets the splash status to `'<label>: <App>.Startup/<step>'`. The
  `initial_data` outcome is a WARNING `Startup finished on local data
  only: ...` when the load fell back to local data. Each app's
  `_loadLocalState` merges the startup lines with the stored log right
  after the store load (and `_handleBootstrapFailure` does it when that
  load throws), so a failed start still persists its records. The
  handshake now goes through `HttpClientInternalsMixin.send`, so it is
  logged and bounded by the startup budget; its result also answers the
  version banner's first probe. `send` logs failures as `HTTP request
  failed: <App>.HTTP/request_failed — GET <host><path> after <n>ms:
  <cause>.`, startup requests of 3s or more as `<App>.HTTP/slow`, and a
  non-JSON body as `Server response not usable: <App>.HTTP/response —
  expected JSON from ... but received HTML (HTTP <n>, <type>, <n>B) ...`.
  Logs never carry tokens, cookies, or profile data.
- **`startup_guard.dart`** — `runGuardedApp` (used by every `main.dart`)
  wraps `runApp` in `runZonedGuarded`, chains `FlutterError.onError` and
  `PlatformDispatcher.instance.onError`, and installs `StartupErrorWidget` as
  a non-blank `ErrorWidget.builder`. An uncaught error before the first frame
  shows `StartupFailureApp`; later ones are only logged, because the shell's
  own fallbacks are on screen by then.
- **`components/version_update_banner.dart`** (related, not startup) —
  `VersionUpdateBanner` compares the build's `APP_VERSION` with the
  handshake `version`: backend newer shows "A new version is available",
  backend older shows "rolling out", below `min_frontend_version` shows
  "no longer supported". Every build path must pass `APP_VERSION`, or the
  `0.1.21` code default triggers a false update banner (see
  [`../development/local_dev.md`](../development/local_dev.md#version-stamping-and-the-version-banner)).

## `src/models/`

- **`ActionFeedback`** — `{bool isError, String message, String? source}`, returned by every user-triggered action (login, save, revoke, etc.) so the app shell can surface a typed result without a string-typing protocol.
- **`ApiDebugSnapshot`** — captured per HTTP round-trip: `method`, `path`, `status`, `durationMs`, `bodyPreview`, `source`. Fed into `DebugLogCard` for per-request visibility.

## `src/settings/`

- **`AppPreferencesCard`** — shared Settings card showing editor-mode / theme-preset / theme-mode dropdowns, an `extrasBuilder` slot for per-app fields (planner uses it for deadline-weight sliders), and the API base URL `TextField` with the "locked while signed in" tooltip from 0.1.66 and the "Include the `/api/v1` suffix" default hint from 0.1.66. Host apps pass in their `localSettings` mutation callbacks; the card doesn't persist anything itself.

## `src/utils/`

| File | Purpose |
| --- | --- |
| `blur_dialog.dart` | `showBlurDialog<T>()` — drop-in replacement for `showDialog` that blurs the underlying scaffold. Consumers: auth dialogs, identity-code prompts. |
| `compact_timestamp.dart` | "2 min ago" / "yesterday" / "Jan 14" formatting for the sessions list, note cards, etc. |
| `local_archive.dart` | Zip-based export / import of a workspace snapshot. Shared across apps so planner and portal can import what editor exported. |
| `local_attachment_store.dart` + `_io.dart` + `_web.dart` | Conditional-import attachment blob store. IO backend writes to `path_provider` app-docs; web backend is in-memory today (IndexedDB persistence tracked in TODO). Used by the 0.1.40+ attachment-CDN work so notes can carry image/file references without sending them to the backend. |
| `ical_events.dart` | `parseIcalEvents(raw)` (0.1.199): on-device RFC 5545 VEVENT reader for the planner's offline import. Unfolds lines, reads only VEVENT-level properties (not nested VALARM), unescapes text, handles UTC / all-day / floating and `TZID=` (as device-local) times, defaults DTEND to +1h or +1 day, counts events without a readable DTSTART as skipped, and returns `IcalParseResult(calendarName, events, skipped)`. No RRULE expansion. |
| `ping_backend.dart` | `HttpNotechondriaClient.verifyHandshake` helper — probes `GET /handshake/` on a candidate base URL before Settings commits a new one (0.1.17 design). |

## `src/notechondria_shared.dart` — export barrel

The single public entry point each app imports:

```dart
// frontend/editor_app/lib/main.dart
import 'package:notechondria_shared/notechondria_shared.dart';
```

Everything in `src/` that should be consumable from outside the
package is re-exported from this barrel. Adding a new shared
symbol: add the file under `src/<category>/` and append an
`export 'src/<category>/<file>.dart' show <Symbol>;` line in the
barrel. Keep the `show` list tight to avoid accidental public
surface creep.

## Dependencies

`frontend/notechondria_shared/pubspec.yaml`:

- `flutter` SDK (Material + Cupertino).
- `http` — HTTP client surface for the `AuthClient` + per-app
  implementations to consume.
- `shared_preferences` — the local settings / session blobs.
- `file_selector` — `local_archive` import/export file picking.
- `path_provider` — attachment store filesystem roots.
- `archive` — zip read/write for `local_archive`.

These are the union of what all three apps needed. No per-app
dependency leaks upward into this package, and no third-party
UI kit — everything is plain Flutter so the three apps can style
consistently from their own `ThemeData`.

## Consuming the package

Each app's `pubspec.yaml`:

```yaml
dependencies:
  notechondria_shared:
    path: ../notechondria_shared
```

Because it's a path-dep, edits to shared code take effect on the
next `flutter pub get` + hot-restart in the consuming app. The
smoke tests per app cover enough of the shared surface that
regressions surface quickly.

## When to add new shared code

Follow the migration TODO heuristic: **if three apps have a
byte-identical method, extract it.** If two apps share it and the
third has a small divergence, keep it per-app and note the
divergence in the owning file's header comment. Do not over-
generalize — a mixin with 6 abstract getters for 3 concrete call
sites is worse than copying three methods.
