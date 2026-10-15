part of notechondria_frontend;

/// Cold-start orchestration for the portal shell and the recovery actions
/// behind its startup fallbacks. Moved out of `app_shell.dart` in 0.1.198
/// (AGENTS.md 1000-line cap) when startup gained a bounded request budget
/// and a bootstrap-failure screen.
///
/// Every backend request made while starting, retrying from the
/// load-error banner, or switching to offline mode from it runs inside a
/// [StartupRequestBudget] (see `runWithStartupBudget`): an unresponsive
/// backend now ends in the banner after [kBackendStartupTimeout] instead
/// of an empty shell that never finishes loading.
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
        StartupRequestBudget(source: 'Portal.Startup/bootstrap'),
        () async {
          _splashStatus.value = 'Loading local state';
          await _loadLocalState();
          _splashStatus.value = 'Restoring session';
          await _restoreSession();
          _splashStatus.value = 'Completing sign-in';
          final freshSignIn = await handleOAuthCallback();
          _splashStatus.value = 'Connecting to server';
          await _loadInitialData();
          if (freshSignIn) {
            await _applyKeepOfflineChoice();
          }
          await _openInitialCourseDeepLink();
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
    debugPrint('Notechondria Portal cannot finish starting: '
        'Portal.Startup/bootstrap \u2014 $cause\n$stack');
    _startupFailure = cause;
    _isLoading = false;
    _showSplash = false;
    refreshState();
    log(
      level: DebugLogLevel.error,
      source: 'Portal.Startup/bootstrap',
      message: 'Portal cannot finish starting \u2014 $cause',
    );
  }

  void _retryBootstrap() {
    _startupFailure = null;
    _isLoading = true;
    refreshState();
    unawaited(_bootstrapApp());
  }

  /// Leaves the bootstrap-failure screen for the shell with whatever was
  /// loaded, so Settings > Local data stays reachable.
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
      StartupRequestBudget(source: 'Portal.Startup/retry'),
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
      StartupRequestBudget(source: 'Portal.Startup/work_offline'),
      () => _setOfflineMode(true),
    );
  }

  /// Honours the sign-in card's "keep offline data after login" choice
  /// right after a fresh OAuth sign-in (0.1.180). Kept (default): the
  /// cloud is pulled into the local cache in the background — every local
  /// save carries a `last_edit` timestamp, and when both sides changed
  /// the pull's conflict dialog prompts the user to pick which version to
  /// keep. Unchecked: local drafts are cleared so a shared machine never
  /// leaks the previous user's offline notes into this account.
  Future<void> _applyKeepOfflineChoice() async {
    final keep = _localSettings['keep_offline_data_on_login'] != false;
    if (!keep) {
      _localDrafts = [];
      await saveLocalDrafts(_localDrafts);
      refreshState();
      log(
        level: DebugLogLevel.info,
        source: 'Portal.Sync.Session/keep_offline',
        message: 'Local drafts cleared on sign-in: '
            'Portal.Sync.Session/keep_offline — '
            '"keep offline data" was unchecked.',
      );
      return;
    }
    // Background merge; failures only log (never block the session).
    unawaited(_pullCloudNotesToLocal().then((feedback) {
      log(
        level: feedback.isError ? DebugLogLevel.warning : DebugLogLevel.info,
        source: 'Portal.Sync.Session/keep_offline',
        message: 'Post-login cloud→local pull: '
            'Portal.Sync.Session/keep_offline — ${feedback.message}',
      );
    }));
  }

  /// Restores a persisted auth session if one exists (mirrors the
  /// editor). Validates the stored token against `/auth/session/`; a
  /// stale token clears the persisted session instead of restoring it.
  /// A startup timeout keeps the persisted session: it says nothing about
  /// the token, and clearing it would sign the user out because the
  /// server was slow. The banner's Retry restores it later.
  Future<void> _restoreSession() async {
    final session = await _LocalAppStore.loadSession();
    if (session == null) return;
    final token = session['token']?.toString() ?? '';
    if (token.isEmpty) return;
    try {
      final check = await widget.client.checkSession(token);
      if (check['authenticated'] == true) {
        await applyAuthPayload(check);
        return;
      }
    } on BackendStartupTimeout catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: 'Portal.Auth/restore',
        message: 'Saved session not restored yet \u2014 $error '
            'The session stays saved; Retry restores it.',
      );
      return;
    } catch (_) {
      // Token invalid or network down — fall through and clear.
    }
    await _LocalAppStore.clearSession();
  }

  /// Resolves a `#/courses/<slug>` cold-start deep link once the course
  /// list is loaded. Unknown slugs stay on the course-list tab.
  Future<void> _openInitialCourseDeepLink() async {
    final slug = widget.initialCourseSlug;
    if (slug == null || slug.isEmpty || !mounted) {
      return;
    }
    Map<String, dynamic>? match;
    for (final course in _courses) {
      if (course['slug']?.toString() == slug) {
        match = course;
        break;
      }
    }
    if (match != null) {
      await _selectCourse(match);
    }
  }
}
