import 'dart:async';
import 'dart:convert';

import '../../utils/ical_events.dart';
import '../folder_fs.dart';
import '../folder_journal.dart';
import '../folder_layout.dart';
import '../folder_messages.dart';
import '../router.dart';
import 'activity.dart' show isoDate, localDay;
import 'lookup.dart' show lookupSkip;
import 'planner_records.dart';
import 'records.dart';

// Calendar feeds (F40-F43): `planner/feeds.json` holds the
// `CalendarFeedSerializer` fields (`backend/notes/api.py:631-644`) without
// `raw_ical`; `planner/feeds/<id>.ics` holds the imported text or the last
// download. An `.ics` import posts `raw_ical`. A URL subscription (F42) is
// downloaded by the browser through the transport's plain client, outside
// any lock hold, after `normalize_calendar_url`; a host that sends no
// `Access-Control-Allow-Origin` gives no readable answer and the POST is
// refused with the F43 message. A PATCH with `source_url` or with the
// folder-only `refresh: true` downloads again. Events are read with the
// shared offline iCal reader (`utils/ical_events.dart`), which the planner
// already uses for imports; the backend's reader is `parse_ical_events`.

/// The bound of one download; with the lock waits it stays inside the 7 s
/// write deadline (2.9). The backend allows 10 s from the server.
const Duration kCalendarFetchTimeout = Duration(seconds: 5);

String feedIcsPath(int id) => '$kPlannerDir/feeds/$id.ics';

const String _consequence = 'Calendar feed not saved';

// --- normalize_calendar_url (`backend/notes/services.py:399-450`) ---

