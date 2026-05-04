part of notechondria_frontend;

/// Initial data orchestrator.
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
        // Derive the Casdoor org-login URL from the same payload so
        // AuthHub's "Login via third party" + "Sign up via Casdoor"
        // CTAs can navigate the browser to the hosted login page at
        // `${endpoint}/login/${organization}`.
        final endpoint =
            (config['endpoint']?.toString() ?? '').replaceAll(RegExp(r'/+$'), '');
        final orgName = config['organization']?.toString() ?? '';
        final orgLoginUrl =
            (configured && endpoint.isNotEmpty && orgName.isNotEmpty)
                ? '$endpoint/login/$orgName'
                : null;
        if (mounted &&
            (configured != _casdoorConfigured ||
                orgLoginUrl != _casdoorOrgLoginUrl)) {
          _casdoorConfigured = configured;
          _casdoorOrgLoginUrl = orgLoginUrl;
          refreshState();
        }
      } catch (_) {
        // shadow mode or transient — leave the flag false.
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
          courses = (await widget.client.getCourses(token: _token))
              .map(decorateRemoteCourse)
              .toList(growable: false);
          updatedCache = true;
        } catch (_) {}
      }
        _frontPage = frontPage;
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
        source: 'Portal._loadInitialData',
        level: DebugLogLevel.info,
        message:
            'Offline mode: Portal._loadInitialData \u2014 skipped remote '
            'fetches, rendered from local cache.',
      );
      return;
    }

    try {
      frontPage = await widget.client.getFrontPage(token: _token);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }
    try {
      courses = (await widget.client.getCourses(token: _token))
          .map(decorateRemoteCourse)
          .toList(growable: false);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }
    try {
      activity = await widget.client.getActivity(token: _token);
      updatedCache = true;
    } catch (error) {
      errors.add(error.toString().replaceFirst('Exception: ', ''));
    }

    final selectedCourse = _chooseDefaultCourse(
      remoteCourses: courses,
      localCourses: _localCourses,
      frontPage: frontPage,
    );
    if (selectedCourse != null) {
      if (isLocalCourse(selectedCourse)) {
        courseNotes = _localNotesForCourse(selectedCourse);
      } else {
        try {
          courseNotes = await widget.client.getCourseNotes(
            selectedCourse['id'] as int,
            token: _token,
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
        plannerEvents = await widget.client.getPlannerEvents(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        calendarFeeds = await widget.client.getCalendarFeeds(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        activityWeek = await widget.client.getActivityWeek(
          _token!,
          startDate: _activityWeekStart.toIso8601String().split('T').first,
        );
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        deletedNotes = await widget.client.getDeletedNotes(_token!);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
      try {
        notePage =
            await widget.client.listNotes(token: _token, limit: 20, offset: 0);
        learnerNotes = (notePage['results'] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
      } catch (error) {
        errors.add(error.toString().replaceFirst('Exception: ', ''));
      }
    } else {
      plannerEvents = const [];
      calendarFeeds = const [];
      activityWeek = null;
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
    // Portal doesn't persist the token to disk, so only in-memory
    // state needs to be reset.
    //
    // Threshold: require AT LEAST TWO authenticated endpoints to
    // fail with a 401-shaped error before we nuke the session. A
    // single flaky endpoint that happens to 401 (rate limit, server
    // glitch, or the post-login race where one endpoint lags the
    // token commit) used to wipe a freshly-issued session and kick
    // the user back to the login dialog. The user-reported "first
    // login always fails" symptom was this false-positive.
    final authFailureCount = errors.where((message) {
      final lower = message.toLowerCase();
      return lower.contains('invalid token') ||
          lower.contains('authentication credentials were not provided') ||
          lower.contains('token_not_valid') ||
          lower.contains('session rejected:');
    }).length;
    final sessionRejected = _token != null &&
        _token!.isNotEmpty &&
        authFailureCount >= 2;

      if (sessionRejected) {
        _token = null;
        _profile = null;
      }
      _frontPage = frontPage;
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
      source: 'Portal._loadInitialData',
      level: errors.isEmpty
          ? DebugLogLevel.info
          : DebugLogLevel.warning,
      message: errors.isEmpty
          ? 'Initial Portal._loadInitialData data loaded '
              '(${courses.length} cloud courses, ${learnerNotes.length} notes).'
          : sessionRejected
              ? 'Session expired \u2014 signed out. Please sign in again.'
              : 'Initial Portal._loadInitialData load used offline fallback: '
                  'Portal.Sync.FrontPage/bootstrap \u2014 ${errors.first}.',
    );
  }
}
