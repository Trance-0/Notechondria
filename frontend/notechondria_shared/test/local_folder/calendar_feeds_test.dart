// Calendar feeds over MemoryFolderFs (F40-F43): `.ics` import into
// planner/feeds/<id>.ics, toggle, edit, delete, the client_local_id upsert
// (7.1), and URL subscribe and refresh through the transport's plain
// calendar client (F42), including the F43 answer for a host without CORS.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:notechondria_shared/src/local_folder/transport.dart';

import 'backend_harness.dart';

final DateTime _noon = DateTime.utc(2026, 10, 19, 12);

const String _ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n'
    'BEGIN:VEVENT\r\nUID:a\r\nSUMMARY:Seminar\r\nDTSTART:20261021T150000Z\r\n'
    'DTEND:20261021T160000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n';

const Set<String> _feedKeys = {
  'id', 'title', 'source_kind', 'source_url', 'is_enabled', 'course_id',
  'last_sync', 'date_created', 'last_edit',
};

/// Stands in for the calendar host: records each request and answers with
/// [respond].
class _CalendarHost extends http.BaseClient {
  _CalendarHost(this.respond);
  Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }
}

Future<http.StreamedResponse> _answer(int status, String body) async =>
    http.StreamedResponse(http.ByteStream.fromBytes(utf8.encode(body)), status);

