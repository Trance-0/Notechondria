import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_index.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_harness.dart';
import 'folder_fixtures.dart';

// The stored index and the cascades that select through the index (loop 2a
// review L2A-1 to L2A-5): `index.json` follows this tab's writes, entries
// loaded from it are compared with the disk before a list answers from
// them, a rescan keeps the saves made while it ran, a sidecar edited
// elsewhere is repaired, and note and course delete find their targets by
// what is on disk.

String _md(Map<String, Object?> note) => noteBodyPath(uuidHex('${note['uuid']}'));

/// Memory locks whose next shared request waits for [gate], so a test can
/// run a write between two scan pages.
class _GatedLocks extends MemoryFolderLocks {
  Completer<void>? gate;

  @override
  Future<T> run<T>(String name, FolderLockMode mode, Future<T> Function() operation,
      {Duration? timeLeft}) async {
    final waitFor = gate;
    if (waitFor != null && mode == FolderLockMode.shared) {
      gate = null;
      await waitFor.future;
    }
    return super.run(name, mode, operation, timeLeft: timeLeft);
  }
}

/// A tab over [folder] opened from the stored `index.json`, without a
/// rescan.
Future<LocalFolderController> _reopen(MemoryFolderPlatform tab, FolderFs folder) async {
  tab.handleStore.records[kTestFolderId] = folder;
  final c = LocalFolderController.forTest(
      app: 'editor', platform: tab, boot: LocalFolderBoot.snapshot);
  addTearDown(c.dispose);
  await c.open();
  expect(c.state, LocalFolderState.active);
  return c;
}

