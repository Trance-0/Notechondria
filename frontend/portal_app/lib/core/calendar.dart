part of notechondria_frontend;

/// Calendar CRUD.
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
      days: _activityRangeDays,
    );
    _calendarFeeds = feeds;
    _activityWeek = week;
    refreshState();
    log(
      level: DebugLogLevel.debug,
      source: 'Portal.Sync.Calendar/refresh',
      message: 'Calendar state refreshed: '
          'Portal.Sync.Calendar/refresh \u2014 '
          'feeds and activity week re-pulled.',
    );
  }

  Future<Map<String, dynamic>?> _importCalendarFeed(String rawIcal, String title,
      {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Calendar not imported: '
        'Portal.Sync.Calendar/import \u2014 '
        'no cloud session; sign in first.',
      );
    }
    final response = await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'I',
      'raw_ical': rawIcal,
      'course_id': courseId,
    });
    await _refreshCalendarState();
    final summary = response['import_summary'];
    final count = summary is Map ? summary['count'] : null;
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Calendar/import',
      message: 'Calendar imported: Portal.Sync.Calendar/import \u2014 '
          '"$title" iCal feed added${count != null ? " ($count events)" : ""}.',
    );
    // The backend returns an import_summary {ok,count,events,error}; hand it
    // back so the caller can show a success/failure modal.
    return summary is Map ? Map<String, dynamic>.from(summary) : null;
  }

  Future<Map<String, dynamic>?> _subscribeCalendarFeed(String title, String url,
      {int? courseId}) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw Exception(
        'Calendar not subscribed: '
        'Portal.Sync.Calendar/subscribe \u2014 '
        'no cloud session; sign in first.',
      );
    }
    final response = await widget.client.createCalendarFeed(token, {
      'title': title,
      'source_kind': 'S',
      'source_url': url,
      'course_id': courseId,
    });
    await _refreshCalendarState();
    final summary = response['import_summary'];
    final count = summary is Map ? summary['count'] : null;
    log(
      level: DebugLogLevel.info,
      source: 'Portal.Sync.Calendar/subscribe',
      message: 'Calendar subscribed: '
          'Portal.Sync.Calendar/subscribe \u2014 '
          '"$title" feed URL registered${count != null ? " ($count events)" : ""}.',
    );
    return summary is Map ? Map<String, dynamic>.from(summary) : null;
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
      source: 'Portal.Sync.Calendar/toggle',
      message: 'Calendar feed ${enabled ? "enabled" : "disabled"}: '
          'Portal.Sync.Calendar/toggle \u2014 '
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
      source: 'Portal.Sync.Calendar/delete',
      message: 'Calendar feed deleted: '
          'Portal.Sync.Calendar/delete \u2014 '
          '"${feed['title']}" removed from the portal.',
    );
  }
}
