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
extension _AppShellBootstrapX on _AppShellState {
  Future<void> _bootstrapApp() async {
    _startupFailure = null;
    _splashTimer?.cancel();
    _splashTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      _isLoading = false;
      _showSplash = false;
      refreshState();
    });
    try {
      await runWithStartupBudget(
        StartupRequestBudget(source: 'Planner.Startup/bootstrap'),
        () async {
          _splashStatus.value = 'Loading local planner data';
          await _loadLocalState();
          _splashStatus.value = 'Completing sign-in';
          await handleOAuthCallback();
          _splashStatus.value = 'Connecting to server';
          await _loadInitialData();
        },
      );
    } catch (error, stack) {
      _handleBootstrapFailure(error, stack);
    }
  }

  /// A startup step threw (e.g. a corrupt local cache): show the
  /// [StartupFailureView] instead of a half-initialized shell.
  void _handleBootstrapFailure(Object error, StackTrace stack) {
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
      message: 'Planner cannot finish starting \u2014 $cause',
    );
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
