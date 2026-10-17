import 'dart:async';

import 'package:flutter/material.dart';

import '../components/copyable_feedback.dart';
import '../components/debug_log.dart';
import '../startup/startup_log.dart';

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
  /// action that needs to surface a snackbar-level message. The text is
  /// selectable and the SnackBar has a Copy action (0.1.199), so every
  /// message raised through here can be pasted back verbatim.
  void showMessage(String message) {
    if (!mounted) return;
    showCopyableSnackBar(context, message);
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

  /// Runs one cold-start step and writes structured startup records
  /// (0.1.199): a DEBUG "started" line, then the outcome line with its
  /// duration. [source] is the step's `<App>.Startup/<process>`.
  ///
  /// When [label] is set (an existing splash key such as `Connecting to
  /// server`) and [status] is the splash notifier, the splash shows
  /// `'<label>: <source>'`, i.e. the localized label plus the step name.
  /// On success the outcome line is [outcome]'s record, or a DEBUG
  /// "finished" line. On a throw it logs ERROR `<failureConsequence>:
  /// <source> — <cause>` (cause from `describeRequestFailure`, so no
  /// token or query string is logged) and rethrows, so the caller's
  /// fallback (startup failure view, banner) still runs.
  Future<T> startupStep<T>(
    String source,
    Future<T> Function() body, {
    ValueNotifier<String>? status,
    String? label,
    StartupOutcome Function(T value)? outcome,
    String failureConsequence = 'Startup step failed',
  }) async {
    if (label != null && status != null) status.value = '$label: $source';
    log(
      source: source,
      level: DebugLogLevel.debug,
      message: 'Startup step started: $source \u2014 '
          '${label ?? 'running'}.',
    );
    final start = DateTime.now();
    try {
      final value = await body();
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final result = outcome?.call(value) ??
          (
            level: DebugLogLevel.debug,
            message: 'Startup step finished: $source \u2014 done.',
          );
      log(
        source: source,
        level: result.level,
        message: result.message,
        durationMs: elapsed,
      );
      return value;
    } catch (error) {
      log(
        source: source,
        level: DebugLogLevel.error,
        message: '$failureConsequence: $source \u2014 '
            '${describeRequestFailure(error)}.',
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      rethrow;
    }
  }

  /// Wraps a backend call so its duration is recorded in the debug
  /// log at DEBUG level. Re-throws after emitting the failure line so
  /// callers can still branch on the error. Inside a startup pass the
  /// call is also bounded by the pass's `StartupRequestBudget` (enforced
  /// in the HTTP layer), so a failure here can be a startup timeout.
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
        message: 'Backend call failed \u2014 '
            '${error.toString().replaceFirst("Exception: ", "")}',
        level: DebugLogLevel.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      rethrow;
    }
  }
}