Map<String, Object?> _row(http.Response r, Object? id) =>
    listOf(r).firstWhere((row) => row['id'] == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a tab opened from index.json lists the edits made since the last scan',
      () async {
    for (final flushed in [false, true]) {
      final p = MemoryFolderPlatform();
      final (a, fs) = await folderApp(platform: p);
      final course = mapOf(await callApi(a, 'POST', '/courses/', json: {'title': 'Bio'}));
      final note = await createNote(a,
          title: 'Old title', content: 'old body', extra: {'description': 'old'});
      for (var i = 0; i < 5; i++) {
        await createNote(a, title: 'other $i', content: 'x');
      }
      await a.rescan();
      final patch = await callApi(a, 'PATCH', '/notes/${note['id']}/', json: {
        'title': 'Fresh title',
        'content': 'new body',
        'course_id': course['id'],
        'description': 'new',
      });
      expect(patch.statusCode, 200, reason: patch.body);
      if (flushed) await a.flushIndex();
      final stored = (await readFolderIndex(fs, folderId: kTestFolderId))!;
      expect(stored.files[_md(note)]!.title, flushed ? 'Fresh title' : 'Old title');

      final counting = CountingFolderFs(fs);
      final b = await _reopen(p.anotherTab(), counting);
      counting.reads.clear();
      final row = _row(await callApi(b, 'GET', '/notes/'), note['id']);
      expect(row['title'], 'Fresh title', reason: 'flushed: $flushed');
      expect(row['description'], 'new');
      expect(row['course_id'], course['id']);
      // Every stored entry was compared by stat; only the edited note's
      // files were read again.
      expect(counting.bodyReads, flushed ? isEmpty : {_md(note)});
      expect(listOf(await callApi(b, 'GET', '/notes/?q=fresh')).map((r) => r['id']),
          [note['id']]);
      expect(listOf(await callApi(b, 'GET', '/notes/?q=old title')), isEmpty);
      expect(
          listOf(await callApi(b, 'GET', '/courses/${course['id']}/notes/'))
              .map((r) => r['id']),
          [note['id']]);
      final recent = listOf(await callApi(b, 'GET', '/courses/')).single['recent_notes'] as List;
      expect((recent.single as Map)['title'], 'Fresh title');
    }
  });

  test("this tab's writes reach index.json once the flush delay passes",
      () async {
    final (a, fs) = await folderApp();
    await createNote(a, title: 'Timed note');
    expect(fs.textOf(kIndexPath), isNot(contains('Timed note')));
    await Future<void>.delayed(kIndexFlushDelay + const Duration(milliseconds: 300));
    expect(fs.textOf(kIndexPath), contains('Timed note'));
  });

  test('a failed index write is logged and tried again after the next write',
      () async {
    final logs = <String>[];
    final fs = await newNotechondriaFolder();
    SharedPreferences.setMockInitialValues(
        {kSharedStorageModeKey: folderRecord().encode()});
    await LocalFolderBoot.preload();
    final p = MemoryFolderPlatform()..handleStore.records[kTestFolderId] = fs;
    final c = LocalFolderController.forTest(
        app: 'editor',
        platform: p,
        boot: LocalFolderBoot.snapshot,
        log: (_, message) => logs.add(message));
    addTearDown(c.dispose);
    await c.open();
    await createNote(c, title: 'First');
    fs.failNext(FolderErrorKind.noModificationAllowed,
        operation: 'write', pathPrefix: kIndexPath);
    await c.flushIndex();
    expect(logs.where((m) => m.startsWith('Folder index not saved: Shared.LocalFolder/write — ')),
        hasLength(1));
    expect(fs.textOf(kIndexPath), isNot(contains('First')));
    await createNote(c, title: 'Second');
    await c.flushIndex();
    expect(fs.textOf(kIndexPath), allOf(contains('First'), contains('Second')));
    expect(c.state, LocalFolderState.active);
  });

  test('emptying the trash removes the notes from index.json', () async {
    final (a, fs) = await folderApp();
    final note = await createNote(a, title: 'Secret plan', content: 'the hidden excerpt');
    await a.rescan();
    expect(fs.textOf(kIndexPath), contains('the hidden excerpt'));
    expect((await callApi(a, 'DELETE', '/notes/${note['id']}/')).statusCode, 204);
    expect((await callApi(a, 'DELETE', '/notes/deleted/empty/')).statusCode, 200);
    await a.flushIndex();
    expect(fs.textOf(kIndexPath), isNot(contains('the hidden excerpt')));
    expect(fs.textOf(kIndexPath), isNot(contains('Secret plan')));
  });

  test('a note saved between scan pages keeps its new entry (L2A-2)', () async {
    final locks = _GatedLocks();
    final p = MemoryFolderPlatform(locks: locks);
    final fs = await newNotechondriaFolder();
    // 300 notes (600 files): the scan reads more than one 500-entry page.
    for (var i = 1; i <= 300; i++) {
      final uuid = newUuidV4();
      final path = noteBodyPath(uuidHex(uuid));
      fs.externalEdit(path, noteText(uuid, 'seed $i', 'body $i'));
      fs.externalEdit(sidecarPathForBody(path), NoteSidecar(id: i, uuid: uuid).encode());
    }
    final (c, _) = await folderApp(fs: fs, platform: p);
    // The first note by path is read in the first page.
    final path = (fs.paths.where(isNoteBodyPath).toList()..sort()).first;
    final id = c.index!.files[sidecarPathForBody(path)]!.id;
    Future<http.Response>? patch;
    void onPage() {
      if (patch != null) return;
      final gate = locks.gate = Completer<void>();
      patch = callApi(c, 'PATCH', '/notes/$id/', json: {'title': 'Saved mid-scan'})
        ..whenComplete(gate.complete);
    }

    c.addListener(onPage);
    final result = await c.rescan();
    c.removeListener(onPage);
    expect(result, isNotNull);
    expect(patch, isNotNull);
    expect((await patch!).statusCode, 200);
    expect(c.index!.files[path]!.title, 'Saved mid-scan');
    expect((await readFolderIndex(fs, folderId: kTestFolderId))!.files[path]!.title,
        'Saved mid-scan');
    expect(_row(await callApi(c, 'GET', '/notes/'), id)['title'], 'Saved mid-scan');
  });

  test('a sidecar edited elsewhere is repaired when its note is read (L2A-3)',
      () async {
    final (a, fs) = await folderApp();
    final note = await createNote(a, title: 'n', extra: {'description': 'before'});
    final side = sidecarPathForBody(_md(note));
    final json = Map<String, Object?>.from(jsonDecode(fs.textOf(side)!) as Map);
    fs.externalEdit(side, jsonEncode({...json, 'description': 'after'}));
    expect(mapOf(await callApi(a, 'GET', '/notes/${note['id']}/'))['description'], 'after');
    expect(_row(await callApi(a, 'GET', '/notes/'), note['id'])['description'], 'after');
    // Another tab's identity fix gave the note a new id (3.7): the old id
    // answers 404, and the new one is found.
    fs.externalEdit(side, jsonEncode({...json, 'id': 77}));
    expect((await callApi(a, 'GET', '/notes/${note['id']}/')).statusCode, 404);
    final renumbered = await callApi(a, 'GET', '/notes/77/');
    expect(renumbered.statusCode, 200, reason: renumbered.body);
    expect(mapOf(renumbered)['uuid'], note['uuid']);
  });

  test('deleting a note privatizes a comment made public in another tab (L2A-4)',
      () async {
    final p = MemoryFolderPlatform();
    final (a, fs) = await folderApp(platform: p);
    final source = await createNote(a, title: 'source');
    final comment = await createNote(a,
        title: 'comment', extra: {'note_type': 'C', 'source_note_uuid': source['uuid']});
    final (b, _) = await folderApp(fs: fs, platform: p.anotherTab());
    final made = await callApi(b, 'PATCH', '/notes/${comment['id']}/', json: {'is_public': true});
    expect(mapOf(made)['is_public'], isTrue);
    expect((await callApi(a, 'DELETE', '/notes/${source['id']}/')).statusCode, 204);
    expect(mapOf(await callApi(b, 'GET', '/notes/${comment['id']}/'))['is_public'], isFalse);
  });

  test('deleting a course detaches a note another tab moved into it (L2A-5)',
      () async {
    final p = MemoryFolderPlatform();
    final (a, fs) = await folderApp(platform: p);
    final course = mapOf(await callApi(a, 'POST', '/courses/', json: {'title': 'Bio'}));
    final note = await createNote(a, title: 'loose');
    final (b, _) = await folderApp(fs: fs, platform: p.anotherTab());
    final moved = await callApi(b, 'PATCH', '/notes/${note['id']}/',
        json: {'course_id': course['id']});
    expect(mapOf(moved)['course_id'], course['id']);
    expect((await callApi(a, 'DELETE', '/courses/${course['id']}/')).statusCode, 204);
    expect(decodeNoteFile(fs.textOf(_md(note))!, path: _md(note)).frontmatter.courseSlug,
        isNull);
    // A later course with the same title and slug does not adopt the note.
    final again = mapOf(await callApi(a, 'POST', '/courses/', json: {'title': 'Bio'}));
    expect(again['slug'], course['slug']);
    expect(listOf(await callApi(a, 'GET', '/courses/${again['id']}/notes/')), isEmpty);
  });
}
