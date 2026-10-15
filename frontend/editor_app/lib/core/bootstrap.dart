part of notechondria_frontend;

/// Cold-start orchestration for the editor shell and the recovery actions
/// behind its startup fallbacks. Moved out of `app_shell.dart` in 0.1.198
/// when startup gained a bounded request budget and a bootstrap-failure
/// screen.
///
/// Every backend request made while starting, retrying from the
/// load-error banner, or switching to offline mode from it runs inside a
/// [StartupRequestBudget] (see `runWithStartupBudget`): an unresponsive
/// backend now ends in the banner after [kBackendStartupTimeout] instead
/// of an empty shell that never finishes loading. Local drafts keep
/// rendering either way.
extension _AppShellBootstrapX on _AppShellState {
  Future<void> _bootstrapApp() async {
    _startupFailure = null;
    _splashTimer?.cancel();
    _splashTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isLoading) {
        _isLoading = false;
        _showSplash = false;
        refreshState();
      }
    });
    try {
      await runWithStartupBudget(
        StartupRequestBudget(source: 'Editor.Startup/bootstrap'),
        () async {
          _splashStatus.value = 'Loading local workspace';
          await _loadLocalState();
          // Restore the stored auth token BEFORE handling any OAuth
          // callback. The bind flow needs `_token` to be non-null so it
          // can call the authenticated /auth/bind/* endpoint; otherwise
          // the fallback logic would hit the public /auth/<provider>/
          // endpoint and either log in as the OAuth identity's email
          // owner or create a new account, effectively overwriting the
          // current user.
          _splashStatus.value = 'Restoring session';
          await _restoreSession();
          _splashStatus.value = 'Completing sign-in';
          await handleOAuthCallback();
          _splashStatus.value = 'Connecting to server';
          await _loadInitialData();
          // Deep-link: if the URL contains a note UUID, load it.
          final deepLinkUuid = _parseNoteUuidFromUrl();
          if (deepLinkUuid != null) {
            await _openNoteByUuid(deepLinkUuid);
          }
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
    debugPrint('Notechondria Editor cannot finish starting: '
        'Editor.Startup/bootstrap \u2014 $cause\n$stack');
    _startupFailure = cause;
    _isLoading = false;
    _showSplash = false;
    refreshState();
    log(
      level: DebugLogLevel.error,
      source: 'Editor.Startup/bootstrap',
      message: 'Editor cannot finish starting \u2014 $cause',
    );
  }

  void _retryBootstrap() {
    _startupFailure = null;
    _isLoading = true;
    refreshState();
    unawaited(_bootstrapApp());
  }

  /// Leaves the bootstrap-failure screen for the shell with whatever was
  /// loaded, so local drafts and Settings > Local data stay reachable.
  void _continueAfterBootstrapFailure() {
    _startupFailure = null;
    _isLoading = false;
    refreshState();
  }

  /// Retry from the load-error banner: re-runs the network half of
  /// startup under a fresh budget. A persisted session that startup could
  /// not restore (the backend timed out) is restored first;
  /// `applyAuthPayload` then reloads the data itself.
  Future<void> _retryStartup() {
    return runWithStartupBudget(
      StartupRequestBudget(source: 'Editor.Startup/retry'),
      () async {
        if (_token == null || _token!.isEmpty) {
          await _restoreSession();
          if (_token != null && _token!.isNotEmpty) return;
        }
        await _loadInitialData();
      },
    );
  }

  /// "Work offline" from the load-error banner. Bounded like a retry so a
  /// signed-in user's offline category refresh cannot hang on an
  /// unresponsive backend.
  Future<void> _workOffline() {
    return runWithStartupBudget(
      StartupRequestBudget(source: 'Editor.Startup/work_offline'),
      () => _setOfflineMode(true),
    );
  }
}
