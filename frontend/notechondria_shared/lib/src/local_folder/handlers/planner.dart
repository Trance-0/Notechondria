import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../router.dart';
import 'activity.dart' show isoDate, localDay;
import 'calendar.dart' show feedWeekItems;
import 'history_sessions.dart' show readSessions, sessionCourseLookup, sessionPayload;
import 'lookup.dart';
import 'planner_records.dart';
import 'records.dart';

// Planner routes (F35-F37): planner events with the completion toggle and
// recurrence (`backend/notes/api.py:2141-2223`, `PlannerEventWriteSerializer`
// :595-612), `GET /activity/` (`ActivityApiView`, :2094-2104: the ten most
// recently edited notes), and `GET /activity/week/` (`calendar_week_payload`,
// `backend/notes/services.py:748-890`), which merges events, study sessions,
// and the cached events of enabled feeds. A pushed browser-local event
// carries `client_local_id`; a POST with a known one answers the folder's
// record unchanged (modes_and_migration 7.1). Every write re-reads
// `planner/events.json` inside its exclusive hold (6.2 R2).

/// `CALENDAR_RANGE_DAYS` and `DEFAULT_CALENDAR_RANGE_DAYS`.
const Set<int> kCalendarRangeDays = {3, 7, 30};
const int kDefaultCalendarRangeDays = 7;

const String _consequence = 'Planner event not saved';

void _notNull(BodyFields b, String key) {
  if (b.has(key) && b.body[key] == null) throw b.bad('$key must not be null');
}

String _day(BodyFields b, String key) {
  final day = parseIsoDay(b.string(key));
  if (day == null) throw b.bad('$key must be a date (YYYY-MM-DD)');
  return isoDate(day);
}

String? _instant(BodyFields b, String key) {
  final v = b.string(key);
  if (v == null || v.trim().isEmpty) return null;
  final t = DateTime.tryParse(v.trim()) ??
      (throw b.bad('$key must be an ISO 8601 date and time'));
  return isoInstant(t);
}

int _atLeastOne(BodyFields b, String key) {
  final v = b.integer(key) ?? (throw b.bad('$key must be an integer'));
  if (v < 1) throw b.bad('$key must be at least 1');
  return v;
}

/// `PlannerEventWriteSerializer`: the stored values of the keys present
/// in the body (all required ones on create).
Map<String, Object?> _eventFields(BodyFields b, {required bool partial}) {
  final out = <String, Object?>{};
  for (final key in const [
    'title', 'event_date', 'difficulty_weight', 'is_completed',
    'recurrence_freq', 'recurrence_interval',
  ]) {
    _notNull(b, key);
  }
  if (!partial || b.has('title')) {
    out['title'] = b.string('title', required: true)!.trim();
    if ((out['title'] as String).length > 120) {
      throw b.bad('title is longer than 120 characters');
    }
  }
  if (!partial || b.has('event_date')) {
    if (!b.has('event_date')) throw b.bad('event_date is required');
    out['event_date'] = _day(b, 'event_date');
  }
  for (final key in const ['starts_at', 'ends_at', 'completed_at']) {
    if (b.has(key)) out[key] = _instant(b, key);
  }
  if (b.has('difficulty_weight')) {
    out['difficulty_weight'] = _atLeastOne(b, 'difficulty_weight');
  }
  if (b.has('description')) {
    out['description'] = b.string('description', maxLength: 255) ?? '';
  }
  if (b.has('course_id')) out['course_id'] = b.integer('course_id');
  if (b.has('is_completed')) out['is_completed'] = b.boolean('is_completed');
  if (b.has('recurrence_freq')) {
    out['recurrence_freq'] = b.choice('recurrence_freq', const {'N', 'W', 'M', 'Y'});
  }
  if (b.has('recurrence_interval')) {
    out['recurrence_interval'] = _atLeastOne(b, 'recurrence_interval');
  }
  if (b.has('recurrence_end_date')) {
    out['recurrence_end_date'] =
        b.body['recurrence_end_date'] == null ? null : _day(b, 'recurrence_end_date');
  }
  if (b.has('recurrence_count')) {
    out['recurrence_count'] =
        b.body['recurrence_count'] == null ? null : _atLeastOne(b, 'recurrence_count');
  }
  return out;
}