Future<(LocalFolderController, MemoryFolderFs, LocalFolderTransport, _CalendarHost)>
    _app(Future<http.StreamedResponse> Function(http.BaseRequest) respond) async {
  final (c, fs) = await folderApp(now: () => _noon);
  final host = _CalendarHost(respond);
  return (c, fs, LocalFolderTransport(c, calendarClient: host), host);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('import raw_ical: the text goes to planner/feeds/<id>.ics', () async {
    final (c, fs, t, host) = await _app((_) => _answer(500, ''));
    final r = await callApi(c, 'POST', '/calendar-feeds/',
        json: {'title': ' Seminars ', 'source_kind': 'I', 'raw_ical': _ics}, client: t);
    expect(r.statusCode, 201, reason: r.body);
    final feed = mapOf(r);
    expect(feed.keys.toSet(), {..._feedKeys, 'import_summary'});
    expect(feed['title'], 'Seminars');
    expect(feed['source_url'], '');
    expect(feed['import_summary'], {
      'ok': true,
      'count': 1,
      'events': [{'title': 'Seminar', 'starts_at': '2026-10-21T15:00:00.000Z'}],
      'error': null,
    });
    expect(fs.textOf('planner/feeds/${feed['id']}.ics'), _ics);
    final stored = jsonDecode(fs.textOf(kPlannerFeedsPath)!) as Map;
    expect(((stored['feeds'] as List).single as Map).containsKey('raw_ical'), isFalse);
    expect(host.requests, isEmpty);

    final empty = mapOf(await callApi(c, 'POST', '/calendar-feeds/',
        json: {'title': 'Empty', 'raw_ical': 'BEGIN:VCALENDAR\nEND:VCALENDAR'}));
    expect((empty['import_summary'] as Map)['ok'], isFalse);
    expect((empty['import_summary'] as Map)['error'],
        'No calendar events were found in the imported data.');
  });

  test('list, toggle, edit, and delete (F41)', () async {
    final (c, fs) = await folderApp(now: () => _noon);
    final b = mapOf(await callApi(c, 'POST', '/calendar-feeds/', json: {'title': 'B', 'raw_ical': _ics}));
    final a = mapOf(await callApi(c, 'POST', '/calendar-feeds/', json: {'title': 'A', 'raw_ical': _ics}));
    final listed = listOf(await callApi(c, 'GET', '/calendar-feeds/'));
    expect([for (final f in listed) f['title']], ['A', 'B']);
    expect(listed.first.keys.toSet(), _feedKeys);
    final off = await callApi(c, 'PATCH', '/calendar-feeds/${b['id']}/',
        json: {'is_enabled': false, 'title': 'B2'});
    expect(off.statusCode, 200, reason: off.body);
    expect(mapOf(off)['is_enabled'], isFalse);
    expect(mapOf(off)['title'], 'B2');
    final week = mapOf(await callApi(c, 'GET', '/activity/week/?start_date=2026-10-19'));
    final wed = ((week['days'] as List)[2] as Map)['events'] as List;
    expect([for (final e in wed) (e as Map)['source_id']], [a['id']]);

    final replaced = await callApi(c, 'PATCH', '/calendar-feeds/${a['id']}/',
        json: {'raw_ical': _ics.replaceAll('Seminar', 'Talk')});
    expect(replaced.statusCode, 200);
    expect(fs.textOf('planner/feeds/${a['id']}.ics'), contains('Talk'));

    final gone = await callApi(c, 'DELETE', '/calendar-feeds/${a['id']}/');
    expect(gone.statusCode, 204);
    expect(fs.exists('planner/feeds/${a['id']}.ics'), isFalse);
    expect([for (final f in listOf(await callApi(c, 'GET', '/calendar-feeds/'))) f['id']], [b['id']]);
    final missing = await callApi(c, 'DELETE', '/calendar-feeds/${a['id']}/');
    expect(missing.statusCode, 404);
    expect(detailOf(missing), LocalFolderMessages.feedNotFound(a['id'] as int));
    final noCourse = await callApi(c, 'POST', '/calendar-feeds/',
        json: {'title': 'C', 'raw_ical': _ics, 'course_id': 77});
    expect(noCourse.statusCode, 404);
    final bad = await callApi(c, 'POST', '/calendar-feeds/',
        json: {'title': 'C', 'source_url': 'webcal://example.com/a.ics'});
    expect(bad.statusCode, 400);
    final creds = await callApi(c, 'POST', '/calendar-feeds/',
        json: {'title': 'C', 'source_url': 'https://u:p@example.com/a.ics'});
    expect(creds.statusCode, 400);
    expect(fs.textOf(kPlannerFeedsPath), isNot(contains('u:p@')));
  });

  test('a repeated client_local_id push changes nothing (7.1)', () async {
    final (c, fs) = await folderApp(now: () => _noon);
    final body = {'title': 'Pushed', 'raw_ical': _ics, 'client_local_id': 'planner:feed-3'};
    final first = await callApi(c, 'POST', '/calendar-feeds/', json: body);
    expect(first.statusCode, 201);
    final feeds = fs.textOf(kPlannerFeedsPath);
    final manifest = fs.textOf(kManifestPath);
    final again = await callApi(c, 'POST', '/calendar-feeds/',
        json: {...body, 'title': 'Other title'});
    expect(again.statusCode, 200, reason: again.body);
    expect(mapOf(again)['id'], mapOf(first)['id']);
    expect(mapOf(again)['title'], 'Pushed');
    expect(fs.textOf(kPlannerFeedsPath), feeds);
    expect(fs.textOf(kManifestPath), manifest);
  });

  test('subscribe by URL: one plain GET to the normalized URL (F42)', () async {
    final (c, fs, t, host) = await _app((_) => _answer(200, _ics));
    final r = await callApi(c, 'POST', '/calendar-feeds/', client: t, json: {
      'title': 'Team',
      'source_kind': 'S',
      'source_url': 'https://calendar.google.com/calendar/embed?src=team%40group.calendar.google.com',
    });
    expect(r.statusCode, 201, reason: r.body);
    final feed = mapOf(r);
    const ical = 'https://calendar.google.com/calendar/ical/team%40group.calendar.google.com/public/basic.ics';
    expect(feed['source_url'], ical);
    expect(feed['last_sync'], _noon.toIso8601String());
    expect((feed['import_summary'] as Map)['count'], 1);
    expect(fs.textOf('planner/feeds/${feed['id']}.ics'), _ics);
    final sent = host.requests.single;
    expect(sent.method, 'GET');
    expect('${sent.url}', ical);
    expect(sent.headers.keys.map((k) => k.toLowerCase()), ['accept']);

    // Refresh: PATCH with refresh: true downloads again.
    host.respond = (_) => _answer(200, _ics.replaceAll('Seminar', 'Retro'));
    final refreshed = await callApi(c, 'PATCH', '/calendar-feeds/${feed['id']}/',
        json: {'refresh': true}, client: t);
    expect(refreshed.statusCode, 200, reason: refreshed.body);
    expect(fs.textOf('planner/feeds/${feed['id']}.ics'), contains('Retro'));
    expect(host.requests, hasLength(2));
    expect(mapOf(refreshed).keys.toSet(), _feedKeys);
  });

  test('a host without CORS headers: the F43 answer, nothing written', () async {
    final (c, fs, t, host) =
        await _app((_) => Future.error(http.ClientException('XMLHttpRequest error.')));
    final before = fs.paths.toSet();
    final r = await callApi(c, 'POST', '/calendar-feeds/', client: t,
        json: {'title': 'Private', 'source_kind': 'S', 'source_url': 'https://cal.example.org/a.ics'});
    expect(r.statusCode, 502, reason: r.body);
    expect(detailOf(r), LocalFolderMessages.calendarNoCors('cal.example.org'));
    expect(detailOf(r), startsWith('Calendar not subscribed: Shared.LocalFolder.Backend/calendar.fetch — '));
    expect(containsSessionRejectionSentinel(detailOf(r)), isFalse);
    expect(containsDeepLinkPrivateNoteMarker(detailOf(r)), isFalse);
    expect(fs.paths.toSet(), before);
    expect(host.requests, hasLength(1));

    // A refresh that fails keeps the stored feed and its other fields.
    host.respond = (_) => _answer(200, _ics);
    final feed = mapOf(await callApi(c, 'POST', '/calendar-feeds/', client: t,
        json: {'title': 'Ok', 'source_url': 'https://cal.example.org/b.ics'}));
    host.respond = (_) => Future.error(http.ClientException('Failed to fetch'));
    final text = fs.textOf(kPlannerFeedsPath);
    final failed = await callApi(c, 'PATCH', '/calendar-feeds/${feed['id']}/', client: t,
        json: {'refresh': true, 'title': 'Renamed'});
    expect(failed.statusCode, 502);
    expect(detailOf(failed), LocalFolderMessages.calendarNoCors('cal.example.org', refresh: true));
    expect(fs.textOf(kPlannerFeedsPath), text);
  });

  test('other download failures', () async {
    final (c, fs, t, host) = await _app((_) => _answer(404, 'gone'));
    // An HTTP error at subscribe keeps the backend's shape: 201, ok false.
    final r = await callApi(c, 'POST', '/calendar-feeds/', client: t,
        json: {'title': 'Gone', 'source_url': 'https://cal.example.org/x.ics'});
    expect(r.statusCode, 201, reason: r.body);
    final feed = mapOf(r);
    expect(feed['import_summary'],
        {'ok': false, 'count': 0, 'events': [], 'error': 'HTTP 404 fetching the calendar URL.'});
    expect(fs.exists('planner/feeds/${feed['id']}.ics'), isFalse);
    final refresh = await callApi(c, 'PATCH', '/calendar-feeds/${feed['id']}/',
        client: t, json: {'refresh': true});
    expect(refresh.statusCode, 502);
    expect(detailOf(refresh), LocalFolderMessages.calendarHttpStatus('cal.example.org', 404));
    host.respond = (_) => _answer(200, '<html>sign in</html>');
    final html = await callApi(c, 'PATCH', '/calendar-feeds/${feed['id']}/',
        client: t, json: {'refresh': true});
    expect(detailOf(html), LocalFolderMessages.calendarNotIcal('cal.example.org'));
    host.respond = (_) => Completer<http.StreamedResponse>().future;
    final slow = await callApi(c, 'POST', '/calendar-feeds/', client: t,
        json: {'title': 'Slow', 'source_url': 'https://cal.example.org/slow.ics'});
    expect(slow.statusCode, 504);
    expect(detailOf(slow), LocalFolderMessages.calendarTimeout('cal.example.org', 5));
    // Never the Notechondria server, and no request leaves for it.
    final count = host.requests.length;
    final own = await callApi(c, 'POST', '/calendar-feeds/', client: t,
        json: {'title': 'Own', 'source_url': 'https://notechondria.trance-0.com/media/a.ics'});
    expect(own.statusCode, 400);
    expect(detailOf(own), LocalFolderMessages.calendarIsBackend('notechondria.trance-0.com'));
    expect(host.requests, hasLength(count));
    final noUrl = mapOf(await callApi(c, 'POST', '/calendar-feeds/', json: {'title': 'F', 'raw_ical': _ics}));
    final cannot = await callApi(c, 'PATCH', '/calendar-feeds/${noUrl['id']}/',
        client: t, json: {'refresh': true});
    expect(cannot.statusCode, 400);
    expect(detailOf(cannot), LocalFolderMessages.calendarNoSourceUrl(noUrl['id'] as int));
  }, timeout: const Timeout(Duration(seconds: 30)));
}
