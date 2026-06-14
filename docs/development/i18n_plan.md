# Internationalization (i18n) plan

Plan + architecture for adding multi-language support to the three
Flutter apps (editor / planner / portal) and the shared
`notechondria_shared` package. Written at 0.1.132.

**Goal.** Ship English (US) and Chinese (Simplified) with:

- a **Language** setting in each app, built from a shared widget;
- **system-language detection** as the first-run default;
- a structure that scales to more languages and is delivered over
  **multiple versions** (phased — see §6).

## 1. Current state

There is **no** localization anywhere today (verified across all four
packages):

- No `flutter_localizations` / `intl` dependency, no
  `flutter: generate: true`, no `l10n.yaml`, no `.arb` files, no
  `AppLocalizations`.
- Each app's `MaterialApp` (in `lib/app_shell.dart`) has no
  `localizationsDelegates` / `supportedLocales` / `locale`.
- Roughly **~370 user-facing hardcoded strings** across the apps
  (editor ~134, portal ~115, planner ~84, shared ~41), densest in the
  settings pages, dialogs, and the shared components.

## 2. Architecture decision

### 2.1 One shared generated catalog (not per-app)

The three apps were split from a monolith and share `notechondria_shared`
for every cross-cutting widget (auth dialogs, onboarding tour, what's-new
overlay, install banner, debug log, settings card, splash). Those shared
widgets contain user-facing strings, so the **localization catalog must
live in the shared package** — duplicating ARBs per app would mean three
copies of every shared string.

**Decision: run `gen-l10n` inside `notechondria_shared` with
`synthetic-package: false`, output into the package's `lib/`, and export
the generated `AppLocalizations` from the package barrel.** Each app adds
the shared delegate to its `MaterialApp`. This gives a single ARB catalog
and a single generated `AppLocalizations` consumed by all three apps and
the shared widgets.

Why not the default synthetic package (`package:flutter_gen/...`)? That
output is app-scoped and not importable from a shared package, which is
exactly the sharing we need. `synthetic-package: false` writes real
Dart into the package `lib/` that can be exported.