/// `normalize_planner_event_window` (`backend/notes/api.py:2425-2432`): a
/// missing start is noon of `event_date`, a missing or non-positive window
/// lasts one hour, and `event_date` is the local day of the start.
Map<String, Object?> _normalizeWindow(Map<String, Object?> r) {
  final day = parseIsoDay(jsonString(r['event_date']))!;
  final start = parseInstant(r['starts_at']) ?? localNoon(day);
  var end = parseInstant(r['ends_at']);
  if (end == null || !end.isAfter(start)) end = start.add(const Duration(hours: 1));
  return {
    ...r,
    'starts_at': isoInstant(start),
    'ends_at': isoInstant(end),
    'event_date': isoDate(localDay(start)),
  };
}

Future<CourseLookup> _courses(LocalHandlerContext ctx, {bool write = false}) async =>
    CourseLookup(await readCourses(ctx.fs, skip: write ? lookupSkip(ctx) : ctx.skipPaths));

/// A body `course_id` must name a folder course (`get_object_or_404`).
void _checkCourse(CourseLookup courses, Map<String, Object?> fields) {
  final id = fields['course_id'];
  if (id is int && !courses.byId.containsKey(id)) {
    throw LocalHttpError(404, LocalFolderMessages.courseNotFound(id));
  }
}

int _byDateTitleId(Map<String, Object?> a, Map<String, Object?> b) {
  final d = '${a['event_date']}'.compareTo('${b['event_date']}');
  if (d != 0) return d;
  final t = '${a['title']}'.compareTo('${b['title']}');
  return t != 0 ? t : jsonInt(a['id'])!.compareTo(jsonInt(b['id'])!);
}

/// GET `/planner-events/`: open events unless `include_completed` is `1` or
/// `true`, by date and title, at most `limit` (1 to 200) when given.
Future<LocalResponse> _list(LocalHandlerContext ctx) async {
  final q = ctx.request.query;
  final withDone = const {'1', 'true'}.contains(q['include_completed']);
  final rows = [
    for (final r in usableEvents(await readEventsFile(ctx.fs)))
      if (withDone || r['is_completed'] != true) r,
  ]..sort(_byDateTitleId);
  final limit = int.tryParse((q['limit'] ?? '').trim());
  final courses = await _courses(ctx);
  final take = limit == null ? rows.length : limit.clamp(1, 200);
  return LocalResponse(200, [
    for (final r in rows.take(take)) plannerEventPayload(r, courses),
  ]);
}

/// POST `/planner-events/`; a known `client_local_id` answers 200 with the
/// stored record and writes nothing.
Future<LocalResponse> _create(LocalHandlerContext ctx) async {
  final b = BodyFields(ctx.request.body, consequence: _consequence, process: 'planner');
  final client = b.string('client_local_id', maxLength: 128);
  final clientId = client == null || client.trim().isEmpty ? null : client.trim();
  final file = await readEventsFile(ctx.fs);
  final courses = await _courses(ctx, write: true);
  if (clientId != null) {
    final existing = file.byClientLocalId(clientId);
    if (existing != null) {
      if (parseIsoDay(jsonString(existing['event_date'])) == null) {
        // Answering 201 here would add a second copy of the pushed event.
        throw LocalHttpError(409,
            LocalFolderMessages.eventDateUnreadable(jsonInt(existing['id'])!, clientId));
      }
      return LocalResponse(200, plannerEventPayload(existing, courses));
    }
  }
  final fields = _eventFields(b, partial: false);
  _checkCourse(courses, fields);
  final manifest = await readFolderManifest(ctx.fs) ??
      (throw LocalHttpError(503,
          LocalFolderMessages.manifestMissing(ctx.folderName, importPending: false)));
  final (updated, id) = manifest.allocate('event');
  final now = isoInstant(ctx.now());
  final completed = fields['is_completed'] == true;
  final record = _normalizeWindow({
    'id': id,
    'title': fields['title'],
    'event_date': fields['event_date'],
    'starts_at': fields['starts_at'],
    'ends_at': fields['ends_at'],
    'difficulty_weight': fields['difficulty_weight'] ?? 1,
    'description': fields['description'] ?? '',
    'course_id': fields['course_id'],
    'is_completed': completed,
    'completed_at': fields['completed_at'] ?? (completed ? now : null),
    'recurrence_freq': fields['recurrence_freq'] ?? 'N',
    'recurrence_interval': fields['recurrence_interval'] ?? 1,
    'recurrence_end_date': fields['recurrence_end_date'],
    'recurrence_count': fields['recurrence_count'],
    'date_created': now,
    'last_edit': now,
    if (clientId != null) 'client_local_id': clientId,
  });
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(kPlannerEventsPath, file.encode([...file.records, record])),
    JournalWrite(kManifestPath, updated.encode()),
  ]));
  return LocalResponse(201, plannerEventPayload(record, courses));
}

