import '../folder_fs.dart';
import '../folder_index.dart' show recordListKeyOf, recordListOf;
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../router.dart' show LocalHttpError;
import 'activity.dart' show isoDate;
import 'records.dart';

// Planner records (F35-F37): `planner/events.json` and `planner/feeds.json`
// as files of records, the `planner_event_payload` shape, and the recurrence
// expansion and deadline urgency of `backend/notes/services.py:182-307`.
// Dates are UTC midnights of calendar days, so day arithmetic has no DST
// steps; instants are stored as UTC ISO 8601 text. The backend's
// `timezone.localdate()` and server time zone are the browser's here.

/// A records file read from disk: the object it was (null for a bare list
/// or a missing file), its records, and the key the list sits under.
class PlannerFile {
  PlannerFile(this.path, this.container, this.records, this.key,
      {this.unreadable = false, this.consequence = 'Change not saved'});

  final String path;
  final Map<String, Object?>? container;

  /// Every object record of the file, as read; writes keep the ones the
  /// answers skip (no integer `id`), so a hand-edited row is never dropped.
  final List<Map<String, Object?>> records;
  final String key;

  /// The file exists but is not a records file (202-N6): reads answer it
  /// as empty, and [encode] refuses, so a write never replaces it.
  final bool unreadable;

  /// The 1.8 consequence of a refused write.
  final String consequence;

  /// Records with an integer `id`.
  List<Map<String, Object?>> get withIds =>
      [for (final r in records) if (jsonInt(r['id']) != null) r];

  Map<String, Object?>? byId(int id) {
    for (final r in records) {
      if (jsonInt(r['id']) == id) return r;
    }
    return null;
  }

  /// The record pushed with [clientLocalId] (modes_and_migration 7.1).
  Map<String, Object?>? byClientLocalId(String clientLocalId) {
    for (final r in records) {
      if (jsonInt(r['id']) != null && r['client_local_id'] == clientLocalId) {
        return r;
      }
    }
    return null;
  }

  /// The file's text with [next] as its records, in the file's own shape.
  /// Throws a 503 for an [unreadable] file (202-N6).
  String encode(List<Map<String, Object?>> next) {
    if (unreadable) {
      throw LocalHttpError(503,
          LocalFolderMessages.unreadableFolderFile(consequence, 'planner', path));
    }
    final container = this.container;
    final listKey = container == null ? null : recordListKeyOf(container);
    return encodeFolderJson({
      ...?container,
      'schema_version': kFolderSchemaVersion,
      listKey ?? key: next,
    });
  }
}

Future<PlannerFile> readPlannerFile(FolderFs fs, String path, String key,
    {String consequence = 'Change not saved'}) async {
  final text = await readTextOrNull(fs, path);
  if (text == null) return PlannerFile(path, null, [], key, consequence: consequence);
  final json = decodeJsonValue(text);
  return PlannerFile(path, json is Map ? Map<String, Object?>.from(json) : null,
      recordListOf(json) ?? [], key,
      unreadable: !isRecordsFileJson(json, key), consequence: consequence);
}

/// Whether [json] (decoded, null when it did not parse) is a records file a
/// write can rewrite without losing data: a list, or an object whose
/// [key] is absent or a list (202-N6).
bool isRecordsFileJson(Object? json, String key) =>
    json is List || (json is Map && (!json.containsKey(key) || json[key] is List));

Future<PlannerFile> readEventsFile(FolderFs fs) => readPlannerFile(
    fs, kPlannerEventsPath, 'events', consequence: 'Planner event not saved');

Future<PlannerFile> readFeedsFile(FolderFs fs) => readPlannerFile(
    fs, kPlannerFeedsPath, 'feeds', consequence: 'Calendar feed not saved');

final RegExp _isoDay = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');

/// A `YYYY-MM-DD` day (Django's `parse_date`) as a UTC midnight, or null.
DateTime? parseIsoDay(String? text) {
  final m = text == null ? null : _isoDay.firstMatch(text.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final day = DateTime.utc(y, mo, d);
  return day.year == y && day.month == mo && day.day == d ? day : null;
}

DateTime? parseInstant(Object? value) =>
    value is String && value.trim().isNotEmpty ? DateTime.tryParse(value.trim()) : null;

String isoInstant(DateTime t) => t.toUtc().toIso8601String();

/// `datetime.combine(day, 12:00)` made aware in the local time zone.
DateTime localNoon(DateTime day) => DateTime(day.year, day.month, day.day, 12);

// --- Recurrence (`services.py:215-278`) ---

/// `_MAX_OCCURRENCES`: the bound of one expansion.
const int kMaxOccurrences = 4000;

/// `_add_months`: the day clamps to the last day of the target month.
DateTime addMonths(DateTime base, int months) {
  final index = base.month - 1 + months;
  final year = base.year + (index ~/ 12);
  final month = index % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, base.day < lastDay ? base.day : lastDay);
}

/// `_add_period`: the date [step] recurrences after [base].
DateTime addPeriod(DateTime base, String freq, int interval, int step) =>
    switch (freq) {
      'W' => base.add(Duration(days: 7 * interval * step)),
      'M' => addMonths(base, interval * step),
      'Y' => addMonths(base, 12 * interval * step),
      _ => base,
    };

