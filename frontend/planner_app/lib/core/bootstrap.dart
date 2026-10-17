part of notechondria_frontend;

/// Cold-start orchestration for the planner shell and the recovery
/// actions behind its startup fallbacks. Moved out of `app_shell.dart` in
/// 0.1.198 when startup gained a bounded request budget and a
/// bootstrap-failure screen.
///
/// Every backend request made while starting, retrying from the
/// load-error banner, or switching to offline mode from it runs inside a
/// [StartupRequestBudget] (see `runWithStartupBudget`): an unresponsive
/// backend now ends in the banner after [kBackendStartupTimeout] instead
/// of an empty shell that never finishes loading. Locally stored planner
/// data keeps rendering either way.
///
/// 0.1.199: every step writes structured debug-log records through
/// `startupStep` (`Planner.Startup/<step>`, with duration and, on failure,
/// the cause), and the splash shows the running step. Order: local_state,
/// config, handshake, session_restore (nothing to restore: the planner
/// keeps sign-in in memory only), oauth_callback, initial_data.
extension _AppShellBootstrapX on _AppShellState {
  Future<void> _bootstrapApp() async {
    _startupFailure = null;
    _splashTimer?.cancel();
    // Safety net only: startup itself is bounded by the 10s budget, so
    // the splash normally ends when `_loadInitialData` finishes.
    _splashTimer =
        Timer(kBackendStartupTimeout + const Duration(seconds: 2), () {
      if (!mounted) return;
      _isLoading = false;
      _showSplash = false;
      refreshState();
    });
    try {
      await runWithStartupBudget(
        StartupRequestBudget(source: 'Planner.Startup/bootstrap'),
        () async {
          await startupStep<void>(
            'Planner.Startup/local_state',
            _loadLocalState,
            status: _splashStatus,
            label: 'Loading local planner data',
            failureConsequence: 'Local planner data not loaded',
            outcome: (_) => (
              level: DebugLogLevel.info,
              message: 'Local planner data loaded: '
                  'Planner.Startup/local_state \u2014 '
                  '${_localCourses.length} local course(s), '
                  '${_localDrafts.length} draft(s), '
                  '${_plannerEvents.length} planner event(s), '
                  '${_localCalendarFeeds.length} imported calendar(s).',
            ),
          );
          _logStartupConfig();
          await _runStartupHandshake();
          log(
            level: DebugLogLevel.debug,
            source: 'Planner.Startup/session_restore',
            message: 'No saved session: Planner.Startup/session_restore '
                '\u2014 the planner keeps sign-in in memory only, so '
                'startup has nothing to restore.',
          );
          await startupStep<bool>(
            'Planner.Startup/oauth_callback',
            handleOAuthCallback,
            status: _splashStatus,
            label: 'Completing sign-in',
            failureConsequence: 'Sign-in not completed',
            outcome: (signedIn) => signedIn
                ? (
                    level: DebugLogLevel.info,
                    message: 'Sign-in completed: '
                        'Planner.Startup/oauth_callback \u2014 the sign-in '
                        'redirect was exchanged for a session.',
                  )
                : (
                    level: DebugLogLevel.debug,
                    message: 'No sign-in completed: '
                        'Planner.Startup/oauth_callback \u2014 the page URL '
                        'has no usable sign-in code (see any Auth line '
                        'above for a failed exchange).',
                  ),
          );
          await startupStep<void>(
            'Planner.Startup/initial_data',
            _loadInitialData,
            status: _splashStatus,
            label: 'Loading categories',
            failureConsequence: 'Cloud data not loaded',
            outcome: (_) => _initialDataOutcome('Planner.Startup/initial_data'),
          );
        },
      );
    } catch (error, stack) {
      _handleBootstrapFailure(error, stack);
    }
  }