/// PATCH `/planner-events/{id}/`: the fields present, then the completion
/// rule (true without a time stamps now, false clears it) and the window.
Future<LocalResponse> _update(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  final b = BodyFields(ctx.request.body, consequence: _consequence, process: 'planner');
  final file = await readEventsFile(ctx.fs);
  final at = file.records.indexWhere((r) =>
      jsonInt(r['id']) == id && parseIsoDay(jsonString(r['event_date'])) != null);
  if (at < 0) throw LocalHttpError(404, LocalFolderMessages.eventNotFound(id));
  final fields = _eventFields(b, partial: true);
  final courses = await _courses(ctx, write: true);
  _checkCourse(courses, fields);
  final record = {...file.records[at], ...fields};
  if (fields['is_completed'] == true && record['completed_at'] == null) {
    record['completed_at'] = isoInstant(ctx.now());
  }
  if (fields['is_completed'] == false) record['completed_at'] = null;
  record['last_edit'] = isoInstant(ctx.now());
  final next = [...file.records]..[at] = _normalizeWindow(record);
  await ctx.writeText(kPlannerEventsPath, file.encode(next));
  return LocalResponse(200, plannerEventPayload(next[at], courses));
}

/// GET `/activity/`: the ten most recently edited live notes.
Future<LocalResponse> _activity(LocalHandlerContext ctx) async {
  await refreshNoteListing(ctx, skip: ctx.skipPaths);
  final notes = indexedNotes(ctx.index, skip: ctx.skipPaths)..sort(byLastEditDesc);
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final lookup = CourseLookup(await readCourses(ctx.fs, skip: ctx.skipPaths));
  return LocalResponse(200, [
    for (final n in notes.take(10)) indexedNoteSummary(n, lookup, profile.author),
  ]);
}

final RegExp _leadingDay = RegExp(r'^\d{4}-\d{2}-\d{2}');

/// Python's `sorted` is stable; `List.sort` is not.
List<Map<String, Object?>> _stableSorted(List<Map<String, Object?>> items,
    int Function(Map<String, Object?>, Map<String, Object?>) compare) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// GET `/activity/week/` (`calendar_week_payload`) with `start_date` and
