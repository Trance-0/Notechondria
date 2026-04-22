import 'dart:async';

import 'package:flutter/material.dart';

import '../components/debug_log.dart';

/// Debug-log mixin shared across `_AppShellState` in editor / planner /
/// portal apps. Owns the `uiLogs` ring buffer + the `DebugLogController`
/// that feeds the in-app terminal, and exposes the two emitters
/// (`appendUiLog`, `log`) plus the timing sugar `timed<T>` every other
/// shared mixin depends on.
///
/// The 80-entry ring buffer cap mirrors the editor/planner/portal
/// convention — one commit worth of scroll, not a log file. Persistence
/// is deferred to `persistUiLogs()` which each app implements against
/// its own `_LocalAppStore` bucket (so the logs end up in the same
/// `SharedPreferences` blob as the rest of the app state, not a
/// parallel key).
///
/// Auto-rebuilds the debug-log card via `refreshState()` after each
/// append so the terminal scrolls with new lines without the caller
/// having to hand-roll a `setState`.
///
/// Usage:
///   class _AppShellState extends State<AppShell>
///       with AppShellLogMixin<AppShell> {
///     @override
///     final List<String> uiLogs = <String>[];
///     @override
///     final DebugLogController logController = DebugLogController();
///     @override
///     Future<void> persistUiLogs() =>
///         _LocalAppStore.saveLogs(uiLogs);
///   }
mixin AppShellLogMixin<W extends StatefulWidget> on State<W> {
  /// Persisted log ring buffer. Must be a mutable list so `log` can
  /// `insert`/`removeRange` in place. Typically declared as
  /// `final List<String> uiLogs = <String>[]` on the subclass.
  List<String> get uiLogs;

  /// Controller feeding the in-app `DebugLogCard` terminal. Created
  /// once on the subclass and disposed in `dispose()`.
  DebugLogController get logController;

  /// Maximum number of entries retained in `uiLogs`. Default 80 —
  /// enough to cover one sync cycle's worth of DEBUG traffic without
  /// ballooning `SharedPreferences`.
  int get uiLogCapacity => 80;

  /// Persists the current `uiLogs` buffer. Called fire-and-forget
  /// after every `log()` append. Typical implementation delegates to
  /// the app's local store, e.g. `_LocalAppStore.saveLogs(uiLogs)`.
  Future<void> persistUiLogs();

  /// Triggers a rebuild. Extensions / mixins can't call the protected
  /// `setState` directly, so every mutating method routes through this.
  void refreshState() {
    if (mounted) setState(() {});
  }

  /// Convenience `ScaffoldMessenger` wrapper. Shared across every
  /// action that needs to surface a snackbar-level message.
  void showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Info-level log line with an empty source tag. Handed as a
  /// callback to dialogs and widgets that don't care about source
  /// metadata.
  void appendUiLog(String message) {
    log(message: message, level: DebugLogLevel.info, source: '');
  }

  /// Richer log emitter. `source` is typically `"ClassName._method"`
  /// and shows up in the debug-log card next to the level badge;
  /// `durationMs` is set for timed backend operations.
  void log({
    required String message,
    DebugLogLevel level = DebugLogLevel.debug,
    String source = '',
    int? durationMs,
  }) {
    final entry = DebugLogEntry(
      timestamp: DateTime.now().toUtc(),
      level: level,
      source: source,
      message: message,
      durationMs: durationMs,
    );
    logController.append(entry);
    uiLogs.insert(0, entry.toPersistedString());
    if (uiLogs.length > uiLogCapacity) {
      uiLogs.removeRange(uiLogCapacity, uiLogs.length);
    }
    refreshState();
    unawaited(persistUiLogs());
  }

  /// Wraps a backend call so its duration is recorded in the debug
  /// log at DEBUG level. Re-throws after emitting the failure line so
  /// callers can still branch on the error.
  Future<T> timed<T>(String source, Future<T> Function() op) async {
    final start = DateTime.now();
    try {
      final result = await op();
      log(
        source: source,
        message: 'ok',
        level: DebugLogLevel.debug,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      return result;
    } catch (error) {
      log(
        source: source,
        message: 'failed: ${error.toString().replaceFirst("Exception: ", "")}',
        level: DebugLogLevel.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      rethrow;
    }
  }
}
