import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/folder_snapshots.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

import 'backend_harness.dart';
import 'folder_fixtures.dart';

String _md(Map<String, Object?> note) => noteBodyPath(uuidHex('${note['uuid']}'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('create and read (F20)', () {
    test('POST /notes/ writes the .md, the sidecar, and the counter', () async {
      final (c, fs) = await folderApp();
      final r = await callApi(c, 'POST', '/notes/', json: {
        'title': 'First',
        'content': '# First\n\nHello world',
        'description': 'd',
        'is_public': true,
        'editor_mode': 'G',
        'client_draft_id': 'draft-1',
      });
      expect(r.statusCode, 201, reason: r.body);
      final note = mapOf(r);
      expect(note['id'], 1);
      expect(note['content'], '# First\n\nHello world');
      expect(note['excerpt'], 'Hello world');
      expect(note['preview_lines'], ['Hello world']);
      expect(note.containsKey('can_edit'), isFalse);
      final path = _md(note);
      final decoded = decodeNoteFile(fs.textOf(path)!, path: path);
      expect(decoded.frontmatter.title, 'First');
      expect(decoded.frontmatter.isPublic, isTrue);
      expect(decoded.frontmatter.editorMode, 'G');
      final sidecar = decodeSidecar(fs.textOf(sidecarPathForBody(path))!)!;
      expect(sidecar.id, 1);
      expect(sidecar.clientDraftId, 'draft-1');
      expect(sidecar.mdSize, isNotNull, reason: 'stamped after the write (3.8)');
      expect(decodeFolderManifest(fs.textOf(kManifestPath)!).counter('note'), 1);
      final detail = await callApi(c, 'GET', '/notes/1/');
      expect(mapOf(detail)['can_edit'], isTrue);
      final byUuid = await callApi(c, 'GET', '/notes/uuid/${note['uuid']}/');
      expect(mapOf(byUuid)['id'], 1);
    });

    test('validation and missing records answer 400 and 404', () async {
      final (c, _) = await folderApp();
      final noTitle = await callApi(c, 'POST', '/notes/', json: {'content': 'x'});
      expect(noTitle.statusCode, 400);
      expect(detailOf(noTitle), startsWith('Note not saved: Shared.LocalFolder.Backend/notes — '));
      final badCourse = await callApi(c, 'POST', '/notes/', json: {'title': 't', 'course_id': 9});
      expect(badCourse.statusCode, 404);
      expect(detailOf(badCourse), LocalFolderMessages.courseNotFound(9));
      expect(detailOf(await callApi(c, 'GET', '/notes/7/')), LocalFolderMessages.noteNotFound(7));
      const uuid = '11111111-2222-4333-8444-555555555555';
      final missing = await callApi(c, 'GET', '/notes/uuid/$uuid/');
      expect(missing.statusCode, 404);
      expect(detailOf(missing), LocalFolderMessages.noteUuidNotFound(uuid));
      expect(containsDeepLinkPrivateNoteMarker(detailOf(missing)), isFalse);
    });

    test('client_draft_id upserts, also out of the trash (3.5)', () async {
      final (c, fs) = await folderApp();
      final first = await createNote(c, extra: {'client_draft_id': 'd1'});
      expect((await callApi(c, 'DELETE', '/notes/${first['id']}/')).statusCode, 204);
      final again = await callApi(c, 'POST', '/notes/',
          json: {'title': 'Again', 'content': 'v2', 'client_draft_id': 'd1'});
      expect(again.statusCode, 200);
      expect(mapOf(again)['id'], first['id']);
      expect(fs.exists(_md(first)), isTrue);
      expect(fs.exists(noteBodyPath(uuidHex('${first['uuid']}'), trashed: true)), isFalse);
      expect(fs.textOf(kRecycleBinPath), isNot(contains('${first['uuid']}')));
    });
  });

  group('update (3.8, T7(j))', () {
    test('PATCH rewrites the note and keeps unknown sidecar keys', () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c);
      final r = await callApi(c, 'PATCH', '/notes/${note['id']}/',
          json: {'title': 'Renamed', 'content': 'New body', 'metadata_json': '{"a":1}'});
      expect(r.statusCode, 200, reason: r.body);
      expect(mapOf(r)['title'], 'Renamed');
      expect(mapOf(r)['metadata_json'], '{"a":1}');
      final decoded = decodeNoteFile(fs.textOf(_md(note))!, path: _md(note));
      expect(decoded.body, 'New body');
      expect(fs.exists(historyIndexPath(uuidHex('${note['uuid']}'))), isFalse);
    });

    test('an external edit is kept as one external_edit snapshot', () async {
      final (c, fs) = await folderApp();
      final note = await createNote(c);
      final path = _md(note);
      final external = noteText('${note['uuid']}', 'Note', 'edited in vim');
      fs.externalEdit(path, external);
      await callApi(c, 'PATCH', '/notes/${note['id']}/', json: {'content': 'app text'});
      final index = decodeHistoryIndex(
          fs.textOf(historyIndexPath(uuidHex('${note['uuid']}')))!)!;
      expect(index.versions.map((v) => v.reason), ['external_edit']);
      expect(fs.textOf(historyBodyPath(uuidHex('${note['uuid']}'), index.versions.single.id)),
          external);
    });

    test('a write from another tab is kept as a concurrent_edit snapshot',
        () async {
      final p = MemoryFolderPlatform();
      final (a, fs) = await folderApp(platform: p);
      final note = await createNote(a);
      final (b, _) = await folderApp(fs: fs, platform: p.anotherTab());
      await callApi(b, 'PATCH', '/notes/${note['id']}/', json: {'content': 'from B'});
      await callApi(a, 'PATCH', '/notes/${note['id']}/', json: {'content': 'from A'});
      final hex = uuidHex('${note['uuid']}');
      final index = decodeHistoryIndex(fs.textOf(historyIndexPath(hex))!)!;
      expect(index.versions.single.reason, 'concurrent_edit');
      expect(fs.textOf(historyBodyPath(hex, index.versions.single.id)), contains('from B'));
      expect(decodeNoteFile(fs.textOf(_md(note))!, path: _md(note)).body, 'from A');
    });
  });

  group('delete (3.5)', () {
    test('DELETE moves to trash/notes/, privatizes comments, adds a pointer',
        () async {
      final (c, fs) = await folderApp();
      final source = await createNote(c, title: 'Source', extra: {'is_public': true});
      final comment = await createNote(c, title: 'Comment', extra: {
        'is_public': true,
        'note_type': 'C',
        'source_note_uuid': source['uuid'],
      });
      expect(comment['source_note_uuid'], source['uuid']);
      final r = await callApi(c, 'DELETE', '/notes/uuid/${source['uuid']}/');
      expect(r.statusCode, 204);
      expect(fs.exists(_md(source)), isFalse);
      final trashPath = noteBodyPath(uuidHex('${source['uuid']}'), trashed: true);
      final trashed = decodeNoteFile(fs.textOf(trashPath)!, path: trashPath);
      expect(trashed.frontmatter.isPublic, isFalse);
      expect(decodeSidecar(fs.textOf(sidecarPathForBody(trashPath))!)!.deletedAt, isNotNull);
      expect(decodeNoteFile(fs.textOf(_md(comment))!, path: _md(comment)).frontmatter.isPublic,
          isFalse);
      expect(fs.textOf(kRecycleBinPath), contains('${source['uuid']}'));
      expect((await callApi(c, 'GET', '/notes/${source['id']}/')).statusCode, 404);
    });
  });

  group('list (F14, F25, F26)', () {
    test('scope, course filter, search, and paging', () async {
      final (c, _) = await folderApp();
      final course = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'Bio'}));
      await createNote(c, title: 'Cells', content: 'mitochondria', extra: {'course_id': course['id']});
      await createNote(c, title: 'Loose', content: 'other', extra: {'is_public': true});
      final all = listOf(await callApi(c, 'GET', '/notes/'));
      expect(all.map((n) => n['title']), ['Loose', 'Cells']);
      final page = mapOf(await callApi(c, 'GET', '/notes/?limit=1&offset=0&scope=personal'));
      expect(page['total'], 2);
      expect(page['has_more'], isTrue);
      expect((page['results'] as List).single['title'], 'Loose');
      final inbox = listOf(await callApi(c, 'GET', '/notes/?course_id=none'));
      expect(inbox.map((n) => n['title']), ['Loose']);
      final inCourse = listOf(await callApi(c, 'GET', '/notes/?course_id=${course['id']}'));
      expect(inCourse.single['course'], {'id': course['id'], 'title': 'Bio', 'slug': 'bio'});
      final found = listOf(await callApi(c, 'GET', '/notes/?q=mitochon'));
      expect(found.map((n) => n['title']), ['Cells']);
      final private = listOf(await callApi(c, 'GET', '/notes/?scope=private'));
      expect(private.map((n) => n['title']), ['Cells']);
      expect(listOf(await callApi(c, 'GET', '/notes/?scope=all')), hasLength(2));
      final bad = await callApi(c, 'GET', '/notes/?limit=x');
      expect(bad.statusCode, 400);
    });

    test('concurrent creates from two tabs get distinct ids (6.2)', () async {
      final p = MemoryFolderPlatform();
      final (a, fs) = await folderApp(platform: p);
      final (b, _) = await folderApp(fs: fs, platform: p.anotherTab());
      final results = await Future.wait([
        for (var i = 0; i < 6; i++) createNote(i.isEven ? a : b, title: 'n$i'),
      ]);
      expect(results.map((n) => n['id']).toSet(), hasLength(6));
      expect(decodeFolderManifest(fs.textOf(kManifestPath)!).counter('note'), 6);
      expect(a.state, LocalFolderState.active);
    });
  });
}
