import 'package:flutter/widgets.dart';

/// Local-store persistence mixin shared across `_AppShellState` in
/// editor / planner / portal. Wraps the per-app `_LocalAppStore`
/// bucket savers behind a single uniform surface so the call-side
/// shape (`persistLocalSettings()`, `persistLocalDrafts()`, …) is
/// identical across apps and the bodies aren't duplicated three
/// times.
///
/// What stays per-app:
///   - `persistLocalCache()` — the cache bucket merges different
///     fields per app (editor includes `front_page` + `courses`;
///     planner adds `activity` / `planner_events` / `activity_week`;
///     portal adds `front_page` + `activity`). It's app-specific so
///     it stays in each app's `core/local_persist.dart` extension.
///   - `_LocalAppStore` itself — the SharedPreferences-backed key
///     scheme is owned by each app and not visible to
///     `notechondria_shared`. The mixin reaches it through the
///     abstract `saveLocalX` adapters below, which each app
///     overrides with a one-liner.
///
/// What this mixin owns:
///   - Five identical bodies — settings, drafts, courses, stats,
///     UI logs — live here once. Each calls the matching abstract
///     `saveLocalX` adapter on the implementing State class.
///
/// Usage in `_AppShellState`:
/// ```dart
/// class _AppShellState extends State<AppShell>
///     with AppShellLocalPersistMixin<AppShell> {
///   @override
///   Map<String, dynamic> get localSettings => _localSettings;
///   @override
///   List<Map<String, dynamic>> get localDrafts => _localDrafts;
///   @override
///   List<Map<String, dynamic>> get localCourses => _localCourses;
///   @override
///   Map<String, dynamic> get localStats => _localStats;
///   @override
///   List<String> get persistedUiLogs => uiLogs;
///
///   @override
///   Future<void> saveLocalSettings(Map<String, dynamic> v) =>
///       _LocalAppStore.saveSettings(v);
///   // … and the four other one-line save adapters.
/// }
/// ```
mixin AppShellLocalPersistMixin<W extends StatefulWidget> on State<W> {
  // Read-side: the in-memory state the mixin persists. Each app's
  // `_AppShellState` exposes its private `_localX` fields through
  // these public getters.
  Map<String, dynamic> get localSettings;
  List<Map<String, dynamic>> get localDrafts;
  List<Map<String, dynamic>> get localCourses;
  Map<String, dynamic> get localStats;

  /// Read-only view of the UI log buffer for `persistUiLogs()`.
  /// Named distinctly from `AppShellLogMixin.uiLogs` so apps that
  /// mix in both don't collide on the override.
  List<String> get persistedUiLogs;

  // Write-side adapters: each app implements these as one-liners
  // pointing at its own `_LocalAppStore.saveX(value)` static call.
  Future<void> saveLocalSettings(Map<String, dynamic> value);
  Future<void> saveLocalDrafts(List<Map<String, dynamic>> value);
  Future<void> saveLocalCourses(List<Map<String, dynamic>> value);
  Future<void> saveLocalStats(Map<String, dynamic> value);
  Future<void> saveLocalLogs(List<String> value);

  /// Persist the in-memory `localSettings` map to durable storage.
  /// Fire-and-forget at most call sites; await it when ordering
  /// matters (e.g. before reading the value from a fresh
  /// SharedPreferences in tests).
  Future<void> persistLocalSettings() => saveLocalSettings(localSettings);

  /// Persist the in-memory `localDrafts` list. Called whenever the
  /// list is mutated — sync, edit, delete, restore.
  Future<void> persistLocalDrafts() => saveLocalDrafts(localDrafts);

  /// Persist the in-memory `localCourses` list. Called on category
  /// create / rename / delete / reorder for the offline mirror.
  Future<void> persistLocalCourses() => saveLocalCourses(localCourses);

  /// Persist the in-memory `localStats` map (counters: avatar
  /// updates, draft saves, starter-workspace seed timestamp, …).
  Future<void> persistLocalStats() => saveLocalStats(localStats);

  /// Persist the UI log ring buffer. `AppShellLogMixin` calls this
  /// fire-and-forget after every `log()` append, so the debug
  /// terminal survives app restarts.
  Future<void> persistUiLogs() => saveLocalLogs(persistedUiLogs);
}
