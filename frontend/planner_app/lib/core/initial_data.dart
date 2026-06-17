part of notechondria_frontend;

/// Cold-boot + post-auth data loading orchestrator.
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
    widget.onLocaleChanged?.call(
      _localSettings['locale']?.toString() ?? 'system',
    );

    var courses = List<Map<String, dynamic>>.from(_courses);
    var activity = List<Map<String, dynamic>>.from(_activity);
    var courseNotes = List<Map<String, dynamic>>.from(_courseNotes);
    var plannerEvents = List<Map<String, dynamic>>.from(_plannerEvents);
    var calendarFeeds = List<Map<String, dynamic>>.from(_calendarFeeds);
    var learnerNotes = List<Map<String, dynamic>>.from(_learnerNotes);
    var deletedNotes = List<Map<String, dynamic>>.from(_deletedNotes);
    Map<String, dynamic>? activityWeek = _activityWeek;
    Map<String, dynamic> notePage = {
      'results': learnerNotes,
      'has_more': _hasMoreLearnerNotes,
    };
    var updatedCache = false;

    // Phase-3 Casdoor probe — fire-and-forget. Drives the SSO pill
    // visibility on the AuthHub; failures fall through to the
    // legacy Google / GitHub buttons. See
    // docs/integrations/casdoor-migration.md.
    unawaited(() async {
      try {
        final config = await widget.client.getCasdoorConfig();
        final configured = config['configured'] == true;
        // Derive the Casdoor login URL from the same payload so
        // AuthHub's "Sign up via Casdoor" CTA can navigate the
        // browser to the hosted org-themed login page at
        // `${endpoint}/login/${organization}`. Prefer the backend's
        // `signin_url` when present so the URL stays in lockstep
        // with the backend's view; the local synthesis is only a
        // fallback for very old backend images that pre-date the
        // `signin_url` field.
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
        // of a silent swallow. See editor_app's matching block for
        // the rationale.
        // 0.1.101: include the resolved request URL so the bare
        // "API route not found" string carries enough info to tell
        // which backend host is stale.
        final baseUrl = _httpClient?.baseUrl ?? '<unresolved>';
        final probedUrl = baseUrl.endsWith('/')
            ? '${baseUrl}auth/casdoor/config/'
            : '$baseUrl/auth/casdoor/config/';
        log(
          level: DebugLogLevel.warning,
          source: 'Planner.Auth/casdoor.config.probe',
          message: 'Casdoor SSO surface unavailable: '
              'Planner.Auth/casdoor.config.probe — '
              '${error.toString().replaceFirst("Exception: ", "")} '
              '(probed $probedUrl).',
        );
      }
    }());

    // Offline-mode gate: skip every remote fetch and render from the
    // local cache. Sign-in and explicit sync still work because those
    // paths call into `widget.client` directly, not through here.
    final offlineMode = _localSettings['offline_mode'] == true;
    if (offlineMode) {
      // Category auto-sync: if authenticated, still fetch courses so
      // the sidebar category list stays up-to-date even in offline mode.
      if (_token != null && _token!.isNotEmpty) {
        try {
          courses = (await timed(
            'Planner._loadInitialData.getCourses.offline',
            () => widget.client.getCourses(token: _token),
          ))
              .map(decorateRemoteCourse)
              .toList(growable: false);
          updatedCache = true;
        } catch (_) {}
      }
      _courses = courses;
      _activity = activity;
      _courseNotes = courseNotes;
      _plannerEvents = plannerEvents;
      _calendarFeeds = calendarFeeds;
      _learnerNotes = learnerNotes;
      _deletedNotes = deletedNotes;
      _activityWeek = activityWeek;
      _hasMoreLearnerNotes = notePage['has_more'] == true;
      _learnerNotesOffset = learnerNotes.length;
      _errorMessage = null;
      _isLoading = false;
      _showSplash = false;
      refreshState();
      log(
        source: 'Planner._loadInitialData',
        level: DebugLogLevel.info,
        message: 'Offline mode: Planner._loadInitialData \u2014 skipped remote '
            'fetches, rendered from local cache.',
      );
      return;
    }

    try {
      courses = (await timed(
        'Planner._loadInitialData.getCourses',
        () => widget.client.getCourses(token: _token),
      ))
          .map(decorateRemoteCourse)
          .toList(growable: false);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }
    try {
      activity = await timed(
        'Planner._loadInitialData.getActivity',
        () => widget.client.getActivity(token: _token),
      );
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }

    final selectedCourse = _chooseDefaultCourse(
      remoteCourses: courses,
      localCourses: _localCourses,
    );
    if (selectedCourse != null) {
      if (isLocalCourse(selectedCourse)) {
        courseNotes = _localNotesForCourse(selectedCourse);
      } else {
        try {
          courseNotes = await timed(
            'Planner._loadInitialData.getCourseNotes',
            () => widget.client.getCourseNotes(
              selectedCourse['id'] as int,
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
        plannerEvents = await timed(
          'Planner._loadInitialData.getPlannerEvents',
          () => widget.client.getPlannerEvents(_token!),
        );
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        calendarFeeds = await timed(
          'Planner._loadInitialData.getCalendarFeeds',
          () => widget.client.getCalendarFeeds(_token!),
        );
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        activityWeek = await timed(
          'Planner._loadInitialData.getActivityWeek',
          () => widget.client.getActivityWeek(
            _token!,
            startDate: _activityWeekStart.toIso8601String().split('T').first,
          ),
        );
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        deletedNotes = await timed(
          'Planner._loadInitialData.getDeletedNotes',
          () => widget.client.getDeletedNotes(_token!),
        );
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        notePage = await timed(
          'Planner._loadInitialData.listNotes',
          () => widget.client.listNotes(token: _token, limit: 20, offset: 0),
        );
        learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
    } else {
      // Signed out: planner events live locally (seeded on first run +
      // created offline), so KEEP them — `plannerEvents` is already the
      // locally-loaded list — and render the activity board from them
      // offline-first instead of blanking it. Earlier builds set
      // `plannerEvents = const []` and `activityWeek = null` here, which
      // wiped the cache loaded at boot and made the Activity view
      // sign-in-only. Cloud-only data (calendar feeds, server recycle
      // bin, cloud notes) has no local equivalent and is still cleared.
      calendarFeeds = const [];
      activityWeek = _buildOfflineActivityWeek();
      deletedNotes = const [];
      learnerNotes = const [];
      notePage = const {
        'results': [],
        'has_more': false,
      };
    }

    // Detect a rejected DRF token (revoked server-side, or signed by a
    // different SECRET_KEY after a deploy) and clear the in-memory
    // session so the user sees the auth UI instead of silently
    // dropping into offline mode with a stale identity.
    //
    // Threshold: require AT LEAST TWO authenticated endpoints to
    // fail with a 401-shaped error before we nuke the session. A
    // single flaky 401 (rate limit / server glitch / post-login
    // race where one endpoint lags the token commit) used to wipe
    // a freshly-issued session and kick the user back to the login
    // dialog. Planner doesn't persist the token to disk, so only
    // in-memory state needs to be reset.
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
      _token = null;
      _profile = null;
    }
    _courses = courses;
    _activity = activity;
    _selectedCourse = selectedCourse;
    _courseNotes = courseNotes;
    _learnerNotes = learnerNotes;
    _deletedNotes = deletedNotes;
    _selectedNote = null;
    _plannerEvents = plannerEvents;
    _calendarFeeds = calendarFeeds;
    _activityWeek = activityWeek;
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
      source: 'Planner._loadInitialData',
      level: errors.isEmpty ? DebugLogLevel.info : DebugLogLevel.warning,
      message: errors.isEmpty
          ? 'Initial Planner._loadInitialData data loaded '
              '(${courses.length} cloud courses, ${learnerNotes.length} notes).'
          : sessionRejected
              ? 'Session expired \u2014 signed out. Please sign in again.'
              : 'Initial Planner._loadInitialData load used offline fallback: '
                  'Planner.Sync.Planner/bootstrap \u2014 ${errors.first}.',
    );
    if (!sessionRejected) {
      if (!_maybeShowOnboarding()) {
        unawaited(_maybeShowWhatsNew());
        _maybeShowInstallBanner();
      }
    }
  }
}
