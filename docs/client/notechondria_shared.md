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
Remaining de-dup work is tracked in the "File-size rule + cross-app
sharing" entry in [`docs/TODO.md`](../TODO.md).

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
        │   ├── splash_painter.dart
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
| `navigation.dart` | Navigation rail / bottom-bar helpers. |
| `phased_status.dart` | `PhasedStatusIndicator` — replaces a bare spinner with a labelled "Sending request to backend → Waiting for backend response → Applying response" line. Used by `EmailPasswordDialog._submit`. |
| `splash_painter.dart`, `splash_screen.dart` | `_SplashScreen`, `_KrebsCyclePainter`, `SplashParticle` | Krebs-cycle animated splash. 0.1.66 unified particle sizes (byproducts + Acetyl-CoA wrapped in `canvas.scale(0.5)` so every splash particle shares a final pixel size); 0.1.67 removed the outer `activePos.dx > -30` gate so narrow (mobile) layouts no longer show a blank moment when the active node slips off the left edge. |

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
