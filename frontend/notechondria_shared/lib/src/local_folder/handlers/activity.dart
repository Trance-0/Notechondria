import '../folder_fs.dart';
import '../folder_index.dart' show recordListOf;
import '../folder_layout.dart';
import '../router.dart';
import 'lookup.dart';
import 'records.dart';

// The front page from the user's own data (F44) and the activity heatmap
// (F38). The front page lists the folder's courses and notes, private ones
// included, since only the user sees it (decision D1). `planner/heatmap.json`
// holds per-day counts of created notes, written with each note creation
// (`record_note_activity`, `backend/notes/services.py:99-109`); future cells
// sum the `difficulty_weight` of `planner/events.json` (Phase 3 writes it).

/// `{"schema_version": 1, "days": {"YYYY-MM-DD": {"created_notes": n,
/// "peak_words": m}}}`.
const String kHeatmapDaysKey = 'days';

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The local calendar day of [now], as a UTC midnight (day arithmetic in
/// UTC has no DST steps). The backend uses `timezone.localdate()`.
DateTime localDay(DateTime now) {
  final t = now.toLocal();
  return DateTime.utc(t.year, t.month, t.day);
}

/// The text of `planner/heatmap.json` after one more created note with
/// [words] words on [day]; null when [words] is 0 (the backend records no
/// row then).
Future<String?> heatmapWithCreatedNote(
    FolderFs fs, DateTime day, int words) async {
  if (words <= 0) return null;
  final text = await readTextOrNull(fs, kPlannerHeatmapPath);
  final json = (text == null ? null : decodeJsonObject(text)) ?? {};
  final days = json[kHeatmapDaysKey] is Map
      ? Map<String, Object?>.from(json[kHeatmapDaysKey] as Map)
      : <String, Object?>{};
  final key = isoDate(day);
  final old = days[key] is Map ? days[key] as Map : const {};
  final peak = jsonInt(old['peak_words']) ?? 0;
  days[key] = {
    'created_notes': (jsonInt(old['created_notes']) ?? 0) + 1,
    'peak_words': words > peak ? words : peak,
  };
  return encodeFolderJson({
    ...json,
    'schema_version': kFolderSchemaVersion,
    kHeatmapDaysKey: days,
  });
}

/// Per day: the past value of `build_heatmap_payload` (`services.py:112-140`).
Future<Map<String, int>> _pastValues(FolderFs fs) async {
  final text = await readTextOrNull(fs, kPlannerHeatmapPath);
  final days = (text == null ? null : decodeJsonObject(text))?[kHeatmapDaysKey];
  final out = <String, int>{};
  if (days is! Map) return out;
  for (final e in days.entries) {
    final v = e.value;
    if (v is! Map) continue;
    final created = jsonInt(v['created_notes']) ?? 0;
    final peak = jsonInt(v['peak_words']) ?? 0;
    var grade = (peak ~/ 100).clamp(0, 4);
    if (peak > 0 && grade == 0) grade = 1;
    out['${e.key}'] = (created > grade ? created : grade).clamp(0, 4);
  }
  return out;
}

/// The records of `planner/events.json` (empty until Phase 3 writes it).
Future<List<Map<String, Object?>>> readPlannerEvents(FolderFs fs) async {
  final text = await readTextOrNull(fs, kPlannerEventsPath);
  return text == null ? [] : recordListOf(decodeJsonValue(text)) ?? [];
}

/// `build_heatmap_payload` (`backend/notes/services.py:112-178`).
Future<Map<String, Object?>> heatmapPayload(LocalHandlerContext ctx,
    {int daysBefore = 182, int daysAfter = 182}) async {
  final today = localDay(ctx.now());
  final start = today.subtract(Duration(days: daysBefore));
  final end = today.add(Duration(days: daysAfter));
  final startKey = isoDate(start);
  final todayKey = isoDate(today);
  final endKey = isoDate(end);
  final past = {
    for (final e in (await _pastValues(ctx.fs)).entries)
      if (e.key.compareTo(startKey) >= 0 && e.key.compareTo(todayKey) <= 0)
        e.key: e.value,
  };
  final future = <String, int>{};
  for (final event in await readPlannerEvents(ctx.fs)) {
    final date = jsonString(event['event_date']);
    if (date == null ||
        date.compareTo(todayKey) < 0 ||
        date.compareTo(endKey) > 0) {
      continue;
    }
    future[date] = (future[date] ?? 0) + (jsonInt(event['difficulty_weight']) ?? 0);
  }
  final cells = <Map<String, Object?>>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    final key = isoDate(d);
    final p = past[key] ?? 0;
    final f = future[key] ?? 0;
    final kind = d.isBefore(today) ? 'past' : (d.isAfter(today) ? 'future' : 'today');
    cells.add({
      'date': key,
      'kind': kind,
      'past_value': p,
      'future_value': f,
      'intensity': d.isAfter(today) ? (f > 4 ? 4 : f) : p,
      'is_today': key == todayKey,
    });
  }
  int maxOf(Iterable<int> values) =>
      values.fold(0, (m, v) => v > m ? v : m);
  return {
    'today': todayKey,
    'start_date': startKey,
    'end_date': endKey,
    'days_before': daysBefore,
    'days_after': daysAfter,
    'cells': cells,
    'max_past_value': maxOf(past.values),
    'max_future_value': maxOf(future.values),
  };
}

/// GET `/front-page/` (`backend/notes/api.py:647-716`), from the folder.
Future<LocalResponse> _frontPage(LocalHandlerContext ctx) async {
  final courses = await readCourses(ctx.fs, skip: ctx.skipPaths)
    ..sort(compareCourses);
  await refreshNoteListing(ctx, skip: ctx.skipPaths);
  final notes = indexedNotes(ctx.index, skip: ctx.skipPaths)
    ..sort(byLastEditDesc);
  final used = {for (final n in notes) n.courseSlug};
  final carousel =
      await coursePayloads(ctx, courses.where((c) => used.contains(c.slug)).take(6).toList());
  final profile = await FolderProfile.read(ctx.fs, folderName: ctx.folderName);
  final lookup = CourseLookup(courses);
  final recommended = [
    for (final n in notes.take(12)) indexedNoteSummary(n, lookup, profile.author),
  ];
  final todayKey = isoDate(localDay(ctx.now()));
  final upcoming = [
    for (final e in await readPlannerEvents(ctx.fs))
      if ((jsonString(e['event_date']) ?? '').compareTo(todayKey) >= 0 &&
          e['is_completed'] != true)
        {
          for (final kv in e.entries)
            if (kv.key != 'client_local_id' && kv.key != 'schema_version')
              kv.key: kv.value,
        },
  ]..sort((a, b) {
      final d = '${a['event_date']}'.compareTo('${b['event_date']}');
      return d != 0 ? d : '${a['title']}'.compareTo('${b['title']}');
    });
  return LocalResponse(200, {
    'default_course': carousel.isEmpty ? null : carousel.first,
    'carousel_courses': carousel,
    'recent_notes': recommended.take(6).toList(),
    'recommended_notes': recommended,
    'collections': carousel,
    'heatmap': await heatmapPayload(ctx, daysBefore: 364, daysAfter: 28),
    'upcoming_events': upcoming.take(8).toList(),
  });
}

List<LocalRoute> activityRoutes() => [
      LocalRoute('GET', 'front-page', _frontPage),
      LocalRoute('GET', 'heatmap', (ctx) async => LocalResponse(200, await heatmapPayload(ctx))),
    ];
