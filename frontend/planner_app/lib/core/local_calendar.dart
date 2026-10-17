part of notechondria_frontend;

/// Calendars imported on this device (0.1.199).
///
/// A calendar imported while signed out, in offline mode, or while the
/// cloud upload fails is parsed on the device (`parseIcalEvents`) and kept
/// in its own `_LocalAppStore` bucket
/// (`notechondria.planner.local_calendar_feeds`), so the import works with
/// no cloud session and no reachable backend and survives a reload. Each
/// record uses the local-archive `calendar_feeds.json` shape (the backend
/// `CalendarFeedSerializer` fields plus `is_local_feed`, `source_file`,
/// and the parsed `events`), so a `.nchron` export carries it unchanged.
///
/// Local feeds are not uploaded later: there is no "push local items on
/// sign-in" path for calendars yet (see docs/TODO.md, Planner).
extension _AppShellLocalCalendarX on _AppShellState {
  Map<String, dynamic> _buildLocalCalendarFeed({
    required String title,
    required String sourceName,
    int? courseId,
    required List<IcalEvent> events,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'id': -DateTime.now().microsecondsSinceEpoch,
      'title': title,
      'source_kind': 'I',
      'source_url': '',
      'is_enabled': true,
      'course_id': courseId,
      'last_sync': null,
      'date_created': now,
      'last_edit': now,
      'is_local_feed': true,
      'source_file': sourceName,
      'events': [for (final event in events) event.toJson()],
    };
  }

  /// Stores [parsed] as a local calendar named [title], replacing an
  /// earlier local import with the same title (case-insensitive), and
  /// re-renders the activity week. [reason] completes the sentence "it is
  /// stored locally because ...". [uploadFailed] marks the signed-in
  /// fallback after a failed cloud upload: its result is a
  /// [_CalendarKeptLocallyFeedback] (a warning, not a plain success).
  Future<ActionFeedback> _saveCalendarLocally({
    required String title,
    required String sourceName,
    int? courseId,
    required IcalParseResult parsed,
    required String reason,
    bool uploadFailed = false,
  }) async {
    final previous = _localCalendarFeeds;
    final key = title.trim().toLowerCase();
    bool sameTitle(Map<String, dynamic> feed) =>
        (feed['title']?.toString() ?? '').trim().toLowerCase() == key;
    final replaced = previous.any(sameTitle);
    final feed = _buildLocalCalendarFeed(
      title: title,
      sourceName: sourceName,
      courseId: courseId,
      events: parsed.events,
    );
    final next = [
      for (final existing in previous)
        if (!sameTitle(existing)) existing,
      feed,
    ];
    _localCalendarFeeds = next;
    try {
      await _LocalAppStore.saveCalendarFeeds(next);
    } catch (error) {
      _localCalendarFeeds = previous;
      final cause = describeRequestFailure(error);
      final message = 'Calendar not imported: Planner.LocalStore/save \u2014 '
          'browser storage rejected the write ($cause).';
      log(
        level: DebugLogLevel.error,
        source: 'Planner.LocalStore/save',
        message: message,
      );
      return ActionFeedback(message: message, isError: true);
    }
    final signedIn = _token != null && _token!.isNotEmpty;
    _activityWeek = signedIn
        ? _withLocalCalendarEvents(_activityWeek)
        : _buildOfflineActivityWeek();
    refreshState();
    final count = parsed.events.length;
    final events = '$count event${count == 1 ? '' : 's'}';
    final stored = replaced
        ? 'replaced the earlier local import with the same title; it is '
            'stored locally because $reason'
        : 'is stored locally because $reason';
    final message = 'Calendar saved on this device: '
        'Planner.Sync.Calendar/import \u2014 "$title" ($events) $stored; '
        'it is not uploaded to the cloud.';
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Calendar/import',
      message: message,
    );
    return uploadFailed
        ? _CalendarKeptLocallyFeedback(message)
        : ActionFeedback(message: message);
  }

  /// Returns [week] with the local calendars' events placed on its days
  /// (backend `days[].events` shape, `kind: 'calendar'`, marked
  /// `is_local_event`). Idempotent: earlier local entries are stripped
  /// first, so a persisted week never duplicates them.
  Map<String, dynamic>? _withLocalCalendarEvents(Map<String, dynamic>? week) {
    if (week == null) return null;
    final rawDays = week['days'] as List<dynamic>? ?? const [];
    if (rawDays.isEmpty) return week;
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final feed in _localCalendarFeeds) {
      if (feed['is_enabled'] == false) continue;
      for (final raw in feed['events'] as List<dynamic>? ?? const []) {
        if (raw is! Map) continue;
        final event = Map<String, dynamic>.from(raw);
        final start = DateTime.tryParse(event['starts_at']?.toString() ?? '');
        if (start == null) continue;
        final date =
            _dateOnly(start.toLocal()).toIso8601String().split('T').first;
        byDate.putIfAbsent(date, () => <Map<String, dynamic>>[]).add({
          'title': event['title'] ?? feed['title'],
          'kind': 'calendar',
          'course_id': feed['course_id'],
          'source_id': feed['id'],
          'calendar_title': feed['title'],
          'starts_at': event['starts_at'],
          'ends_at': event['ends_at'],
          'description': event['description'] ?? '',
          'all_day': event['all_day'] == true,
          'is_local_event': true,
        });
      }
    }
    final days = <Map<String, dynamic>>[];
    for (final rawDay in rawDays) {
      final day = Map<String, dynamic>.from(rawDay as Map);
      final kept = [
        for (final event in day['events'] as List<dynamic>? ?? const [])
          if (!(event is Map &&
              event['is_local_event'] == true &&
              event['kind'] == 'calendar'))
            event,
      ];
      final added = byDate[day['date']?.toString() ?? ''] ??
          const <Map<String, dynamic>>[];
      days.add({...day, 'events': [...kept, ...added]});
    }
    return {...week, 'days': days};
  }
}

/// Result of a signed-in import whose cloud upload failed, so the calendar
/// was kept on this device instead. It is shown as a warning (`isError`:
/// the longer SnackBar), but the import itself completed, so the review
/// dialog still closes (`modules/activity_calendar.dart`).
class _CalendarKeptLocallyFeedback extends ActionFeedback {
  const _CalendarKeptLocallyFeedback(String message)
      : super(message: message, isError: true);
}