/// The recurrence fields of an event record.
class EventRule {
  EventRule(Map<String, Object?> r)
      : base = parseIsoDay(jsonString(r['event_date']))!,
        freq = _freq(r['recurrence_freq']),
        interval = jsonInt(r['recurrence_interval']) ?? 1,
        endDate = parseIsoDay(jsonString(r['recurrence_end_date'])),
        count = jsonInt(r['recurrence_count']);

  final DateTime base;
  final String freq;
  final int interval;
  final DateTime? endDate;
  final int? count;

  /// A value outside N/W/M/Y (only a hand edit makes one) does not repeat;
  /// the backend's `_add_period` would repeat its base date instead.
  static String _freq(Object? v) =>
      v is String && const {'W', 'M', 'Y'}.contains(v) ? v : 'N';

  bool get repeats => freq != 'N';

  /// `_expand_occurrence_dates`: the occurrences in [start, end], with
  /// `recurrence_end_date` inclusive and `recurrence_count` counting the
  /// first occurrence.
  Iterable<DateTime> occurrences(DateTime start, DateTime end) sync* {
    if (!repeats) {
      if (!base.isBefore(start) && !base.isAfter(end)) yield base;
      return;
    }
    final every = interval < 1 ? 1 : interval;
    for (var step = 0; step < kMaxOccurrences; step++) {
      if (count != null && step >= count!) return;
      final occ = addPeriod(base, freq, every, step);
      if (endDate != null && occ.isAfter(endDate!)) return;
      if (occ.isAfter(end)) return;
      if (!occ.isBefore(start)) yield occ;
    }
  }
}

/// Event records an answer can use: an integer `id` and a readable
/// `event_date`.
List<Map<String, Object?>> usableEvents(PlannerFile file) => [
      for (final r in file.withIds)
        if (parseIsoDay(jsonString(r['event_date'])) != null) r,
    ];

// --- Payloads ---

/// `planner_event_payload` (`services.py:182-212`). The course comes from
/// `courses/`; a `course_id` that names no course answers null.
Map<String, Object?> plannerEventPayload(
    Map<String, Object?> r, CourseLookup courses) {
  final day = parseIsoDay(jsonString(r['event_date']))!;
  final startsAt = parseInstant(r['starts_at']) ?? localNoon(day);
  final endsAt = parseInstant(r['ends_at']) ?? startsAt.add(const Duration(hours: 1));
  final courseId = jsonInt(r['course_id']);
  final course = courseId == null ? null : courses.byId[courseId];
  return {
    'id': jsonInt(r['id']),
    'title': jsonString(r['title']) ?? '',
    'event_date': isoDate(day),
    'starts_at': isoInstant(startsAt),
    'ends_at': isoInstant(endsAt),
    'difficulty_weight': jsonInt(r['difficulty_weight']) ?? 1,
    'description': jsonString(r['description']) ?? '',
    'course_id': course?.id,
    'course': course == null
        ? null
        : {
            'id': course.id,
            'title': course.title,
            'slug': course.slug,
            'color_hue': jsonInt(course.json['color_hue']),
          },
    'is_completed': r['is_completed'] == true,
    'completed_at': jsonString(r['completed_at']),
    'recurrence_freq': EventRule._freq(r['recurrence_freq']),
    'recurrence_interval': jsonInt(r['recurrence_interval']) ?? 1,
    'recurrence_end_date': jsonString(r['recurrence_end_date']),
    'recurrence_count': jsonInt(r['recurrence_count']),
  };
}

/// `_occurrence_payload`: start and end move by the days between the base
/// and [occ], so the time of day is kept; `occurrence_date` is added.
Map<String, Object?> occurrencePayload(
    Map<String, Object?> r, CourseLookup courses, DateTime occ) {
  final payload = plannerEventPayload(r, courses);
  final delta = occ.difference(parseIsoDay('${payload['event_date']}')!).inDays;
  if (delta != 0) {
    for (final key in const ['starts_at', 'ends_at']) {
      payload[key] =
          isoInstant(DateTime.parse('${payload[key]}').add(Duration(days: delta)));
    }
  }
  payload['event_date'] = isoDate(occ);
  payload['occurrence_date'] = isoDate(occ);
  return payload;
}

/// `planner_deadline_payload`: `urgency_score` is the weight over the hours
/// left (at least one minute), rounded to 4 places.
Map<String, Object?> deadlinePayload(
    Map<String, Object?> r, CourseLookup courses, DateTime now,
    {DateTime? occ}) {
  final payload =
      occ == null ? plannerEventPayload(r, courses) : occurrencePayload(r, courses, occ);
  final startsAt = DateTime.parse('${payload['starts_at']}');
  var hours = startsAt.difference(now).inMicroseconds / Duration.microsecondsPerHour;
  if (hours < 1 / 60) hours = 1 / 60;
  final weight = jsonInt(payload['difficulty_weight']) ?? 1;
  payload['urgency_score'] = (weight / hours * 10000).round() / 10000;
  return payload;
}
