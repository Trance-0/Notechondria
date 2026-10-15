import 'dart:async';

/// Upper bound for a single backend request made while an app starts
/// (session restore, OAuth exchange, initial data load) or while the
/// backend-unavailable banner retries that work.
const Duration kBackendStartupTimeout = Duration(seconds: 10);

/// A startup backend request did not answer within its bound, or was
/// skipped because an earlier request in the same startup pass already
/// timed out.
///
/// [toString] is the AGENTS.md §1.8 shaped message that lands in the
/// app's error list and debug log; `friendlyError` recognizes it through
/// [tryParse] and renders the localized backend-unavailable sentence.
class BackendStartupTimeout implements Exception {
  const BackendStartupTimeout({
    required this.source,
    required this.request,
    required this.timeout,
    this.skipped = false,
  });

  /// Module/process of the startup pass, e.g. `Portal.Startup/bootstrap`.
  final String source;

  /// The abandoned request, e.g. `GET /api/v1/front-page/`.
  final String request;
  final Duration timeout;

  /// True when the request was never sent because an earlier request in
  /// the same pass had already timed out (fail fast instead of paying the
  /// timeout once per request).
  final bool skipped;

  static final RegExp _pattern = RegExp(
    r'^Cloud data not loaded: (\S+) \u2014 server did not respond within '
    r'(\d+)s',
  );

  /// Recovers [source] and the timeout from a [toString] value (the app
  /// shells keep startup errors as strings). Returns null for any other
  /// message.
  static ({String source, int seconds})? tryParse(String message) {
    final match = _pattern.firstMatch(message.trim());
    if (match == null) return null;
    return (source: match.group(1)!, seconds: int.parse(match.group(2)!));
  }

  @override
  String toString() {
    final seconds = timeout.inSeconds;
    return skipped
        ? 'Cloud data not loaded: $source \u2014 server did not respond '
            'within ${seconds}s earlier in this startup, so $request was '
            'skipped (request timed out).'
        : 'Cloud data not loaded: $source \u2014 server did not respond '
            'within ${seconds}s to $request (request timed out).';
  }
}

/// Shares one timeout across every backend request of a single startup
/// pass. The first request that exceeds [timeout] trips the budget, and
/// every later request in the pass fails immediately with a skipped
/// [BackendStartupTimeout], so an unresponsive server costs one
/// [timeout] in total instead of one per request.
class StartupRequestBudget {
  StartupRequestBudget({
    required this.source,
    this.timeout = kBackendStartupTimeout,
  });

  /// Module/process reported in timeout messages, e.g.
  /// `Editor.Startup/bootstrap` or `Planner.Startup/retry`.
  final String source;
  final Duration timeout;
  bool _timedOut = false;

  /// Whether a request in this pass has already timed out.
  bool get timedOut => _timedOut;

  /// Runs [operation] (one backend request described by [request]) within
  /// the budget.
  Future<T> run<T>(String request, Future<T> Function() operation) async {
    if (_timedOut) {
      throw BackendStartupTimeout(
        source: source,
        request: request,
        timeout: timeout,
        skipped: true,
      );
    }
    try {
      return await operation().timeout(timeout);
    } on TimeoutException {
      _timedOut = true;
      throw BackendStartupTimeout(
        source: source,
        request: request,
        timeout: timeout,
      );
    }
  }
}

const Symbol _budgetZoneKey = #notechondriaStartupRequestBudget;

/// Runs [body] so that every backend request it makes, directly or through
/// any nested await (session restore -> `applyAuthPayload` ->
/// `loadInitialData`, the OAuth exchange, deep-link fetches), is bounded
/// by [budget].
///
/// The budget travels as a zone value and is enforced in one place,
/// `HttpClientInternalsMixin.send`, so startup code paths shared with
/// interactive flows need no extra parameters. Requests started from user
/// gestures run outside this zone and keep their existing (unbounded)
/// behavior, e.g. a long GitHub push.
Future<T> runWithStartupBudget<T>(
  StartupRequestBudget budget,
  Future<T> Function() body,
) {
  return runZoned(body, zoneValues: {_budgetZoneKey: budget});
}

/// The budget of the startup pass the current code runs in, or null
/// outside one.
StartupRequestBudget? get currentStartupBudget =>
    Zone.current[_budgetZoneKey] as StartupRequestBudget?;
