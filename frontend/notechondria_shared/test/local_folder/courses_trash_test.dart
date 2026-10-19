import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/handlers/courses.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

import 'backend_harness.dart';

String _md(Map<String, Object?> note, {bool trashed = false}) =>
    noteBodyPath(uuidHex('${note['uuid']}'), trashed: trashed);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('courses (F12 to F15)', () {
    test('create, the title rule, the client_course_id upsert, and rename',
        () async {
      final (c, fs) = await folderApp();
      final r = await callApi(c, 'POST', '/courses/',
          json: {'title': 'Organic Chemistry', 'client_course_id': 'local-1', 'icon': 3});
      expect(r.statusCode, 201, reason: r.body);
      final course = mapOf(r);
      expect(course['slug'], 'organic-chemistry');
      expect(course['owner'], isA<Map>());
      expect(fs.exists('courses/organic-chemistry.json'), isTrue);
      final dup = await callApi(c, 'POST', '/courses/', json: {'title': 'organic chemistry'});
      expect(dup.statusCode, 400);
      expect(detailOf(dup), LocalFolderMessages.courseTitleTaken('organic chemistry'));
      final upsert = await callApi(c, 'POST', '/courses/',
          json: {'title': 'Organic Chemistry II', 'client_course_id': 'local-1'});
      expect(upsert.statusCode, 200);
      expect(mapOf(upsert)['id'], course['id']);
      final renamed = await callApi(c, 'PATCH', '/courses/${course['id']}/',
          json: {'title': 'Chem', 'color_hue': 120});
      expect(mapOf(renamed)['slug'], 'organic-chemistry');
      expect(mapOf(renamed)['color_hue'], 120);
      expect((await callApi(c, 'PATCH', '/courses/${course['id']}/', json: {'color_hue': 400}))
          .statusCode, 400);
      expect((await callApi(c, 'GET', '/courses/99/')).statusCode, 404);
      expect(slugifyTitle('Ünïcode  Ü -- x'), 'ncode-x');
      expect(await uniqueCourseSlug(fs, 'Organic Chemistry'), 'organic-chemistry-2');
    });

    test('reorder, course notes with paging, and the opened marker', () async {
      final (c, _) = await folderApp();
      final a = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'A'}));
      final b = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'B'}));
      final list = listOf(await callApi(c, 'POST', '/courses/reorder/',
          json: {'course_ids': [b['id'], 'junk', a['id'], b['id']]}));
      expect(list.map((x) => x['title']), ['B', 'A']);
      expect(list.map((x) => x['sort_order']), [1, 2]);
      expect((await callApi(c, 'POST', '/courses/reorder/', json: {'course_ids': 1})).statusCode,
          400);
      for (var i = 0; i < 3; i++) {
        await createNote(c, title: 'n$i', extra: {'course_id': a['id']});
      }
      final page = mapOf(await callApi(c, 'GET', '/courses/${a['id']}/notes/?limit=2'));
      expect(page['total'], 3);
      expect((page['results'] as List), hasLength(2));
      expect(listOf(await callApi(c, 'GET', '/courses/${a['id']}/notes/')), hasLength(3));
      final listed = listOf(await callApi(c, 'GET', '/courses/'));
      expect((listed.last['recent_notes'] as List), hasLength(3));
      final opened = mapOf(await callApi(c, 'POST', '/courses/${a['id']}/open/'));
      expect(opened['last_opened_at'], isA<String>());
    });

    test('delete nulls notes, trashed notes, events, and feeds (3.5)', () async {
      final (c, fs) = await folderApp();
      final course = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'Bio'}));
      final id = course['id'];
      final live = await createNote(c, title: 'live', extra: {'course_id': id});
      final gone = await createNote(c, title: 'gone', extra: {'course_id': id});
      await callApi(c, 'DELETE', '/notes/${gone['id']}/');
      await fs.writeText(kPlannerEventsPath,
          encodeFolderJson({'events': [{'id': 1, 'course_id': id}, {'id': 2, 'course_id': 7}]}));
      await fs.writeText(kPlannerFeedsPath, encodeFolderJson([{'id': 1, 'course_id': id}]));
      final r = await callApi(c, 'DELETE', '/courses/$id/');
      expect(r.statusCode, 204, reason: r.body);
      expect(fs.exists('courses/bio.json'), isFalse);
      for (final path in [_md(live), _md(gone, trashed: true)]) {
        expect(decodeNoteFile(fs.textOf(path)!, path: path).frontmatter.courseSlug, isNull);
      }
      expect(fs.textOf(kPlannerEventsPath), contains('"course_id": 7'));
      expect(decodeJsonValue(fs.textOf(kPlannerEventsPath)!),
          {'events': [{'id': 1, 'course_id': null}, {'id': 2, 'course_id': 7}]});
      expect(decodeJsonValue(fs.textOf(kPlannerFeedsPath)!), [{'id': 1, 'course_id': null}]);
      expect(c.busyLine, isNull);
    });

    test('a long course delete lets the other tab save between chunks (6.2)',
        () async {
      final p = MemoryFolderPlatform();
      final (a, fs) = await folderApp(platform: p);
      final course = mapOf(await callApi(a, 'POST', '/courses/', json: {'title': 'Big'}));
      for (var i = 0; i < 120; i++) {
        await createNote(a, title: 'n$i', extra: {'course_id': course['id']});
      }
      final other = await createNote(a, title: 'other');
      final (b, _) = await folderApp(fs: fs, platform: p.anotherTab());
      final busy = <String>[];
      a.addListener(() {
        if (a.busyLine != null) busy.add(a.busyLine!);
      });
      final deleting = callApi(a, 'DELETE', '/courses/${course['id']}/');
      final watch = Stopwatch()..start();
      final save = await callApi(b, 'PATCH', '/notes/${other['id']}/', json: {'content': 'saved'});
      expect(save.statusCode, 200, reason: save.body);
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect((await deleting).statusCode, 204);
      expect(busy.first, startsWith('Folder busy: Shared.LocalFolder/write — '));
      expect(busy, contains(contains('(120 of 120)')));
    });
  });

  group('trash (F22, 3.5)', () {
    test('list and restore keep is_public false and drop the pointer', () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c, extra: {'is_public': true});
      await callApi(c, 'DELETE', '/notes/${note['id']}/');
      final trash = listOf(await callApi(c, 'GET', '/notes/deleted/'));
      expect(trash.single['id'], note['id']);
      expect(trash.single['deleted_at'], isA<String>());
      expect(trash.single['recycle_bin_entry_id'], note['id']);
      final restored = await callApi(c, 'POST', '/notes/${note['id']}/restore/');
      expect(restored.statusCode, 200, reason: restored.body);
      expect(mapOf(restored)['is_public'], isFalse);
      expect(fs.exists(_md(note)), isTrue);
      expect(fs.exists(_md(note, trashed: true)), isFalse);
      expect(fs.textOf(kRecycleBinPath), isNot(contains('${note['uuid']}')));
      expect((await callApi(c, 'POST', '/notes/${note['id']}/restore/')).statusCode, 404);
    });

    test('empty trash removes history, assets, sessions, and comment links',
        () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c);
      final comment = await createNote(c, title: 'Comment',
          extra: {'note_type': 'C', 'source_note_uuid': note['uuid']});
      final hex = uuidHex('${note['uuid']}');
      await fs.writeText(historyIndexPath(hex), '{"versions": []}');
      await fs.writeText('$kAssetsDir/notes/$hex/attachments.json', '[]');
      await fs.writeText(kPlannerSessionsPath, encodeFolderJson({
        'sessions': [{'id': 1, 'note_uuid': note['uuid']}, {'id': 2, 'note_uuid': 'x'}],
      }));
      await callApi(c, 'DELETE', '/notes/${note['id']}/');
      final r = await callApi(c, 'DELETE', '/notes/deleted/empty/');
      expect(mapOf(r), {'count': 1, 'deleted_count': 1});
      expect(fs.paths.where((p) => p.contains(hex)), isEmpty);
      expect(decodeJsonValue(fs.textOf(kPlannerSessionsPath)!),
          {'sessions': [{'id': 2, 'note_uuid': 'x'}]});
      final sidecar = decodeSidecar(fs.textOf(sidecarPathForBody(_md(comment)))!)!;
      expect(sidecar.sourceNoteUuid, isNull);
      expect(listOf(await callApi(c, 'GET', '/notes/deleted/')), isEmpty);
    });
  });
}
