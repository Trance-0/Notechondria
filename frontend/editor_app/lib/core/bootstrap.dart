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
///
/// 0.1.199: every step writes structured debug-log records through
/// `startupStep` (`Editor.Startup/<step>`, with duration and, on failure,
/// the cause), and the splash shows the running step. Order: local_state,
/// config, handshake, session_restore, oauth_callback, initial_data.
extension _AppShellBootstrapX on _AppShellState {
  /// Safety net only: startup itself is bounded by the 10s budget, so the
  /// splash normally ends when `_loadInitialData` finishes. A folder scan
  /// re-arms it on every progress report (local folder 2.9 "Splash").
  void _armSplashTimer() {
    _splashTimer?.cancel();
    _splashTimer =
        Timer(kBackendStartupTimeout + const Duration(seconds: 2), () {
      if (mounted && _isLoading) {
        _isLoading = false;
        _showSplash = false;
        refreshState();
      }
    });
  }

  Future<void> _bootstrapApp() async {
    _startupFailure = null;
    _armSplashTimer();
    try {
      await runWithStartupBudget(
        StartupRequestBudget(source: 'Editor.Startup/bootstrap'),
        () async {
          await startupStep<void>(
            'Editor.Startup/local_state',
            _loadLocalState,
            status: _splashStatus,
            label: 'Loading local workspace',
            failureConsequence: 'Local workspace not loaded',
            outcome: (_) => (
              level: DebugLogLevel.info,
              message: 'Local workspace loaded: Editor.Startup/local_state '
                  '\u2014 ${_localDrafts.length} local draft(s), '
                  '${_localCourses.length} local categor(ies).',
            ),
          );
          // Folder mode (local folder 2.9): opens the folder and starts
          // the folder session; makes no network request.
          await _runLocalFolderStep();
          _logStartupConfig();
          await _runStartupHandshake();
          // In folder mode the session comes from the folder, so
          // session_restore and oauth_callback are skipped (2.9).
          if (inFolderMode) {
            _logFolderSkipsSignIn();
          } else {
            await _restoreSessionAndCallback();
          }
          if (_folderPending) {
            _finishStartupWithFolderPending();
          } else {
            final name = _folder?.folderName ?? '';
            await startupStep<void>(
              'Editor.Startup/initial_data',
              _loadInitialData,
              status: _splashStatus,
              label: inFolderMode
                  ? "Reading folder '$name'"
                  : 'Connecting to server',
              failureConsequence: inFolderMode
                  ? 'Folder data not loaded'
                  : 'Cloud data not loaded',
              outcome: (_) =>
                  _initialDataOutcome('Editor.Startup/initial_data'),
            );
          }
          // Deep-link: if the URL contains a note UUID, load it. While the
          // folder is pending it waits for the folder (design review 3 T2).
          final deepLinkUuid = _parseNoteUuidFromUrl();
          if (deepLinkUuid != null) {
            if (_folderPending) {
              _folderSession.pendingDeepLink = deepLinkUuid;
            } else {
              await _openNoteByUuid(deepLinkUuid);
            }
          }
        },
      );
      // Outside the startup budget (local folder 2.9 step 3).
      unawaited(_verifyFolderAfterStartup());
    } catch (error, stack) {
      _handleBootstrapFailure(error, stack);
    }
  }

  /// The cloud half of the startup pass: session_restore, then the
  /// oauth_callback, and the 2.10 rule 2 notice when a saved session won
  /// over a connected folder.
  Future<void> _restoreSessionAndCallback() async {
    // Restore the stored auth token BEFORE handling any OAuth
    // callback. The bind flow needs `_token` to be non-null so it
    // can call the authenticated /auth/bind/* endpoint; otherwise
    // the fallback logic would hit the public /auth/<provider>/
    // endpoint and either log in as the OAuth identity's email
    // owner or create a new account, effectively overwriting the
    // current user.
    await startupStep<String>(
      'Editor.Startup/session_restore',
      _restoreSession,
      status: _splashStatus,
      label: 'Restoring session',
      failureConsequence: 'Session not restored',
      outcome: (outcome) =>
          _sessionRestoreOutcome('Editor.Startup/session_restore', outcome),
    );
    _noteCloudSessionPrecedence();
    await startupStep<bool>(
      'Editor.Startup/oauth_callback',
      handleOAuthCallback,
      status: _splashStatus,
      label: 'Completing sign-in',
      failureConsequence: 'Sign-in not completed',
      outcome: (signedIn) => signedIn
          ? (
              level: DebugLogLevel.info,
              message: 'Sign-in completed: '
                  'Editor.Startup/oauth_callback \u2014 the sign-in '
                  'redirect was exchanged for a session.',
            )
          : (
              level: DebugLogLevel.debug,
              message: 'No sign-in completed: '
                  'Editor.Startup/oauth_callback \u2014 the page URL '
                  'has no usable sign-in code (see any Auth line '
                  'above for a failed exchange).',
            ),
    );
  }