  /// Logs which API base URL this start uses and why (0.1.199).
  void _logStartupConfig() {
    final base = _httpClient?.baseUrl ?? 'no HTTP client';
    final saved = _localSettings['api_base_url']?.toString() ?? '';
    final origin = kIsWeb ? '; page origin ${Uri.base.origin}' : '';
    final offline = _localSettings['offline_mode'] == true;
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Startup/config',
      message: 'API base resolved: Planner.Startup/config \u2014 $base '
          '(${saved.isNotEmpty && saved != _defaultApiBaseUrl() ? 'saved setting' : 'default for this page origin'}'
          '$origin; offline mode ${offline ? 'on' : 'off'}).',
    );
  }

  /// The first contact with the backend, logged and bounded by the
  /// startup budget. Its result also answers the version banner's first
  /// probe (`_startupHandshake`), so startup sends one handshake, not two.
  /// A failed handshake does not stop startup: the data load still runs
  /// (and fails fast once the budget has timed out).
  Future<void> _runStartupHandshake() async {
    if (_localSettings['offline_mode'] == true) {
      log(
        level: DebugLogLevel.debug,
        source: 'Planner.Startup/handshake',
        message: 'Handshake skipped: Planner.Startup/handshake \u2014 '
            'offline mode is on.',
      );
      _completeStartupHandshake(null);
      return;
    }
    final base = _httpClient?.baseUrl ??
        (_localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl());
    try {
      final result = await startupStep<HandshakeResult>(
        'Planner.Startup/handshake',
        () => widget.client.verifyHandshake(base),
        status: _splashStatus,
        label: 'Connecting to server',
        failureConsequence: 'Backend not reachable',
        outcome: (result) => result.ok
            ? (
                level: DebugLogLevel.info,
                message: 'Backend reachable: Planner.Startup/handshake '
                    '\u2014 GET $base/handshake/ answered ${result.service} '
                    'v${result.version} (api ${result.apiVersion}).',
              )
            : (
                level: DebugLogLevel.warning,
                message: 'Backend not reachable: Planner.Startup/handshake '
                    '\u2014 ${(result.error ?? 'no detail').replaceFirst(RegExp(r'\.$'), '')}.',
              ),
      );
      _completeStartupHandshake(result);
    } catch (_) {
      // Already logged by startupStep; the data load reports the rest.
      _completeStartupHandshake(null);
    }
  }

  void _completeStartupHandshake(HandshakeResult? result) {
    if (_startupHandshake.isCompleted) return;
    _startupHandshake.complete(result);
    if (result != null) {
      _startupHandshakeReuseUntil =
          DateTime.now().add(const Duration(minutes: 1));
    }
  }

  /// The initial_data outcome record. `_loadInitialData` does not throw
  /// when cloud requests fail (it falls back to local data and sets
  /// `_errorMessage`), so a fallback is reported as a WARNING with its
  /// cause instead of "done".
  StartupOutcome _initialDataOutcome(String source) {
    final error = _errorMessage;
    if (error != null && error.isNotEmpty) {
      return (
        level: DebugLogLevel.warning,
        message: 'Startup finished on local data only: $source \u2014 '
            '${error.replaceFirst(RegExp(r'\.$'), '')}.',
      );
    }
    return (
      level: DebugLogLevel.debug,
      message: _localSettings['offline_mode'] == true
          ? 'Startup step finished: $source \u2014 offline mode is on; '
              'rendered from the local cache.'
          : 'Startup step finished: $source \u2014 every cloud request '
              'answered.',
    );
  }

  /// A startup step threw (e.g. a corrupt local cache): show the
  /// [StartupFailureView] instead of a half-initialized shell.
  void _handleBootstrapFailure(Object error, StackTrace stack) {
    _completeStartupHandshake(null);
    final cause = error.toString().replaceFirst('Exception: ', '');
    debugPrint('Notechondria Planner cannot finish starting: '
        'Planner.Startup/bootstrap \u2014 $cause\n$stack');
    _startupFailure = cause;
    _isLoading = false;
    _showSplash = false;
    refreshState();
    log(
      level: DebugLogLevel.error,
      source: 'Planner.Startup/bootstrap',
      message: 'Planner cannot finish starting: Planner.Startup/bootstrap '
          '\u2014 $cause',
    );
    unawaited(_recoverLogPersistence());
  }

  void _retryBootstrap() {
    _startupFailure = null;
    _isLoading = true;
    refreshState();
    unawaited(_bootstrapApp());
  }

  /// Leaves the bootstrap-failure screen for the shell with whatever was
  /// loaded, so the local planner data and Settings stay reachable.
  void _continueAfterBootstrapFailure() {
    _startupFailure = null;
    _isLoading = false;
    refreshState();
  }

  /// Retry from the load-error banner: re-runs the initial data load
  /// under a fresh budget. (The planner does not persist sessions, so
  /// there is no session to restore.)
  Future<void> _retryStartup() {
    return runWithStartupBudget(
      StartupRequestBudget(source: 'Planner.Startup/retry'),
      _loadInitialData,
    );
  }

  /// "Work offline" from the load-error banner. Bounded like a retry so a
  /// signed-in user's offline category refresh cannot hang on an
  /// unresponsive backend.
  Future<void> _workOffline() {
    return runWithStartupBudget(
      StartupRequestBudget(source: 'Planner.Startup/work_offline'),
      () => _setOfflineMode(true),
    );
  }
}