/// `urllib.parse.quote(value, safe="")`: every byte but A-Z a-z 0-9 `_.-~`.
String _quoteAll(String value) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final c = String.fromCharCode(byte);
    if (RegExp(r'[A-Za-z0-9_.\-~]').hasMatch(c)) {
      out.write(c);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// `base64.urlsafe_b64decode(cid + padding)` decoded as UTF-8 with errors
/// ignored and stripped; null when it does not decode.
String? _decodeCid(String raw) {
  final padded = raw + '=' * ((4 - raw.length % 4) % 4);
  // Python's non-validating decode drops characters outside the alphabet.
  final kept = padded
      .replaceAll('-', '+')
      .replaceAll('_', '/')
      .replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
  final data = kept.replaceAll('=', '');
  if (data.length % 4 == 1) return null;
  try {
    final bytes = base64.decode(data + '=' * ((4 - data.length % 4) % 4));
    return utf8.decode(bytes, allowMalformed: true).replaceAll('\uFFFD', '').trim();
  } on FormatException {
    return null;
  }
}

/// Google Calendar share links (`embed?src=`, `?cid=`) become their
/// `.../ical/<id>/public/basic.ics` form; any other URL is unchanged.
String normalizeCalendarUrl(String url) {
  if (url.isEmpty) return url;
  final parsed = Uri.tryParse(url);
  if (parsed == null) return url;
  final host = parsed.authority.toLowerCase();
  if (!host.contains('calendar.google.com')) return url;
  if (parsed.path.contains('/calendar/ical/')) return url;
  Map<String, List<String>> query;
  try {
    query = parsed.queryParametersAll;
  } on FormatException {
    return url;
  }
  String? first(String key) =>
      (query[key] ?? const <String>[]).where((v) => v.isNotEmpty).firstOrNull;
  var calId = first('src');
  if (calId == null) {
    final cid = first('cid');
    if (cid != null) calId = _decodeCid(cid);
  }
  if (calId == null || calId.isEmpty) return url;
  return 'https://calendar.google.com/calendar/ical/${_quoteAll(calId)}/public/basic.ics';
}

// --- Payloads ---

/// `CalendarFeedSerializer`.
Map<String, Object?> feedPayload(Map<String, Object?> r) => {
      'id': jsonInt(r['id']),
      'title': jsonString(r['title']) ?? '',
      'source_kind': jsonString(r['source_kind']) ?? 'I',
      'source_url': jsonString(r['source_url']) ?? '',
      'is_enabled': r['is_enabled'] != false,
      'course_id': jsonInt(r['course_id']),
      'last_sync': jsonString(r['last_sync']),
      'date_created': jsonString(r['date_created']),
      'last_edit': jsonString(r['last_edit']),
    };

/// `summarize_calendar_feed`: ok, count, the first 25 events by start
/// (title, starts_at), or an error.
Map<String, Object?> importSummary(String raw, {String? error}) {
  if (error != null) {
    return {'ok': false, 'count': 0, 'events': const <Object?>[], 'error': error};
  }
  final events = parseIcalEvents(raw).events;
  if (events.isEmpty) {
    return {
      'ok': false,
      'count': 0,
      'events': const <Object?>[],
      'error': 'No calendar events were found in the imported data.',
    };
  }
  return {
    'ok': true,
    'count': events.length,
    'events': [
      for (final e in events.take(25))
        {'title': e.summary, 'starts_at': isoInstant(e.start)},
    ],
    'error': null,
  };
}

/// Week items of the enabled feeds from their cached `.ics` files, as
/// `calendar_week_payload` builds them (`services.py:794-820`), keyed by
/// the local day of the start; only days in [first, last].
Future<List<(String, Map<String, Object?>)>> feedWeekItems(
    LocalHandlerContext ctx, DateTime first, DateTime last) async {
  final feeds = [
    for (final r in (await readFeedsFile(ctx.fs)).withIds)
      if (r['is_enabled'] != false) r,
  ]..sort((a, b) {
      final t = '${a['title']}'.compareTo('${b['title']}');
      return t != 0 ? t : jsonInt(a['id'])!.compareTo(jsonInt(b['id'])!);
    });
  final out = <(String, Map<String, Object?>)>[];
  for (final feed in feeds) {
    final id = jsonInt(feed['id'])!;
    final path = feedIcsPath(id);
    if (ctx.skipPaths.contains(path)) continue;
    final text = await readTextOrNull(ctx.fs, path);
    if (text == null) continue;
    for (final e in parseIcalEvents(text).events) {
      final day = localDay(e.start);
      if (day.isBefore(first) || day.isAfter(last)) continue;
      out.add((
        isoDate(day),
        {
          'title': e.summary,
          'kind': 'calendar',
          'course_id': jsonInt(feed['course_id']),
          'source_id': id,
          'calendar_title': jsonString(feed['title']) ?? '',
          'starts_at': isoInstant(e.start),
          'ends_at': isoInstant(e.end),
        },
      ));
    }
  }
  return out;
}

// --- Downloads (F42, F43) ---

/// A `source_url` value: blank, or an http(s) URL without credentials
/// (Django's URLValidator also takes ftp, which a browser cannot fetch).
String _sourceUrl(BodyFields b) {
  final url = (b.string('source_url') ?? '').trim();
  if (url.isEmpty) return '';
  final uri = Uri.tryParse(url);
  if (uri == null || !const {'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
    throw b.bad('source_url must be an http or https URL');
  }
  if (uri.userInfo.isNotEmpty) {
    throw b.bad('source_url must not contain a user name or password');
  }
  return url;
}

LocalHttpError _fetchError(int status, String detail) =>
    LocalHttpError(status, scrubRouteDetail(detail));

/// Downloads [sourceUrl] after normalizing it. A failure without an
/// answer is thrown (F43, timeouts); an answer is returned as it is.
Future<LocalFetchAnswer> _download(LocalHandlerContext ctx, String sourceUrl,
    {required bool refresh}) async {
  final target = Uri.parse(normalizeCalendarUrl(sourceUrl));
  // Never the Notechondria server: the app sends this request to its API
  // base, so a feed on that host (any port or scheme) is refused.
  if (target.host.toLowerCase() == ctx.request.url.host.toLowerCase()) {
    throw _fetchError(400, LocalFolderMessages.calendarIsBackend(target.host));
  }
  final LocalFetchAnswer answer;
  try {
    answer = await ctx.fetchCalendarUrl(target, timeout: kCalendarFetchTimeout);
  } on TimeoutException {
    throw _fetchError(504, LocalFolderMessages.calendarTimeout(
        target.host, kCalendarFetchTimeout.inSeconds, refresh: refresh));
  } on LocalHttpError {
    rethrow;
  } catch (_) {
    // The browser hides the cause; a host without CORS headers is the
    // common one (F43).
    throw _fetchError(502, LocalFolderMessages.calendarNoCors(target.host, refresh: refresh));
  }
  if (answer.tooLarge) {
    throw _fetchError(502, LocalFolderMessages.calendarTooLarge(
        target.host, kCalendarFetchMaxBytes, refresh: refresh));
  }
  return answer;
}

bool _ok(LocalFetchAnswer a) => a.status >= 200 && a.status < 300;

const String _notIcal = 'remote feed did not return iCal data (calendar is '
    "likely private; use the 'Secret address in iCal format' instead of the "
    'public share link)';

void _checkCourse(List<CourseRecord> courses, int? id) {
  if (id != null && !courses.any((c) => c.id == id)) {
    throw LocalHttpError(404, LocalFolderMessages.courseNotFound(id));
  }
}

// --- Routes ---

Future<LocalResponse> _list(LocalHandlerContext ctx) async {
  final rows = (await readFeedsFile(ctx.fs)).withIds
    ..sort((a, b) {
      final t = '${a['title']}'.compareTo('${b['title']}');
      return t != 0 ? t : jsonInt(a['id'])!.compareTo(jsonInt(b['id'])!);
    });
  return LocalResponse(200, [for (final r in rows) feedPayload(r)]);
}

/// POST `/calendar-feeds/` (chunked: the download runs between holds).
Future<LocalResponse> _create(LocalHandlerContext ctx) async {
  final b = BodyFields(ctx.request.body, consequence: _consequence, process: 'planner');
  final title = b.string('title', required: true)!.trim();
  if (title.length > 120) throw b.bad('title is longer than 120 characters');
  final kind = b.choice('source_kind', const {'I', 'S'}) ?? 'I';
  final given = _sourceUrl(b);
  final sourceUrl = given.isEmpty ? '' : normalizeCalendarUrl(given);
  final rawIcal = b.string('raw_ical') ?? '';
  final courseId = b.integer('course_id');
  final enabled = b.boolean('is_enabled') ?? true;
  final client = b.string('client_local_id', maxLength: 128);
  final clientId = client == null || client.trim().isEmpty ? null : client.trim();
  Future<Map<String, Object?>?> known() async {
    final file = await readFeedsFile(ctx.fs);
    final existing = clientId == null ? null : file.byClientLocalId(clientId);
    return existing == null ? null : feedPayload(existing);
  }

  if (clientId != null) {
    final existing = await ctx.chunk(known);
    if (existing != null) return LocalResponse(200, existing);
  }
  var ics = rawIcal;
  String? error;
  if (rawIcal.isEmpty && sourceUrl.isNotEmpty) {
    final answer = await _download(ctx, sourceUrl, refresh: false);
    if (!_ok(answer)) {
      error = 'HTTP ${answer.status} fetching the calendar URL.';
    } else if (!answer.body.contains('BEGIN:VCALENDAR')) {
      error = _notIcal;
    } else {
      ics = answer.body;
    }
  }
  return ctx.chunk(() async {
    final existing = await known();
    if (existing != null) return LocalResponse(200, existing);
    final file = await readFeedsFile(ctx.fs);
    _checkCourse(await readCourses(ctx.fs, skip: lookupSkip(ctx)), courseId);
    final manifest = await readFolderManifest(ctx.fs) ??
        (throw LocalHttpError(503,
            LocalFolderMessages.manifestMissing(ctx.folderName, importPending: false)));
    final (updated, id) = manifest.allocate('feed');
    final now = isoInstant(ctx.now());
    final record = <String, Object?>{
      'id': id,
      'title': title,
      'source_kind': kind,
      'source_url': sourceUrl,
      'is_enabled': enabled,
      'course_id': courseId,
      'last_sync': ics.isNotEmpty && rawIcal.isEmpty ? now : null,
      'date_created': now,
      'last_edit': now,
      if (clientId != null) 'client_local_id': clientId,
    };
    await ctx.commit(ctx.journal.newRecord([
      if (ics.isNotEmpty) JournalWrite(feedIcsPath(id), ics),
      JournalWrite(kPlannerFeedsPath, file.encode([...file.records, record])),
      JournalWrite(kManifestPath, updated.encode()),
    ]));
    return LocalResponse(201, {
      ...feedPayload(record),
      'import_summary': importSummary(ics, error: error),
    });
  });
}

/// PATCH `/calendar-feeds/{id}/` (chunked). `raw_ical` replaces the cached
/// text; `source_url` or `refresh: true` downloads the feed again, and a
/// failed download changes nothing.
Future<LocalResponse> _update(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  final b = BodyFields(ctx.request.body, consequence: _consequence, process: 'planner');
  final changes = <String, Object?>{};
  if (b.has('title')) {
    final title = b.string('title', required: true)!.trim();
    if (title.length > 120) throw b.bad('title is longer than 120 characters');
    changes['title'] = title;
  }
  if (b.has('source_kind')) {
    changes['source_kind'] = b.choice('source_kind', const {'I', 'S'}) ??
        (throw b.bad('source_kind must not be null'));
  }
  if (b.has('source_url')) changes['source_url'] = _sourceUrl(b);
  if (b.has('is_enabled')) changes['is_enabled'] = b.boolean('is_enabled') ?? true;
  if (b.has('course_id')) changes['course_id'] = b.integer('course_id');
  final rawIcal = b.has('raw_ical') ? (b.string('raw_ical') ?? '') : null;
  final refresh = b.boolean('refresh') == true;
  Future<Map<String, Object?>> current() async =>
      (await readFeedsFile(ctx.fs)).byId(id) ??
      (throw LocalHttpError(404, LocalFolderMessages.feedNotFound(id)));

  final before = await ctx.chunk(current);
  final url = '${changes['source_url'] ?? before['source_url'] ?? ''}';
  String? fetched;
  if (rawIcal == null && (refresh || (b.has('source_url') && url.isNotEmpty))) {
    if (url.isEmpty) {
      throw LocalHttpError(400, LocalFolderMessages.calendarNoSourceUrl(id));
    }
    final answer = await _download(ctx, url, refresh: true);
    final host = Uri.parse(normalizeCalendarUrl(url)).host;
    if (!_ok(answer)) {
      throw _fetchError(502, LocalFolderMessages.calendarHttpStatus(host, answer.status));
    }
    if (!answer.body.contains('BEGIN:VCALENDAR')) {
      throw _fetchError(502, LocalFolderMessages.calendarNotIcal(host));
    }
    fetched = answer.body;
  }
  return ctx.chunk(() async {
    final file = await readFeedsFile(ctx.fs);
    final at = file.records.indexWhere((r) => jsonInt(r['id']) == id);
    if (at < 0) throw LocalHttpError(404, LocalFolderMessages.feedNotFound(id));
    _checkCourse(await readCourses(ctx.fs, skip: lookupSkip(ctx)),
        changes['course_id'] as int?);
    final now = isoInstant(ctx.now());
    final record = {
      ...file.records[at],
      ...changes,
      if (fetched != null) 'last_sync': now,
      'last_edit': now,
    };
    final next = [...file.records]..[at] = record;
    final ics = fetched ?? rawIcal;
    final path = feedIcsPath(id);
    final removeIcs = ics != null && ics.isEmpty && await ctx.fs.stat(path) != null;
    if (ics == null || (ics.isEmpty && !removeIcs)) {
      await ctx.writeText(kPlannerFeedsPath, file.encode(next));
    } else {
      await ctx.commit(ctx.journal.newRecord([
        if (ics.isNotEmpty) JournalWrite(path, ics),
        JournalWrite(kPlannerFeedsPath, file.encode(next)),
      ], [
        if (removeIcs) JournalRemoval(path),
      ]));
    }
    return LocalResponse(200, feedPayload(record));
  });
}

/// DELETE `/calendar-feeds/{id}/`: the record and its `.ics` file.
Future<LocalResponse> _delete(LocalHandlerContext ctx) async {
  final id = ctx.request.intParam('id');
  final file = await readFeedsFile(ctx.fs);
  if (file.byId(id) == null) throw LocalHttpError(404, LocalFolderMessages.feedNotFound(id));
  final path = feedIcsPath(id);
  await ctx.commit(ctx.journal.newRecord([
    JournalWrite(kPlannerFeedsPath,
        file.encode([for (final r in file.records) if (jsonInt(r['id']) != id) r])),
  ], [
    if (await ctx.fs.stat(path) != null) JournalRemoval(path),
  ]));
  return LocalResponse.noContent;
}

List<LocalRoute> calendarRoutes() => [
      LocalRoute('GET', 'calendar-feeds', _list),
      LocalRoute('POST', 'calendar-feeds', _create, chunked: true),
      LocalRoute('PATCH', 'calendar-feeds/{id}', _update, chunked: true),
      LocalRoute('DELETE', 'calendar-feeds/{id}', _delete),
    ];