  /// Logs which API base URL this start uses and why (0.1.199).
  void _logStartupConfig() {
    final base = _httpClient?.baseUrl ?? 'no HTTP client';
    final saved = _localSettings['api_base_url']?.toString() ?? '';
    if (inFolderMode) {
      log(
        level: DebugLogLevel.info,
        source: 'Editor.Startup/config',
        message: 'API base resolved: Editor.Startup/config \u2014 folder '
            'mode; requests are answered in the page (the saved URL '
            '${saved.isEmpty ? base : saved} is used only by Check for '
            'updates).',
      );
      return;
    }
    final origin = kIsWeb ? '; page origin ${Uri.base.origin}' : '';
    final offline = _localSettings['offline_mode'] == true;
    log(
      level: DebugLogLevel.info,
      source: 'Editor.Startup/config',
      message: 'API base resolved: Editor.Startup/config \u2014 $base '
          '(${saved.isNotEmpty && saved != _defaultApiBaseUrl() ? 'saved setting' : 'default for this page origin'}'
          '$origin; offline mode ${offline ? 'on' : 'off'}).',
    );
  }

  /// The first contact with the backend, logged and bounded by the
  /// startup budget. Its result also answers the version banner's first
  /// probe (`_startupHandshake`), so startup sends one handshake, not two.
  /// A failed handshake does not stop startup: the session restore and
  /// data load still run (and fail fast once the budget has timed out).
  Future<void> _runStartupHandshake() async {
    // Folder mode ignores offline_mode: the handshake is answered in the
    // page (local folder 2.7, 2.8 rule 4).
    if (!inFolderMode && _localSettings['offline_mode'] == true) {
      log(
        level: DebugLogLevel.debug,
        source: 'Editor.Startup/handshake',
        message: 'Handshake skipped: Editor.Startup/handshake \u2014 '
            'offline mode is on.',
      );
      _completeStartupHandshake(null);
      return;
    }
    final base = _httpClient?.baseUrl ??
        (_localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl());
    try {
      final result = await startupStep<HandshakeResult>(
        'Editor.Startup/handshake',
        () => widget.client.verifyHandshake(base),
        status: _splashStatus,
        label: inFolderMode ? 'Opening folder backend' : 'Connecting to server',
        failureConsequence: 'Backend not reachable',
        outcome: (result) => result.ok
            ? (
                level: DebugLogLevel.info,
                message: 'Backend reachable: Editor.Startup/handshake '
                    '\u2014 GET $base/handshake/ answered ${result.service} '
                    'v${result.version} (api ${result.apiVersion}).',
              )
            : (
                level: DebugLogLevel.warning,
                message: 'Backend not reachable: Editor.Startup/handshake '
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
      message: inFolderMode
          ? 'Startup step finished: $source \u2014 every folder request '
              'answered.'
          : _localSettings['offline_mode'] == true
          ? 'Startup step finished: $source \u2014 offline mode is on; '
              'rendered from the local cache.'
          : 'Startup step finished: $source \u2014 every cloud request '
              'answered.',
    );
  }

  /// Turns `_restoreSession`'s outcome into the session_restore record.
  StartupOutcome _sessionRestoreOutcome(String source, String outcome) {
    if (outcome == 'no saved session') {
      return (
        level: DebugLogLevel.debug,
        message: 'No saved session: $source \u2014 nothing is stored on '
            'this device.',
      );
    }
    if (outcome == 'saved session validated') {
      return (
        level: DebugLogLevel.info,
        message: 'Session restored: $source \u2014 saved session validated.',
      );
    }
    return (
      level: DebugLogLevel.warning,
      message: outcome.startsWith('saved session kept')
          ? 'Session not restored yet: $source \u2014 $outcome.'
          : 'Session not restored: $source \u2014 $outcome.',
    );
  }

  /// A startup step threw (e.g. a corrupt local cache): show the
  /// [StartupFailureView] instead of a half-initialized shell.
  void _handleBootstrapFailure(Object error, StackTrace stack) {
    final cause = error.toString().replaceFirst('Exception: ', '');
    debugPrint('Notechondria Editor cannot finish starting: '
        'Editor.Startup/bootstrap \u2014 $cause\n$stack');
    _completeStartupHandshake(null);
    _startupFailure = cause;
    _isLoading = false;
    _showSplash = false;
    refreshState();
    log(
      level: DebugLogLevel.error,
      source: 'Editor.Startup/bootstrap',
      message: 'Editor cannot finish starting: Editor.Startup/bootstrap '
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
