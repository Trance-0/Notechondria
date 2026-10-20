// Planner routes over MemoryFolderFs (F35-F38): events with the completion
// toggle and recurrence, the client_local_id upsert (7.1), `/activity/`,
// the week view merging events, sessions, and feed events, deadlines, the
// heatmap's future cells, and the course-delete cascade (3.5).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';

import 'backend_harness.dart';

final DateTime _noon = DateTime.utc(2026, 10, 19, 12);

const Set<String> _eventKeys = {
  'id', 'title', 'event_date', 'starts_at', 'ends_at', 'difficulty_weight',
  'description', 'course_id', 'course', 'is_completed', 'completed_at',
  'recurrence_freq', 'recurrence_interval', 'recurrence_end_date',
  'recurrence_count',
};

List<Map<String, Object?>> _stored(MemoryFolderFs fs) => [
      for (final r in (jsonDecode(fs.textOf(kPlannerEventsPath)!) as Map)['events'] as List)
        Map<String, Object?>.from(r as Map),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planner events', () {
    test('create, list, and patch; the window is normalized', () async {
      final (c, fs) = await folderApp(now: () => _noon);
      final course = mapOf(await callApi(c, 'POST', '/courses/',
          json: {'title': 'Bio', 'color_hue': 120}));
      final r = await callApi(c, 'POST', '/planner-events/', json: {
        'title': '  Exam  ',
        'event_date': '2026-10-21',
        'difficulty_weight': 3,
        'course_id': course['id'],
      });
      expect(r.statusCode, 201, reason: r.body);
      final e = mapOf(r);
      expect(e.keys.toSet(), _eventKeys);
      expect(e['title'], 'Exam');
      expect(e['course'], {'id': course['id'], 'title': 'Bio', 'slug': 'bio', 'color_hue': 120});
      expect(e['recurrence_freq'], 'N');
      expect(e['description'], '');
      final start = DateTime.parse('${e['starts_at']}');
      expect(start.toLocal().hour, 12);
      expect(DateTime.parse('${e['ends_at']}').difference(start), const Duration(hours: 1));
      final manifest = (await readFolderManifest(fs))!;
      expect(manifest.idCounters['event'], e['id']);

      // An end before the start becomes start + 1 h; event_date follows starts_at.
      final timed = mapOf(await callApi(c, 'POST', '/planner-events/', json: {
        'title': 'Lab',
        'event_date': '2026-10-30',
        'starts_at': '2026-10-22T09:00:00Z',
        'ends_at': '2026-10-22T08:00:00Z',
      }));
      expect(timed['event_date'], '2026-10-22');
      expect(timed['ends_at'], '2026-10-22T10:00:00.000Z');

      final listed = listOf(await callApi(c, 'GET', '/planner-events/'));
      expect([for (final x in listed) x['title']], ['Exam', 'Lab']);

      final patched = await callApi(c, 'PATCH', '/planner-events/${e['id']}/',
          json: {'title': 'Final exam', 'description': 'Room 4'});
      expect(patched.statusCode, 200, reason: patched.body);
      expect(mapOf(patched)['title'], 'Final exam');
      expect(mapOf(patched)['description'], 'Room 4');
      expect(mapOf(patched)['starts_at'], e['starts_at']);
      expect(_stored(fs).first.containsKey('last_edit'), isTrue);
    });

    test('completion toggle stamps and clears completed_at; list hides done', () async {
      final (c, _) = await folderApp(now: () => _noon);
      final e = mapOf(await callApi(c, 'POST', '/planner-events/',
          json: {'title': 'Essay', 'event_date': '2026-10-20'}));
      final done = mapOf(await callApi(c, 'PATCH', '/planner-events/${e['id']}/',
          json: {'is_completed': true}));
      expect(done['is_completed'], isTrue);
      expect(done['completed_at'], _noon.toIso8601String());
      expect(listOf(await callApi(c, 'GET', '/planner-events/')), isEmpty);
      final all = listOf(await callApi(c, 'GET', '/planner-events/?include_completed=1'));
      expect(all.single['id'], e['id']);
      final undone = mapOf(await callApi(c, 'PATCH', '/planner-events/${e['id']}/',
          json: {'is_completed': false}));
      expect(undone['completed_at'], isNull);
      final created = mapOf(await callApi(c, 'POST', '/planner-events/',
          json: {'title': 'Done already', 'event_date': '2026-10-20', 'is_completed': true}));
      expect(created['completed_at'], isNotNull);
    });

    test('validation answers 400 with a 1.8 detail; unknown ids 404', () async {
      final (c, _) = await folderApp(now: () => _noon);
      for (final body in [
        {'event_date': '2026-10-20'},
        {'title': 'x'},
        {'title': ' ', 'event_date': '2026-10-20'},
        {'title': 'x', 'event_date': '20/10/2026'},
        {'title': 'x', 'event_date': '2026-10-20', 'difficulty_weight': 0},
        {'title': 'x', 'event_date': '2026-10-20', 'recurrence_freq': 'D'},
        {'title': 'x', 'event_date': '2026-10-20', 'recurrence_count': 0},
        {'title': 'x', 'event_date': '2026-10-20', 'starts_at': 'soon'},
        {'title': 'x' * 121, 'event_date': '2026-10-20'},
      ]) {
        final r = await callApi(c, 'POST', '/planner-events/', json: body);
        expect(r.statusCode, 400, reason: '$body ${r.body}');
        expect(detailOf(r), startsWith('Planner event not saved: Shared.LocalFolder.Backend/planner — '));
      }
      final noCourse = await callApi(c, 'POST', '/planner-events/',
          json: {'title': 'x', 'event_date': '2026-10-20', 'course_id': 99});
      expect(noCourse.statusCode, 404);
      expect(detailOf(noCourse), LocalFolderMessages.courseNotFound(99));
      final missing = await callApi(c, 'PATCH', '/planner-events/5/', json: {'title': 'y'});
      expect(missing.statusCode, 404);
      expect(detailOf(missing), LocalFolderMessages.eventNotFound(5));
    });

    test('a repeated client_local_id push changes nothing (7.1)', () async {
      final (c, fs) = await folderApp(now: () => _noon);
      final body = {
        'title': 'Pushed',
        'event_date': '2026-10-24',
        'client_local_id': 'planner:local-17',
      };
      final first = await callApi(c, 'POST', '/planner-events/', json: body);
      expect(first.statusCode, 201);
      final text = fs.textOf(kPlannerEventsPath);
      final manifest = fs.textOf(kManifestPath);
      // Edited in the folder, then pushed again from another app.
      await callApi(c, 'PATCH', '/planner-events/${mapOf(first)['id']}/',
          json: {'title': 'Edited in folder'});
      final edited = fs.textOf(kPlannerEventsPath);
      expect(edited, isNot(text));
      final again = await callApi(c, 'POST', '/planner-events/',
          json: {...body, 'title': 'Pushed again', 'course_id': 42});
      expect(again.statusCode, 200, reason: again.body);
      expect(mapOf(again)['id'], mapOf(first)['id']);
      expect(mapOf(again)['title'], 'Edited in folder');
      expect(mapOf(again).containsKey('client_local_id'), isFalse);
      expect(fs.textOf(kPlannerEventsPath), edited);
      expect(fs.textOf(kManifestPath), manifest);
      expect(_stored(fs), hasLength(1));
      expect(_stored(fs).single['client_local_id'], 'planner:local-17');
    });

    test('course delete nulls course_id in events and feeds (3.5)', () async {
      final (c, fs) = await folderApp(now: () => _noon);
      final course = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'Bio'}));
      final e = mapOf(await callApi(c, 'POST', '/planner-events/', json: {
        'title': 'Exam', 'event_date': '2026-10-21', 'course_id': course['id'],
      }));
      final f = mapOf(await callApi(c, 'POST', '/calendar-feeds/', json: {
        'title': 'Lectures', 'raw_ical': _ics, 'course_id': course['id'],
      }));
      expect(f['course_id'], course['id']);
      expect((await callApi(c, 'DELETE', '/courses/${course['id']}/')).statusCode, 204);
      final events = listOf(await callApi(c, 'GET', '/planner-events/'));
      expect(events.single['id'], e['id']);
      expect(events.single['course_id'], isNull);
      expect(events.single['course'], isNull);
      expect(_stored(fs).single['course_id'], isNull);
      final feeds = listOf(await callApi(c, 'GET', '/calendar-feeds/'));
      expect(feeds.single['course_id'], isNull);
    });
  });

  group('activity', () {
    test('GET /activity/ lists the ten most recently edited notes', () async {
      final (c, _) = await folderApp(now: () => _noon);
      for (var i = 0; i < 12; i++) {
        await createNote(c, title: 'n$i');
      }
      final r = await callApi(c, 'GET', '/activity/');
      expect(r.statusCode, 200, reason: r.body);
      final rows = listOf(r);
      expect(rows, hasLength(10));
      expect(rows.first.containsKey('preview_lines'), isTrue);
    });

    test('the week merges plan occurrences, sessions, and feed events', () async {
      final (c, _) = await folderApp(now: () => _noon);
      final note = await createNote(c, title: 'Notes');
      final weekly = mapOf(await callApi(c, 'POST', '/planner-events/', json: {
        'title': 'Lab',
        'event_date': '2026-10-05',
        'starts_at': '2026-10-05T14:00:00Z',
        'recurrence_freq': 'W',
        'difficulty_weight': 2,
      }));
      await callApi(c, 'POST', '/planner-events/', json: {
        'title': 'Exam', 'event_date': '2026-10-21', 'difficulty_weight': 3,
      });
      final done = mapOf(await callApi(c, 'POST', '/planner-events/', json: {
        'title': 'Old essay', 'event_date': '2026-10-20', 'is_completed': true,
      }));
      await callApi(c, 'POST', '/note-sessions/', json: {
        'note_id': note['id'], 'started_at': '2026-10-20T08:00:00Z',
      });
      final feed = mapOf(await callApi(c, 'POST', '/calendar-feeds/',
          json: {'title': 'Lectures', 'raw_ical': _ics}));
      final off = mapOf(await callApi(c, 'POST', '/calendar-feeds/',
          json: {'title': 'Hidden', 'raw_ical': _ics}));
      await callApi(c, 'PATCH', '/calendar-feeds/${off['id']}/', json: {'is_enabled': false});

      final r = await callApi(c, 'GET', '/activity/week/?start_date=2026-10-19');
      expect(r.statusCode, 200, reason: r.body);
      final week = mapOf(r);
      expect(week['start_date'], '2026-10-19');
      expect(week['previous_week_start'], '2026-10-12');
      expect(week['next_week_start'], '2026-10-26');
      final days = week['days'] as List;
      expect([for (final d in days) (d as Map)['date']].first, '2026-10-19');
      expect(days, hasLength(7));
      Map day(String date) => days.firstWhere((d) => (d as Map)['date'] == date) as Map;
      final monday = (day('2026-10-19')['events'] as List).cast<Map>();
      expect(monday.map((e) => e['kind']), ['plan']);
      expect(monday.single['source_id'], weekly['id']);
      expect(monday.single['occurrence_date'], '2026-10-19');
      expect(monday.single['starts_at'], '2026-10-19T14:00:00.000Z');
      final tuesday = (day('2026-10-20')['events'] as List).cast<Map>();
      expect(tuesday.map((e) => e['kind']), ['note_session', 'calendar']);
      expect(tuesday.last['calendar_title'], 'Lectures');
      expect(tuesday.last['source_id'], feed['id']);
      expect(tuesday.last['title'], 'Lecture 1');
      final wednesday = (day('2026-10-21')['events'] as List).cast<Map>();
      expect(wednesday.map((e) => e['title']), ['Exam']);
      // Deadlines: open by urgency (the series' next occurrence is 2 h away,
      // weight 2: 1.0; the exam 48 h, weight 3: 0.0625), completed last.
      final deadlines = (week['deadlines'] as List).cast<Map>();
      expect(deadlines.map((d) => d['title']), ['Lab', 'Exam', 'Old essay']);
      expect(deadlines.first['occurrence_date'], '2026-10-19');
      expect(deadlines.first['urgency_score'], 1.0);
      expect(deadlines[1]['urgency_score'], 0.0625);
      expect(deadlines.last['id'], done['id']);

      final three = mapOf(await callApi(c, 'GET', '/activity/week/?start_date=bad&days=3'));
      expect(three['start_date'], '2026-10-19');
      expect(three['days'] as List, hasLength(3));
      final fallback = mapOf(await callApi(c, 'GET', '/activity/week/?days=5'));
      expect(fallback['days'] as List, hasLength(7));
    });

    test('heatmap future cells sum the weights in events.json', () async {
      final (c, _) = await folderApp(now: () => _noon);
      for (final w in [2, 3]) {
        await callApi(c, 'POST', '/planner-events/',
            json: {'title': 'e$w', 'event_date': '2026-10-25', 'difficulty_weight': w});
      }
      final h = mapOf(await callApi(c, 'GET', '/heatmap/'));
      final cell = (h['cells'] as List).firstWhere((x) => (x as Map)['date'] == '2026-10-25') as Map;
      expect(cell['future_value'], 5);
      expect(cell['intensity'], 4);
      final page = mapOf(await callApi(c, 'GET', '/front-page/'));
      final upcoming = (page['upcoming_events'] as List).cast<Map>();
      expect(upcoming.map((e) => e['title']), ['e2', 'e3']);
      expect(upcoming.first.keys.toSet(), _eventKeys);
    });
  });

  test('the handshake reports the planner and feeds capabilities', () async {
    final (c, _) = await folderApp();
    final caps = mapOf(await callApi(c, 'GET', '/handshake/'))['capabilities'] as Map;
    expect(caps['planner'], 1);
    expect(caps['calendar_feeds'], 1);
  });
}

const String _ics = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:Lectures\r\n'
    'BEGIN:VEVENT\r\nUID:l1\r\nSUMMARY:Lecture 1\r\nDTSTART:20261020T130000Z\r\n'
    'DTEND:20261020T140000Z\r\nEND:VEVENT\r\n'
    'BEGIN:VEVENT\r\nUID:l2\r\nSUMMARY:Lecture 2\r\nDTSTART:20261110T130000Z\r\n'
    'END:VEVENT\r\nEND:VCALENDAR\r\n';
