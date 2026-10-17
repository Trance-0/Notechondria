part of notechondria_frontend;

/// Calendar feed CRUD.
///
/// 0.1.199: importing an iCal file no longer needs a cloud session. The
/// file is parsed on the device first; signed out, in offline mode, or
/// when the cloud upload fails, the calendar is stored locally
/// (`core/local_calendar.dart`). Signed in and online, the cloud path is
/// unchanged. Subscribing by URL stays cloud-only (the server downloads
/// the feed; a browser cannot fetch another site's .ics cross-origin), so
/// it explains that instead of failing silently.
extension _AppShellCalendarX on _AppShellState {
  Future<void> _refreshCalendarState() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    final feeds = await widget.client.getCalendarFeeds(token);
    final week = await widget.client.getActivityWeek(
      token,
      startDate: _activityWeekStart.toIso8601String().split('T').first,
    );
    _calendarFeeds = feeds;
    _activityWeek = _withLocalCalendarEvents(week);
    refreshState();
    log(
      level: DebugLogLevel.debug,
      source: 'Planner.Sync.Calendar/refresh',
      message: 'Calendar state refreshed: '
          'Planner.Sync.Calendar/refresh \u2014 '
          'feeds and activity week re-pulled.',
    );
  }

  Future<ActionFeedback> _importCalendarFeed(
    String rawIcal,
    String title, {
    int? courseId,
    String sourceName = '',
  }) async {
    final parsed = parseIcalEvents(rawIcal);
    final label = sourceName.isEmpty ? title : sourceName;
    log(
      level: DebugLogLevel.debug,
      source: 'Planner.Sync.Calendar/parse',
      message: 'Calendar parsed: Planner.Sync.Calendar/parse \u2014 '
          '"$label" has ${parsed.events.length} readable event(s), '
          '${parsed.skipped} skipped (no readable DTSTART).',
    );
    if (parsed.events.isEmpty) {
      final message = 'Calendar not imported: Planner.Sync.Calendar/parse '
          '\u2014 "$label" has no VEVENT entries with a readable DTSTART.';
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Sync.Calendar/parse',
        message: message,
      );
      return ActionFeedback(message: message, isError: true);
    }
    final token = _token;
    final signedIn = token != null && token.isNotEmpty;
    final offline = _localSettings['offline_mode'] == true;
    if (!signedIn || offline) {
      return _saveCalendarLocally(
        title: title,
        sourceName: sourceName,
        courseId: courseId,
        parsed: parsed,
        reason: signedIn ? 'offline mode is on' : 'you are not signed in',
      );
    }
    try {
      await widget.client.createCalendarFeed(token, {
        'title': title,
        'source_kind': 'I',
        'raw_ical': rawIcal,
        'course_id': courseId,
      });
    } catch (error) {
      // A dead or failing backend must never lose the import: keep it on
      // this device and say why. `cause` is redacted (no query string or
      // credential), unlike the raw error text.
      final cause = describeRequestFailure(error);
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Sync.Calendar/push',
        message: 'Calendar saved on this device only: '
            'Planner.Sync.Calendar/push \u2014 cloud upload failed '
            '($cause).',
      );
      return _saveCalendarLocally(
        title: title,
        sourceName: sourceName,
        courseId: courseId,
        parsed: parsed,
        reason: 'the cloud upload failed ($cause)',
        uploadFailed: true,
      );
    }
    final count = parsed.events.length;
    final message = 'Calendar imported: Planner.Sync.Calendar/push \u2014 '
        '"$title" ($count event${count == 1 ? '' : 's'}) added to your '
        'cloud calendars.';
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Calendar/push',
      message: message,
    );
    try {
      await _refreshCalendarState();
    } catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Sync.Calendar/refresh',
        message: 'Calendar list not refreshed: '
            'Planner.Sync.Calendar/refresh \u2014 '
            '${describeRequestFailure(error)}; the import itself succeeded.',
      );
    }
    return ActionFeedback(message: message);
  }

  Future<ActionFeedback> _subscribeCalendarFeed(String title, String url,
      {int? courseId}) async {
    if (url.trim().isEmpty) {
      return const ActionFeedback(
        message: 'Calendar not subscribed: '
            'Planner.Sync.Calendar/subscribe \u2014 the URL field is empty.',
        isError: true,
      );
    }
    final token = _token;
    final signedIn = token != null && token.isNotEmpty;
    if (!signedIn || _localSettings['offline_mode'] == true) {
      final message = signedIn
          ? 'Calendar not subscribed: Planner.Sync.Calendar/subscribe \u2014 '
              'offline mode is on, and subscribing by URL needs the server '
              'to download the feed; this browser cannot fetch another '
              "site's calendar directly (cross-origin). Turn offline mode "
              'off, or download the .ics file and use Import iCal, which '
              'works offline.'
          : 'Calendar not subscribed: Planner.Sync.Calendar/subscribe \u2014 '
              'subscribing by URL needs a cloud session because the server '
              "downloads the feed; this browser cannot fetch another site's "
              'calendar directly (cross-origin). Sign in, or download the '
              '.ics file and use Import iCal, which works offline.';
      log(
        level: DebugLogLevel.info,
        source: 'Planner.Sync.Calendar/subscribe',
        message: message,
      );
      return ActionFeedback(message: message, isError: true);
    }
    try {
      await widget.client.createCalendarFeed(token, {
        'title': title,
        'source_kind': 'S',
        'source_url': url,
        'course_id': courseId,
      });
    } catch (error) {
      final message = 'Calendar not subscribed: '
          'Planner.Sync.Calendar/subscribe \u2014 '
          '${describeRequestFailure(error)}.';
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Sync.Calendar/subscribe',
        message: message,
      );
      return ActionFeedback(message: message, isError: true);
    }
    final message = 'Calendar subscribed: '
        'Planner.Sync.Calendar/subscribe \u2014 '
        '"$title" feed URL registered.';
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Calendar/subscribe',
      message: message,
    );
    try {
      await _refreshCalendarState();
    } catch (error) {
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Sync.Calendar/refresh',
        message: 'Calendar list not refreshed: '
            'Planner.Sync.Calendar/refresh \u2014 '
            '${describeRequestFailure(error)}; the subscription itself '
            'succeeded.',
      );
    }
    return ActionFeedback(message: message);
  }

  Future<void> _toggleCalendarFeed(
      Map<String, dynamic> feed, bool enabled) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client
        .updateCalendarFeed(token, feed['id'] as int, {'is_enabled': enabled});
    await _refreshCalendarState();
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Calendar/toggle',
      message: 'Calendar feed ${enabled ? "enabled" : "disabled"}: '
          'Planner.Sync.Calendar/toggle \u2014 '
          '"${feed['title']}" now ${enabled ? "visible" : "hidden"}.',
    );
  }

  Future<void> _deleteCalendarFeed(Map<String, dynamic> feed) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      return;
    }
    await widget.client.deleteCalendarFeed(token, feed['id'] as int);
    await _refreshCalendarState();
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Calendar/delete',
      message: 'Calendar feed deleted: '
          'Planner.Sync.Calendar/delete \u2014 '
          '"${feed['title']}" removed from the planner.',
    );
  }
}