/// `days` (3, 7, or 30).
Future<LocalResponse> _week(LocalHandlerContext ctx) async {
  final q = ctx.request.query;
  final now = ctx.now();
  final today = localDay(now);
  final raw = (q['start_date'] ?? '').trim();
  final start = parseIsoDay(_leadingDay.firstMatch(raw)?[0]) ?? today;
  final asked = int.tryParse((q['days'] ?? '').trim()) ?? kDefaultCalendarRangeDays;
  final count = kCalendarRangeDays.contains(asked) ? asked : kDefaultCalendarRangeDays;
  final days = [for (var i = 0; i < count; i++) start.add(Duration(days: i))];
  final first = days.first, last = days.last;
  final byDay = {for (final d in days) isoDate(d): <Map<String, Object?>>[]};
  final courses = await _courses(ctx);
  final events = usableEvents(await readEventsFile(ctx.fs))..sort(_byDateTitleId);
  for (final r in events.where((r) => r['is_completed'] != true)) {
    for (final occ in EventRule(r).occurrences(first, last)) {
      byDay[isoDate(occ)]!.add({
        ...occurrencePayload(r, courses, occ),
        'kind': 'plan',
        'source_id': jsonInt(r['id']),
      });
    }
  }
  final (_, sessions) = await readSessions(ctx.fs);
  final courseOf = await sessionCourseLookup(ctx);
  for (final s in sessions) {
    final started = parseInstant(s['started_at']);
    if (started == null) continue;
    final key = isoDate(localDay(started));
    byDay[key]?.add(sessionPayload(s, courseOf(s)));
  }
  for (final item in await feedWeekItems(ctx, first, last)) {
    byDay[item.$1]?.add(item.$2);
  }
  // Deadlines: open one-time events from today (40 at most), the next
  // occurrence of each open series within 400 days, then completed events
  // of the window, so a checked item stays in place.
  final deadlines = <Map<String, Object?>>[];
  final listed = <int>{};
  final todayKey = isoDate(today);
  final oneTime = [
    for (final r in events)
      if (!EventRule(r).repeats &&
          r['is_completed'] != true &&
          '${r['event_date']}'.compareTo(todayKey) >= 0)
        r,
  ]..sort((a, b) {
      final s = '${plannerEventPayload(a, courses)['starts_at']}'
          .compareTo('${plannerEventPayload(b, courses)['starts_at']}');
      return s != 0 ? s : _byDateTitleId(a, b);
    });
  for (final r in oneTime.take(40)) {
    listed.add(jsonInt(r['id'])!);
    deadlines.add(deadlinePayload(r, courses, now));
  }
  final horizon = today.add(const Duration(days: 400));
  for (final r in events) {
    final rule = EventRule(r);
    if (!rule.repeats || r['is_completed'] == true) continue;
    final next = rule.occurrences(today, horizon).firstOrNull;
    if (next != null) deadlines.add(deadlinePayload(r, courses, now, occ: next));
  }
  final done = [
    for (final r in events)
      if (r['is_completed'] == true &&
          !parseIsoDay('${r['event_date']}')!.isBefore(first) &&
          !parseIsoDay('${r['event_date']}')!.isAfter(last))
        r,
  ];
  for (final r in done.take(40)) {
    if (listed.add(jsonInt(r['id'])!)) deadlines.add(deadlinePayload(r, courses, now));
  }
  final sortedDeadlines = _stableSorted(deadlines, (a, b) {
    final c = (a['is_completed'] == true ? 1 : 0) - (b['is_completed'] == true ? 1 : 0);
    if (c != 0) return c;
    final u = (b['urgency_score'] as num).compareTo(a['urgency_score'] as num);
    if (u != 0) return u;
    final s = '${a['starts_at'] ?? ''}'.compareTo('${b['starts_at'] ?? ''}');
    return s != 0 ? s : '${a['title'] ?? ''}'.compareTo('${b['title'] ?? ''}');
  });
  return LocalResponse(200, {
    'start_date': isoDate(first),
    'previous_week_start': isoDate(first.subtract(const Duration(days: 7))),
    'next_week_start': isoDate(first.add(const Duration(days: 7))),
    'days': [
      for (final d in days)
        {
          'date': isoDate(d),
          'events': _stableSorted(
              byDay[isoDate(d)]!,
              (a, b) => '${a['starts_at'] ?? '${isoDate(d)}T23:59:00'}'
                  .compareTo('${b['starts_at'] ?? '${isoDate(d)}T23:59:00'}')),
        },
    ],
    'deadlines': sortedDeadlines,
  });
}

List<LocalRoute> plannerRoutes() => [
      LocalRoute('GET', 'planner-events', _list),
      LocalRoute('POST', 'planner-events', _create),
      LocalRoute('PATCH', 'planner-events/{id}', _update),
      LocalRoute('GET', 'activity', _activity),
      LocalRoute('GET', 'activity/week', _week),
    ];
