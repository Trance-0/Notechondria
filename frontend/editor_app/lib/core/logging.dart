part of notechondria_frontend;

/// Debug-log emitters used by every other module. Each log line is pushed
/// into `DebugLogController` (the in-app terminal) and a 80-entry ring
/// buffer `_uiLogs` that persists across restarts. `_timed<T>` is the
/// sugar that records backend round-trip durations. Extracted from
/// `app_shell.dart` so that file stays closer to the AGENTS.md §1.5
/// 1000-line ceiling.
extension _AppShellLoggingX on _AppShellState {
  void _appendUiLog(String message) {
    _log(message: message, level: DebugLogLevel.info, source: '');
  }

  /// Richer variant of `_appendUiLog`. `source` is typically
  /// `"ClassName._method"` and shows up in the debug log card next to the
  /// level badge. `durationMs` is set for timed backend operations.
  void _log({
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
    _logController.append(entry);
    _uiLogs.insert(0, entry.toPersistedString());
    if (_uiLogs.length > 80) {
      _uiLogs.removeRange(80, _uiLogs.length);
    }
    _refresh();
    unawaited(_persistUiLogs());
  }

  /// Wraps a backend call so its duration is recorded in the debug log at
  /// Debug level. Re-throws after emitting the failure line.
  Future<T> _timed<T>(String source, Future<T> Function() op) async {
    final start = DateTime.now();
    try {
      final result = await op();
      _log(
        source: source,
        message: 'ok',
        level: DebugLogLevel.debug,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      return result;
    } catch (error) {
      _log(
        source: source,
        message: 'failed: ${error.toString().replaceFirst("Exception: ", "")}',
        level: DebugLogLevel.error,
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      rethrow;
    }
  }
}
