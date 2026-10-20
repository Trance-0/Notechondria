part of '../main.dart';

/// The planner's connect-time push of browser-local data into a folder
/// (design `local_folder_mode/modes_and_migration.md` 7.1, 2.10 rule 3)
/// and the return to browser-local data on Disconnect (2.10 rule 4 step 4).
///
/// Order: courses first, through `_syncLocalCourse` (it needs the token
/// `_startFolderSession` sets, remaps drafts, and moves each course into the
/// local recycle bin), recording `local course id -> folder course id`;
/// then the `is_local_event` planner events and the imported calendars,
/// each with `client_local_id = "planner:<local id>"`, so a repeat push
/// returns the existing folder record. Confirmed items leave the visible
/// lists for the recovery list [_kPushedToFolderKey], pruned after 30 days.
/// Drafts follow inside `applyAuthPayload`.

/// 7.1 step 3: `[{folder_id, pushed_at, events, feeds}]`.
const String _kPushedToFolderKey = 'notechondria.planner.pushed_to_folder';
const Duration _kPushedToFolderTtl = Duration(days: 30);

extension _AppShellLocalFolderPushX on _AppShellState {
  /// Pushes this browser's courses, planner events, and imported calendars
  /// into the folder; returns how many events and calendars the folder
  /// confirmed. A failed item stays in this browser and is logged.
  Future<int> _pushBrowserPlannerData(StorageModeRecord record) async {
    final token = _token ?? kLocalFolderToken;
    final courseIds = <int, int>{};
    for (final course in List<Map<String, dynamic>>.from(_localCourses)) {
      final localId = (course['id'] as num?)?.toInt();
      try {
        final created = await _syncLocalCourse(course);
        final folderId = (created['id'] as num?)?.toInt();
        if (localId != null && folderId != null) courseIds[localId] = folderId;
      } catch (error) {
        log(
          level: DebugLogLevel.warning,
          source: 'Planner.Sync.Courses/push',
          message: 'Local course not copied into the folder: '
              "Planner.Sync.Courses/push \u2014 '${course['title']}' "
              '(${describeRequestFailure(error)}); it stays in this browser.',
        );
      }
    }
    int? mapCourse(Object? raw, String title) {
      final id = (raw as num?)?.toInt();
      if (id == null || id >= 0) return id;
      final mapped = courseIds[id];
      if (mapped == null) {
        log(
          level: DebugLogLevel.warning,
          source: 'Planner.Sync.Events/push',
          message: 'Planner event course dropped: Planner.Sync.Events/push '
              "\u2014 '$title' referred to local category $id, which was not "
              'copied into the folder; the event is uncategorized.',
        );
      }
      return mapped;
    }

    final events = <Map<String, dynamic>>[];
    for (final event in _plannerEvents) {
      if (event['is_local_event'] != true) continue;
      final title = '${event['title'] ?? ''}';
      try {
        await widget.client.createPlannerEvent(token, {
          'title': event['title'],
          'event_date': event['event_date'],
          'starts_at': event['starts_at'],
          'ends_at': event['ends_at'],
          'difficulty_weight': event['difficulty_weight'] ?? 1,
          'description': event['description'] ?? '',
          'course_id': mapCourse(event['course_id'], title),
          'is_completed': event['is_completed'] == true,
          'completed_at': event['completed_at'],
          'client_local_id': 'planner:${event['id']}',
        });
        events.add(event);
      } catch (error) {
        _logItemKept('Planner event', 'Planner.Sync.Events/push', title, error);
      }
    }
    final feeds = <Map<String, dynamic>>[];
    for (final feed in _localCalendarFeeds) {
      final title = '${feed['title'] ?? ''}';
      try {
        await widget.client.createCalendarFeed(token, {
          'title': feed['title'],
          'source_kind': 'I',
          'raw_ical': _icalFromStoredFeed(feed),
          'course_id': mapCourse(feed['course_id'], title),
          'client_local_id': 'planner:${feed['id']}',
        });
        feeds.add(feed);
      } catch (error) {
        _logItemKept(
            'Imported calendar', 'Planner.Sync.Calendar/push', title, error);
      }
    }
    if (events.isEmpty && feeds.isEmpty) return 0;
    // The recovery copy is written before the items leave the lists.
    await _recordPushedToFolder(record.folderId, events, feeds);
    final eventIds = {for (final e in events) e['id']};
    final feedIds = {for (final f in feeds) f['id']};
    _plannerEvents = [
      for (final e in _plannerEvents)
        if (!eventIds.contains(e['id'])) e,
    ];
    _localCalendarFeeds = [
      for (final f in _localCalendarFeeds)
        if (!feedIds.contains(f['id'])) f,
    ];
    _localCache = {..._localCache, 'planner_events': _plannerEvents};
    await _LocalAppStore.saveCache(_localCache);
    await _LocalAppStore.saveCalendarFeeds(_localCalendarFeeds);
    log(
      level: DebugLogLevel.info,
      source: 'Planner.Sync.Events/push',
      message: 'Planner items copied into the folder: '
          'Planner.Sync.Events/push \u2014 ${events.length} planner events and '
          "${feeds.length} imported calendars are now in '${record.folderName}'.",
    );
    return events.length + feeds.length;
  }