`notechondria_shared/l10n.yaml` (target):

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/src/l10n
output-class: AppLocalizations
synthetic-package: false
nullable-getter: false
```

Catalog files: `lib/l10n/app_en.arb` (template, English US) and
`lib/l10n/app_zh.arb` (Chinese Simplified). Generated Dart under
`lib/src/l10n/` is committed (so apps build without a generation step in
CI) and re-generated with `flutter gen-l10n` in the shared package when
strings change. The barrel exports `AppLocalizations`.

### 2.2 Per-app MaterialApp wiring

Each app adds to its `MaterialApp`:

```dart
localizationsDelegates: const [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
supportedLocales: AppLocalizations.supportedLocales, // en, zh
locale: _resolvedLocale,   // null => follow device; or Locale('zh')
```

`flutter_localizations` (SDK) + `intl` are added to each app's
`pubspec.yaml`; `intl` is added to the shared package.

### 2.3 Accessing strings

Widgets read `AppLocalizations.of(context)!.someKey`. Shared widgets
already receive a `BuildContext`, so they localize the same way. A few
strings are produced outside a widget context (e.g. some
`local_starter` seed text, log lines) — those either keep an English
default or take the localized string as a parameter from the caller
that does have a context. Seed/welcome content is data, not chrome;
phase it last (§6).

## 3. The Language preference: persistence + propagation

A `locale` preference mirrors the existing `theme_preset` / `theme_mode`
flow exactly — **no backend schema change** (the `Creator.app_settings`
JSON blob is free-form):

1. Stored in `app_settings` under key `locale`, value one of
   `system` | `en` | `zh` (sentinel `system` = follow the device).
2. `defaultSettings()` in each app's `core/local_store.dart` seeds
   `'locale': 'system'`.
3. Included in the settings payload (`core/settings_helpers.dart`)
   so it round-trips to the backend via `PATCH /api/v1/settings/`
   alongside theme, and reconciles on login like the other app settings.
4. A change fires an `onLocaleChanged(String locale)` callback (added
   next to the existing `onThemeChanged`), which `setState`s the
   top-level app state and rebuilds `MaterialApp` with the new `locale`.

Resolution helper (shared): map the stored value to a `Locale?`:

```dart
Locale? resolveLocale(String stored) {
  switch (stored) {
    case 'en': return const Locale('en');
    case 'zh': return const Locale('zh');
    default:   return null; // 'system' => MaterialApp follows device
  }
}
```

When `locale` is null, `MaterialApp` uses the device locale clamped to
`supportedLocales` (Flutter falls back to the first supported locale —
English — for unsupported device languages). That gives the
system-default behavior for free.

## 4. System-language detection (first run)

On a fresh install the stored value is `system`, so `MaterialApp`
already follows the device. If we ever need the *resolved* language for
non-MaterialApp text, read it explicitly at boot:

```dart
final device = WidgetsBinding.instance.platformDispatcher.locale;
final isZh = device.languageCode.toLowerCase() == 'zh';
```

No write-back is needed for the `system` sentinel — it stays `system`
until the user picks an explicit language, at which point their choice
persists and overrides the device.

## 5. The Language setting UI (shared widget)

Add a **Language** dropdown to the shared
`notechondria_shared/lib/src/settings/app_preferences_card.dart`
(System / English / 简体中文), gated by an optional
`onLocaleChanged` + `currentLocale` pair (null hides the row — same
pattern as the card's existing `onReplayTour`). Planner uses
`AppPreferencesCard` directly, so it gets the row by passing the
callback. **Editor and portal hand-roll their settings** (they don't
use `AppPreferencesCard`), so each needs the dropdown added to its own
preferences subpage and wired to its `onLocaleChanged` — note this
divergence; it is the same divergence the theme dropdowns already
live with.

## 6. Phasing (multiple versions)

Each phase is independently shippable.

- **Phase 1 — scaffold + editor.** Add deps, the shared ARB catalog +
  `l10n.yaml` + generated `AppLocalizations`, MaterialApp wiring in all
  three apps, the `locale` preference (persist + propagate + system
  default), the Language dropdown (shared card + editor's hand-rolled
  settings), and translate the **editor** app's user-facing strings +
  the shared widgets it uses. Other apps keep working (English) because
  they share the same catalog and any missing key falls back to the
  template.
- **Phase 2 — planner strings.** Translate planner-specific UI; add the
  Language dropdown to planner via `AppPreferencesCard`.
- **Phase 3 — portal strings.** Translate portal-specific UI + its
  hand-rolled Language dropdown.
- **Phase 4 — shared-widget + dialog sweep.** Audit every shared
  component (auth dialogs, onboarding tour, what's-new, install banner,
  debug log, error state, mcp skill section) and the SnackBar/dialog
  strings across all apps for full coverage; localize seed/welcome
  content if desired.

## 7. String policy (AGENTS.md §1.8 interaction)

§1.8 requires diagnostic/log messages of shape
`"<consequence>: <module>/<process> — <cause>"` and that those stay
**stable and greppable**.

- **Log lines, `DebugLogEntry`, thrown exception messages, telemetry:**
  keep **English** and unchanged — they are operator-facing and must
  stay greppable. Do not localize.
- **User-facing toasts / dialogs / banners:** localize the
  **consequence** sentence (what the user can no longer do) and keep
  the `module/process` token English inside the string so a pasted
  screenshot is still greppable. In practice this means the ARB value
  carries the user-readable part and the code appends the stable
  `Module/process` token, or the §1.8 string is split into a localized
  prefix + an English code suffix. Decide per call site during the
  sweep; default to "localize the human sentence, keep the code token".

## 8. Risks / notes

- **Volume.** ~370 strings is a multi-phase effort; that is why editor
  goes first and the catalog is shared (planner/portal inherit common
  strings for free).
- **`intl` plurals/selects.** Use ARB `plural`/`select` for counts
  ("1 note" / "N notes") rather than string concatenation.
- **Committed generated code.** The generated `app_localizations*.dart`
  is committed so app builds don't require a generation step; regenerate
  in the shared package whenever ARBs change and commit the result.
- **Chinese line metrics.** zh glyphs are wider; spot-check the splash,
  onboarding cards, and settings rows at narrow (mobile) widths after
  translating.
- **No backend work.** Everything rides the existing `app_settings`
  JSON; no migration, no new endpoint.
