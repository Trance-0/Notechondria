// History, snapshots, version restore (F23, 3.8), study sessions (F24),
// the front page and the heatmap (F38, F44).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/folder_snapshots.dart';

import 'backend_harness.dart';

final DateTime _noon = DateTime.utc(2026, 10, 19, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('history', () {
    test('snapshot, history, and restore with a before_restore snapshot',
        () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c,
          title: 'Draft', content: 'First body', extra: {'description': 'v1'});
      final id = note['id'];
      final snap = await callApi(c, 'POST', '/notes/$id/snapshot/',
          json: {'reason': 'manual'});
      expect(snap.statusCode, 201, reason: snap.body);
      final v = mapOf(snap);
      expect(v['reason'], 'manual');
      expect(v['title'], 'Draft');
      expect(v['content'], 'First body');
      expect(v['description'], 'v1');
      expect(v['editor_mode'], 'P');
      expect(v['label'], isNotEmpty);
      expect(v.keys.toSet(), {
        'id', 'title', 'description', 'content', 'metadata_json',
        'editor_mode', 'reason', 'label', 'date_created',
      });
      final hex = uuidHex('${note['uuid']}');
      expect(fs.paths, contains(historyBodyPath(hex, v['id'] as int)));

      await callApi(c, 'PATCH', '/notes/$id/',
          json: {'title': 'Edited', 'content': 'Second body', 'description': 'v2'});
      final restored = await callApi(c, 'POST', '/notes/$id/restore/${v['id']}/');
      expect(restored.statusCode, 200, reason: restored.body);
      expect(mapOf(restored)['title'], 'Draft');
      expect(mapOf(restored)['content'], 'First body');
      expect(mapOf(restored)['description'], 'v1');
      final detail = mapOf(await callApi(c, 'GET', '/notes/$id/'));
      expect(detail['content'], 'First body');

      final history = listOf(await callApi(c, 'GET', '/notes/$id/history/'));
      expect([for (final h in history) h['reason']], ['before_restore', 'manual']);
      expect(history.first['content'], 'Second body');
      expect(history.first['title'], 'Edited');
    });

    test('a snapshot without a body defaults to manual; unknown ids 404',
        () async {
      final (c, _) = await folderApp();
      final note = await createNote(c);
      final snap = await callApi(c, 'POST', '/notes/${note['id']}/snapshot/');
      expect(mapOf(snap)['reason'], 'manual');
      final bad = await callApi(c, 'POST', '/notes/${note['id']}/restore/77/');
      expect(bad.statusCode, 404);
      expect(detailOf(bad),
          LocalFolderMessages.versionNotFound(note['id'] as int, 77));
      expect((await callApi(c, 'GET', '/notes/9/history/')).statusCode, 404);
    });

    test('pruning keeps 12 per pool and never removes the other pool',
        () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c, content: 'Body');
      final hex = uuidHex('${note['uuid']}');
      final writer = FolderSnapshotWriter(fs, now: () => DateTime.utc(2026, 1, 1));
      final path = noteBodyPath(hex);
      for (var i = 0; i < 3; i++) {
        await writer.write(
            noteUuid: '${note['uuid']}',
            reason: 'external_edit',
            text: fs.textOf(path)!,
            notePath: path);
      }
      for (var i = 0; i < 14; i++) {
        final r = await callApi(c, 'POST', '/notes/${note['id']}/snapshot/',
            json: {'reason': i.isEven ? 'manual' : 'autosave_1m'});
        expect(r.statusCode, 201);
      }
      final history = listOf(await callApi(c, 'GET', '/notes/${note['id']}/history/'));
      final reasons = [for (final h in history) h['reason']];
      expect(reasons.where((r) => r == 'external_edit').length, 3);
      expect(reasons.length, 15);
      final index = jsonDecode(fs.textOf(historyIndexPath(hex))!) as Map;
      expect((index['versions'] as List).length, 15);
      final bodies = fs.paths.where((p) => p.startsWith('$kHistoryDir/$hex/') &&
          !p.endsWith('index.json'));
      expect(bodies.length, 15, reason: 'pruned bodies are removed');
      expect(history.first['label'], 'AutoSave-1m');
    });
  });

  group('study sessions', () {
    test('start, update, and list; course and end time are derived', () async {
      final (c, fs) = await folderApp(now: () => _noon);
      final course = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'Bio'}));
      final note = await createNote(c,
          title: 'Mitosis', extra: {'course_id': course['id'], 'description': 'Phases'});
      final start = await callApi(c, 'POST', '/note-sessions/',
          json: {'note_id': note['id'], 'started_at': '2026-10-19T10:00:00Z'});
      expect(start.statusCode, 201, reason: start.body);
      final s = mapOf(start);
      expect(s, {
        'id': 1,
        'title': 'Mitosis',
        'kind': 'note_session',
        'note_id': note['id'],
        'course_id': course['id'],
        'summary': 'Phases',
        'starts_at': '2026-10-19T10:00:00.000Z',
        'ends_at': '2026-10-19T10:15:00.000Z',
      });
      final stored = jsonDecode(fs.textOf(kPlannerSessionsPath)!) as Map;
      expect((stored['sessions'] as List).single['note_uuid'], note['uuid']);

      final patch = await callApi(c, 'PATCH', '/note-sessions/1/',
          json: {'summary': 'Done', 'ended_at': '2026-10-19T11:00:00Z'});
      expect(patch.statusCode, 200, reason: patch.body);
      expect(mapOf(patch)['summary'], 'Done');
      expect(mapOf(patch)['ends_at'], '2026-10-19T11:00:00.000Z');

      final other = await createNote(c, title: 'Other');
      await callApi(c, 'POST', '/note-sessions/',
          json: {'note_id': other['id'], 'title': 'Review'});
      final all = listOf(await callApi(c, 'GET', '/note-sessions/'));
      expect([for (final x in all) x['title']], ['Review', 'Mitosis'],
          reason: 'newest started_at first');
      final one = listOf(await callApi(c, 'GET', '/note-sessions/?note_id=${note['id']}'));
      expect([for (final x in one) x['id']], [1]);
    });

    test('a missing note, session, or note_id answers 404 or 400', () async {
      final (c, _) = await folderApp();
      final noNote = await callApi(c, 'POST', '/note-sessions/', json: {'note_id': 5});
      expect(noNote.statusCode, 404);
      final noId = await callApi(c, 'POST', '/note-sessions/', json: {'title': 'x'});
      expect(noId.statusCode, 400);
      expect(detailOf(noId), startsWith(
          'Study session not saved: Shared.LocalFolder.Backend/planner — '));
      final noSession =
          await callApi(c, 'PATCH', '/note-sessions/3/', json: {'title': 'x'});
      expect(noSession.statusCode, 404);
      expect(detailOf(noSession), LocalFolderMessages.sessionNotFound(3));
      final note = await createNote(c);
      final badTime = await callApi(c, 'POST', '/note-sessions/',
          json: {'note_id': note['id'], 'started_at': 'yesterday'});
      expect(badTime.statusCode, 400);
    });

    test('an unparsable sessions.json is never replaced (202-N6)', () async {
      final (c, fs) = await folderApp(now: () => _noon);
      final note = await createNote(c);
      await fs.writeText(kPlannerSessionsPath, '{"sessions": [{"id": 1,');
      final listed = await callApi(c, 'GET', '/note-sessions/');
      expect(listed.statusCode, 200, reason: listed.body);
      expect(listOf(listed), isEmpty);
      for (final (method, path) in [('POST', '/note-sessions/'), ('PATCH', '/note-sessions/1/')]) {
        final r = await callApi(c, method, path, json: {'note_id': note['id'], 'title': 'x'});
        expect(r.statusCode, 503, reason: '$method ${r.body}');
        expect(detailOf(r), LocalFolderMessages.unreadableFolderFile(
            'Study session not saved', 'planner', kPlannerSessionsPath));
      }
      expect(fs.textOf(kPlannerSessionsPath), '{"sessions": [{"id": 1,');
    });
  });

  group('front page and heatmap', () {
    test('built from own data, private notes included (D1)', () async {
      final (c, fs) = await folderApp(now: () => _noon);
      final course = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'Bio'}));
      await callApi(c, 'POST', '/courses/', json: {'title': 'Empty course'});
      await createNote(c,
          title: 'Private note', content: 'one two three', extra: {'course_id': course['id']});
      await createNote(c, title: 'Loose note', content: 'x');
      await fs.writeText(kPlannerEventsPath, jsonEncode({
        'schema_version': 1,
        'events': [
          {'id': 1, 'title': 'Exam', 'event_date': '2026-10-25', 'difficulty_weight': 3,
              'is_completed': false, 'client_local_id': 'loc-1'},
          {'id': 2, 'title': 'Old', 'event_date': '2026-10-01', 'difficulty_weight': 1,
              'is_completed': false},
          {'id': 3, 'title': 'Done', 'event_date': '2026-10-26', 'difficulty_weight': 2,
              'is_completed': true},
        ],
      }));
      final r = await callApi(c, 'GET', '/front-page/');
      expect(r.statusCode, 200, reason: r.body);
      final page = mapOf(r);
      expect(page.keys.toSet(), {
        'default_course', 'carousel_courses', 'recent_notes',
        'recommended_notes', 'collections', 'heatmap', 'upcoming_events',
      });
      final carousel = page['carousel_courses'] as List;
      expect([for (final x in carousel) (x as Map)['title']], ['Bio']);
      expect((page['default_course'] as Map)['id'], course['id']);
      expect(page['collections'], carousel);
      final recommended = page['recommended_notes'] as List;
      expect([for (final n in recommended) (n as Map)['title']],
          containsAll(['Private note', 'Loose note']));
      expect((recommended.first as Map)['is_public'], isFalse);
      final upcoming = page['upcoming_events'] as List;
      expect([for (final e in upcoming) (e as Map)['title']], ['Exam']);
      expect((upcoming.single as Map).containsKey('client_local_id'), isFalse);

      final heatmap = page['heatmap'] as Map;
      expect(heatmap['today'], '2026-10-19');
      expect(heatmap['days_before'], 364);
      expect(heatmap['days_after'], 28);
      expect(heatmap['start_date'], '2025-10-20');
      expect(heatmap['end_date'], '2026-11-16');
      final cells = heatmap['cells'] as List;
      expect(cells.length, 364 + 28 + 1);
      final today = cells.firstWhere((x) => (x as Map)['is_today'] == true) as Map;
      expect(today['kind'], 'today');
      expect(today['past_value'], 2, reason: 'two notes created today');
      final exam = cells.firstWhere((x) => (x as Map)['date'] == '2026-10-25') as Map;
      expect(exam['future_value'], 3);
      expect(exam['intensity'], 3);
      expect(heatmap['max_past_value'], 2);
      expect(heatmap['max_future_value'], 3);
    });

    test('heatmap.json counts created notes per day; GET /heatmap/', () async {
      final (c, fs) = await folderApp(now: () => _noon);
      await createNote(c, title: 'A', content: List.filled(250, 'w').join(' '));
      final saved = jsonDecode(fs.textOf(kPlannerHeatmapPath)!) as Map;
      expect(saved['days'], {
        '2026-10-19': {'created_notes': 1, 'peak_words': 250},
      });
      final note = await createNote(c, title: 'B', extra: {'client_draft_id': 'd1'});
      // An upsert of an existing draft is an edit, which the heatmap ignores.
      await createNote(c, title: 'B2', extra: {'client_draft_id': 'd1'});
      expect(note['title'], 'B');
      final again = jsonDecode(fs.textOf(kPlannerHeatmapPath)!) as Map;
      expect((again['days'] as Map)['2026-10-19'],
          {'created_notes': 2, 'peak_words': 250});
      final r = await callApi(c, 'GET', '/heatmap/');
      expect(r.statusCode, 200);
      final h = mapOf(r);
      expect(h['days_before'], 182);
      expect((h['cells'] as List).length, 365);
      expect(h['max_past_value'], 2, reason: 'peak 250 words grades 2');
    });

    test('an unparsable heatmap.json is kept and the note still saves (201-N7)', () async {
      final logs = <String>[];
      final (c, fs) = await folderApp(now: () => _noon, logs: logs);
      for (final bad in ['{"days": {"2026-10-18":', '[1, 2]', '{"days": 3}']) {
        await fs.writeText(kPlannerHeatmapPath, bad);
        final note = await createNote(c, title: 'A $bad', content: 'one two');
        expect(note['title'], 'A $bad');
        expect(fs.textOf(kPlannerHeatmapPath), bad);
      }
      expect(logs.where((l) => l == LocalFolderMessages.heatmapNotUpdated(kPlannerHeatmapPath)),
          hasLength(3));
    });

    test('an empty folder answers an empty front page', () async {
      final (c, _) = await folderApp(now: () => _noon);
      final page = mapOf(await callApi(c, 'GET', '/front-page/'));
      expect(page['default_course'], isNull);
      expect(page['carousel_courses'], isEmpty);
      expect(page['recommended_notes'], isEmpty);
      expect(page['upcoming_events'], isEmpty);
      expect((page['heatmap'] as Map)['max_past_value'], 0);
    });
  });
}