  void _logItemKept(String kind, String source, String title, Object error) {
    log(
      level: DebugLogLevel.warning,
      source: source,
      message: '$kind not copied into the folder: $source \u2014 '
          "'$title' (${describeRequestFailure(error)}); it stays in this "
          'browser and is retried on the next first start in a folder.',
    );
  }

  /// Appends one entry to the recovery list and drops entries older than
  /// 30 days (the local recycle bin's TTL).
  Future<void> _recordPushedToFolder(
    String folderId,
    List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> feeds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toUtc();
    final kept = <Object?>[];
    try {
      final raw = jsonDecode(prefs.getString(_kPushedToFolderKey) ?? '[]');
      for (final entry in raw is List ? raw : const []) {
        final at = entry is Map
            ? DateTime.tryParse('${entry['pushed_at']}')
            : null;
        if (at != null && now.difference(at) < _kPushedToFolderTtl) {
          kept.add(entry);
        }
      }
    } on FormatException {
      // An unreadable list is replaced; it held only recovery copies.
    }
    kept.add({
      'folder_id': folderId,
      'pushed_at': now.toIso8601String(),
      'events': events,
      'feeds': feeds,
    });
    await prefs.setString(_kPushedToFolderKey, jsonEncode(kept));
  }

  /// `clearAppSpecificSessionFields`: a cloud logout clears the planner
  /// events as before; a Disconnect (still in folder mode while the
  /// session is cleared, 2.10 rule 4) puts this browser's own cached rows
  /// back, so no folder row reaches `local_cache` afterwards.
  void _clearPlannerSessionFields() {
    if (!inFolderMode) {
      _plannerEvents = const [];
      return;
    }
    List<Map<String, dynamic>> cached(String key) =>
        (_localCache[key] as List<dynamic>? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false);
    _plannerEvents = cached('planner_events');
    _courses = cached('courses').map(decorateRemoteCourse).toList();
    _activity = cached('activity');
    _calendarFeeds = const [];
    _courseNotes = const [];
    _learnerNotes = const [];
    _selectedNote = null;
    _selectedCourse = null;
  }
}

/// Re-serializes a stored local calendar (its parsed `events`, the
/// `IcalEvent.toJson` shape) as iCal for `POST /calendar-feeds/`
/// `raw_ical`. UTC times keep `Z`; device-local times stay floating;
/// all-day events use `VALUE=DATE`.
String _icalFromStoredFeed(Map<String, dynamic> feed) {
  String text(Object? value) => '${value ?? ''}'
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll(RegExp(r'\r?\n'), r'\n');
  String two(int v) => v.toString().padLeft(2, '0');
  String? stamp(Object? raw, bool allDay) {
    final t = DateTime.tryParse('${raw ?? ''}');
    if (t == null) return null;
    final date = '${t.year.toString().padLeft(4, '0')}${two(t.month)}'
        '${two(t.day)}';
    if (allDay) return ';VALUE=DATE:$date';
    return ':${date}T${two(t.hour)}${two(t.minute)}${two(t.second)}'
        '${t.isUtc ? 'Z' : ''}';
  }

  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Notechondria//Planner folder push//EN',
    'X-WR-CALNAME:${text(feed['title'])}',
  ];
  for (final raw in feed['events'] as List<dynamic>? ?? const []) {
    if (raw is! Map) continue;
    final allDay = raw['all_day'] == true;
    final start = stamp(raw['starts_at'], allDay);
    if (start == null) continue;
    final end = stamp(raw['ends_at'], allDay);
    final uid = '${raw['uid'] ?? ''}';
    final description = '${raw['description'] ?? ''}';
    lines.addAll([
      'BEGIN:VEVENT',
      if (uid.isNotEmpty) 'UID:${text(uid)}',
      'SUMMARY:${text(raw['title'])}',
      if (description.isNotEmpty) 'DESCRIPTION:${text(description)}',
      'DTSTART$start',
      if (end != null) 'DTEND$end',
      'END:VEVENT',
    ]);
  }
  lines.add('END:VCALENDAR');
  return '${lines.join('\r\n')}\r\n';
}
