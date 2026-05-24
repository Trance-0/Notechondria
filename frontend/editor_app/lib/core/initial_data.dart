part of notechondria_frontend;

/// Cold-boot + post-auth + post-logout + post-offline-toggle
/// data-loading orchestrator. Fires every remote fetch needed to
/// render the first paint (front page, courses, selected course
/// notes, soft-deleted notes, learner list), then commits the
/// result in one big field update routed through `refreshState()`.
/// Also detects a rejected DRF token across ≥2 authenticated
/// endpoints and clears the local session so the user sees the
/// auth UI instead of a stale identity. Extracted from
/// `app_shell.dart` so that file stays closer to the AGENTS.md
/// §1.5 1000-line ceiling.
extension _AppShellInitialDataX on _AppShellState {
  Future<void> _loadInitialData() async {
    _isLoading = true;
    _errorMessage = null;
    refreshState();
    final errors = <String>[];
    _httpClient?.updateBaseUrl(
      _localSettings['api_base_url']?.toString() ?? _defaultApiBaseUrl(),
    );
    widget.onThemeChanged?.call(
      _localSettings['theme_preset']?.toString() ?? 'teal',
      _localSettings['theme_mode']?.toString() ?? 'S',
    );

    var frontPage = _frontPage ?? frontPageFallbackPayload(_courses);
    var courses = List<Map<String, dynamic>>.from(_courses);
    var courseNotes = List<Map<String, dynamic>>.from(_courseNotes);
    var learnerNotes = List<Map<String, dynamic>>.from(_learnerNotes);
    var deletedNotes = List<Map<String, dynamic>>.from(_deletedNotes);
    Map<String, dynamic> notePage = {
      'results': learnerNotes,
      'has_more': _hasMoreLearnerNotes,
    };
    var updatedCache = false;

    // Offline-mode gate: skip every remote fetch and render from the
    // local cache. Target < 500 ms first paint on signed-out boot.
    // Sign-in and explicit sync still work because those paths call
    // into `widget.client` directly, not through `_loadInitialData`.
    // Phase-3 Casdoor probe — fire-and-forget. The result drives
    // whether `_buildSignedOutAccount` renders the SSO pill;
    // failures (offline, backend on shadow mode, network blip) are
    // swallowed silently and the SPA falls through to the legacy
    // Google / GitHub buttons. See docs/integrations/
    // casdoor-migration.md.
    unawaited(() async {
      try {
        final config = await widget.client.getCasdoorConfig();
        final configured = config['configured'] == true;
        // The login URL backs the "Sign up via Casdoor" link in the
        // signed-out account card. Casdoor's hosted org-themed login
        // page lives at `${endpoint}/login/${organization}` —
        // env-driven on the backend (`CASDOOR_ENDPOINT`,
        // `CASDOOR_ORG_NAME`), no client-side hard-coding. Prefer
        // `signin_url` from the backend response when present so the
        // URL stays in lockstep with the backend's view; the local
        // synthesis is only a fallback for very old backend images
        // that pre-date the `signin_url` field.
        final endpoint = (config['endpoint']?.toString() ?? '')
            .replaceAll(RegExp(r'/+$'), '');
        final orgName = config['organization']?.toString() ?? '';
        final backendSigninUrl = config['signin_url']?.toString() ?? '';
        final orgLoginUrl = !configured
            ? null
            : (backendSigninUrl.isNotEmpty
                ? backendSigninUrl
                : (endpoint.isNotEmpty && orgName.isNotEmpty
                    ? '$endpoint/login/$orgName'
                    : null));
        if (mounted &&
            (configured != _casdoorConfigured ||
                orgLoginUrl != _casdoorOrgLoginUrl)) {
          _casdoorConfigured = configured;
          _casdoorOrgLoginUrl = orgLoginUrl;
          refreshState();
        }
      } catch (error) {
        // 0.1.104: surface the failure as a debug-log line instead
        // of a silent swallow. The previous catch-all hid stale-
        // deploy bugs (e.g. backend running pre-0.1.96 returns 404
        // on /auth/casdoor/config/) — the SSO pill silently failed
        // to appear with no breadcrumb in the UI debug log. Logged
        // at warning so the operator can grep without flagging
        // shadow-mode setups (which return `{configured: false}` as
        // a 200 response, not an exception).
        // 0.1.101: include the resolved request URL in the log line
        // so the operator can tell which backend host returned 404.
        // Without it the bare "API route not found" was useless —
        // the same string appears whether you're hitting prod, a
        // stale Render deploy, or `localhost` with the wrong port.
        final baseUrl = _httpClient?.baseUrl ?? '<unresolved>';
        final probedUrl = baseUrl.endsWith('/')
            ? '${baseUrl}auth/casdoor/config/'
            : '$baseUrl/auth/casdoor/config/';
        log(
          level: DebugLogLevel.warning,
          source: 'Editor.Auth/casdoor.config.probe',
          message: 'Casdoor SSO surface unavailable: '
              'Editor.Auth/casdoor.config.probe — '
              '${error.toString().replaceFirst("Exception: ", "")} '
              '(probed $probedUrl).',
        );
      }
    }());

    final offlineMode = _localSettings['offline_mode'] == true;
    if (offlineMode) {
      // Category auto-sync: if authenticated, still fetch courses so
      // the sidebar category list stays up-to-date even in offline mode.
      if (_token != null && _token!.isNotEmpty) {
        try {
          courses = (await widget.client.getCourses(token: _token))
              .map(decorateRemoteCourse)
              .toList(growable: false);
          updatedCache = true;
        } catch (_) {}
      }
      _frontPage = frontPage;
      _courses = courses;
      _courseNotes = courseNotes;
      _learnerNotes = learnerNotes;
      _deletedNotes = deletedNotes;
      _hasMoreLearnerNotes = notePage['has_more'] == true;
      _learnerNotesOffset = learnerNotes.length;
      _errorMessage = null;
      _isLoading = false;
      _showSplash = false;
      refreshState();
      log(
        source: 'Editor._loadInitialData',
        level: DebugLogLevel.info,
        message: 'Offline mode: Editor._loadInitialData \u2014 skipped remote '
            'fetches, rendered from local cache.',
      );
      return;
    }

    _splashStatus.value = 'Loading public notes data';
    try {
      frontPage = await timed(
        'Editor._loadInitialData.getFrontPage',
        () => widget.client.getFrontPage(token: _token),
      );
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }
    _splashStatus.value = 'Loading categories';
    try {
      courses = (await timed(
        'Editor._loadInitialData.getCourses',
        () => widget.client.getCourses(token: _token),
      ))
          .map(decorateRemoteCourse)
          .toList(growable: false);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }

    // 0.1.120: the pre-refactor "find local Inbox + remote Inbox and
    // merge them" block was retired along with `Course.is_default`.
    // Local courses are now plain user-created folders; orphan notes
    // (no `course_id`) live in the synthetic uncategorized bucket
    // rendered client-side, so there's nothing to dedupe across the
    // local/remote boundary.

    // 0.1.84: only auto-pick a default course if the user already
    // had one selected pre-bootstrap (e.g. they tapped a category
    // and then refreshed). Otherwise leave `_selectedCourse` null
    // so the cold-boot lands on "All Notes" (public-feed view).
    final hadExplicitSelection = _selectedCourse != null;
    Map<String, dynamic>? selectedCourse;
    if (hadExplicitSelection) {
      selectedCourse = _chooseDefaultCourse(
        remoteCourses: courses,
        localCourses: _localCourses,
        frontPage: frontPage,
      );
      selectedCourse ??= _selectedCourse;
    }
    if (selectedCourse != null) {
      final course = selectedCourse;
      if (isLocalCourse(course)) {
        courseNotes = _localNotesForCourse(course);
      } else {
        try {
          courseNotes = await timed(
            'Editor._loadInitialData.getCourseNotes',
            () => widget.client.getCourseNotes(
              course['id'] as int,
              token: _token,
            ),
          );
        } catch (error) {
          errors.add(error.toString().replaceFirst('Exception: ', ''));
          courseNotes = const [];
        }
      }
    } else {
      courseNotes = const [];
    }

    if (_token != null && _token!.isNotEmpty) {
      try {
        deletedNotes = await widget.client.getDeletedNotes(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
    } else {
      deletedNotes = const [];
    }
    _splashStatus.value = 'Loading notes';
    final isAuthd = _token != null && _token!.isNotEmpty;
    final scope = isAuthd ? _learnerSearchScope : 'all';
    // 'local' is a frontend-only scope — skip the backend fetch
    // so _loadInitialData doesn't repopulate _learnerNotes with
    // cloud data while the user is filtering to local drafts only.
    if (scope != 'local') {
      try {
        notePage = await timed(
          'Editor._loadInitialData.listNotes',
          () => widget.client.listNotes(
            token: isAuthd ? _token : null,
            limit: 20,
            offset: 0,
            scope: scope,
          ),
        );
        learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
    }

    // 0.1.120: the pre-refactor "anonymous safety net" picked a local
    // course flagged is_default=true so a brand-new user always
    // landed on their Inbox. With Inbox retired in favour of the
    // synthetic uncategorized bucket, leaving `_selectedCourse=null`
    // is the right thing — the sidebar's pinned uncategorized row
    // shows on first paint and surfaces every note with no category.

    // Detect a rejected DRF token (revoked server-side, or signed by a
    // different SECRET_KEY after a deploy) and clear the local session
    // so the user sees the auth UI instead of silently dropping into
    // offline mode with a stale identity.
    //
    // Threshold: require AT LEAST TWO authenticated endpoints to fail
    // with a 401-shaped error before we nuke the session. A single
    // flaky 401 (rate limit / server glitch / post-login race where
    // one endpoint lags the token commit) used to wipe a freshly-issued
    // session and kick the user back to the login dialog.
    final authFailureCount = errors.where((message) {
      final lower = message.toLowerCase();
      return lower.contains('invalid token') ||
          lower.contains('authentication credentials were not provided') ||
          lower.contains('token_not_valid') ||
          lower.contains('session rejected:');
    }).length;
    final sessionRejected =
        _token != null && _token!.isNotEmpty && authFailureCount >= 2;
    if (sessionRejected) {
      await _LocalAppStore.clearSession();
    }

    if (sessionRejected) {
      _token = null;
      _profile = null;
    }
    _frontPage = frontPage;
    _courses = courses;
    _selectedCourse = selectedCourse;
    _courseNotes = courseNotes;
    _learnerNotes = learnerNotes;
    _deletedNotes = deletedNotes;
    _selectedNote = null;
    _hasMoreLearnerNotes = notePage['has_more'] == true;
    _learnerNotesOffset = learnerNotes.length;
    _errorMessage = errors.isEmpty ? null : errors.first;
    _isLoading = false;
    _showSplash = false;
    refreshState();
    if (updatedCache) {
      await _persistLocalCache();
    }
    log(
      source: 'Editor._loadInitialData',
      level: errors.isEmpty
          ? DebugLogLevel.info
          : sessionRejected
              ? DebugLogLevel.warning
              : DebugLogLevel.warning,
      message: errors.isEmpty
          ? 'Initial Editor._loadInitialData data loaded '
              '(${courses.length} categories, ${learnerNotes.length} notes).'
          : sessionRejected
              ? 'Session expired \u2014 signed out. Please sign in again.'
              : 'Initial load used offline fallback: ${errors.first}',
    );
    if (!sessionRejected && errors.isEmpty) {
      unawaited(_maybePromptInboxMigration());
    }
  }
}
