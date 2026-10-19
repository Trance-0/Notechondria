import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/handlers/records.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';

import 'backend_harness.dart';
import 'folder_fixtures.dart';

// Index-backed lookups (phase 1b review P1B-1, 6.2 R2): a single-note
// request re-reads only the note it serves or rewrites, the list routes
// answer from the index, and notes another tab added or removed are still
// found or dropped.

/// Records which files are read, over a [MemoryFolderFs].
class _CountingFs implements FolderFs {
  _CountingFs(this.inner);
  final MemoryFolderFs inner;
  final List<String> reads = [];

  /// Note bodies read since the last [reads] clear.
  Set<String> get bodyReads => {...reads.where(isNoteBodyPath)};

  @override
  String get name => inner.name;
  @override
  Future<String> readText(String path) {
    reads.add(path);
    return inner.readText(path);
  }

  @override
  Future<Uint8List> readBytes(String path) {
    reads.add(path);
    return inner.readBytes(path);
  }

  @override
  Future<void> writeText(String path, String text) => inner.writeText(path, text);
  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      inner.writeBytes(path, bytes);
  @override
  Future<List<FolderEntry>> list(String directory) => inner.list(directory);
  @override
  Future<FolderStat?> stat(String path) => inner.stat(path);
  @override
  Future<void> remove(String path, {bool recursive = false}) =>
      inner.remove(path, recursive: recursive);
  @override
  Future<FolderPermission> queryPermission({bool write = true}) =>
      inner.queryPermission(write: write);
  @override
  Future<FolderPermission> requestPermission({bool write = true}) =>
      inner.requestPermission(write: write);
  @override
  Future<bool> isSameEntry(FolderFs other) =>
      inner.isSameEntry(other is _CountingFs ? other.inner : other);
}

String _md(Map<String, Object?> note, {bool trashed = false}) =>
    noteBodyPath(uuidHex('${note['uuid']}'), trashed: trashed);

/// A second tab over [folder] (shared locks and handle store), opened and
/// rescanned, so its index holds every note on disk.
Future<LocalFolderController> _openTab(MemoryFolderPlatform tab, FolderFs folder) async {
  tab.handleStore.records[kTestFolderId] = folder;
  final c = LocalFolderController.forTest(
      app: 'editor', platform: tab, boot: LocalFolderBoot.snapshot);
  addTearDown(c.dispose);
  await c.open();
  await c.rescan();
  return c;
}

/// Summaries of every live note as a full read of the folder builds them.
Future<Map<Object?, Map<String, Object?>>> _diskSummaries(MemoryFolderFs fs) async {
  final courses = CourseLookup(await readCourses(fs));
  final author = (await FolderProfile.read(fs, folderName: 'Notes')).author;
  final out = <Object?, Map<String, Object?>>{};
  for (final e in await fs.list(kNotesDir)) {
    if (!e.name.endsWith('.md')) continue;
    final n = await readNoteAt(fs, '$kNotesDir/${e.name}');
    if (n != null) out[n.id] = noteSummary(n, courses, author);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a single-note GET or PATCH reads only that note; lists read none',
      () async {
    final p = MemoryFolderPlatform();
    final (a, fs) = await folderApp(platform: p);
    final notes = [for (var i = 0; i < 30; i++) await createNote(a, title: 'n$i')];
    final counting = _CountingFs(fs);
    final b = await _openTab(p.anotherTab(), counting);
    final target = notes[17];
    counting.reads.clear();
    expect((await callApi(b, 'GET', '/notes/${target['id']}/')).statusCode, 200);
    expect(counting.bodyReads, {_md(target)});
    counting.reads.clear();
    expect((await callApi(b, 'GET', '/notes/uuid/${target['uuid']}/')).statusCode, 200);
    expect(counting.bodyReads, {_md(target)});
    counting.reads.clear();
    final patch = await callApi(b, 'PATCH', '/notes/${target['id']}/',
        json: {'content': 'edited'});
    expect(patch.statusCode, 200, reason: patch.body);
    expect(counting.bodyReads, {_md(target)});
    counting.reads.clear();
    expect(listOf(await callApi(b, 'GET', '/notes/')), hasLength(30));
    expect(listOf(await callApi(b, 'GET', '/courses/')), isEmpty);
    expect(counting.bodyReads, isEmpty);
    counting.reads.clear();
    // A search reads a body only where the title and description miss.
    expect(listOf(await callApi(b, 'GET', '/notes/?q=n17')).single['id'], target['id']);
    expect(counting.bodyReads, hasLength(29));
    expect(counting.bodyReads, isNot(contains(_md(target))));
    expect(listOf(await callApi(b, 'GET', '/notes/?q=edited')).single['id'], target['id']);
  });

  test('notes another tab created or deleted are found and listed', () async {
    final p = MemoryFolderPlatform();
    final (a, fs) = await folderApp(platform: p);
    final kept = await createNote(a, title: 'kept');
    final (b, _) = await folderApp(fs: fs, platform: p.anotherTab());
    // Created in tab b after tab a built its index.
    final late = await createNote(b, title: 'late', content: 'from b');
    final byId = await callApi(a, 'GET', '/notes/${late['id']}/');
    expect(byId.statusCode, 200, reason: byId.body);
    expect(mapOf(byId)['content'], 'from b');
    expect(mapOf(await callApi(a, 'GET', '/notes/uuid/${late['uuid']}/'))['id'], late['id']);
    // Deleted in tab b: tab a answers 404 and lists it in the trash only.
    expect((await callApi(b, 'DELETE', '/notes/${kept['id']}/')).statusCode, 204);
    expect((await callApi(a, 'GET', '/notes/${kept['id']}/')).statusCode, 404);
    expect(listOf(await callApi(a, 'GET', '/notes/')).map((n) => n['id']), [late['id']]);
    expect(listOf(await callApi(a, 'GET', '/notes/deleted/')).single['id'], kept['id']);
    // An outside program's note with a sidecar is listed without a rescan.
    const uuid = '22222222-3333-4444-8555-666666666666';
    final path = noteBodyPath(uuidHex(uuid));
    fs.externalEdit(path, noteText(uuid, 'outside', 'typed in vim'));
    fs.externalEdit(sidecarPathForBody(path), '{"id": 99, "uuid": "$uuid"}\n');
    expect(listOf(await callApi(a, 'GET', '/notes/')).map((n) => n['title']),
        containsAll(['late', 'outside']));
  });

  test('list rows from the index equal summaries from a full read', () async {
    final (c, fs) = await folderApp();
    final course = mapOf(await callApi(c, 'POST', '/courses/', json: {'title': 'Bio'}));
    final source = await createNote(c, title: 'Cells', content: '# Cells\n\nMitochondria\n\nATP', extra: {
      'course_id': course['id'],
      'description': 'about cells',
      'is_public': true,
      'editor_mode': 'G',
    });
    await createNote(c, title: 'Empty', content: '', extra: {'description': 'only a description'});
    await createNote(c, title: 'Comment', content: 'nice', extra: {
      'note_type': 'C',
      'source_note_uuid': source['uuid'],
      'client_draft_id': 'draft-c',
    });
    await callApi(c, 'PATCH', '/notes/${source['id']}/', json: {'title': 'Cells 2', 'content': 'Krebs'});
    final expected = await _diskSummaries(fs);
    expect(expected, hasLength(3));
    // Tab c keeps its index from its own writes; a fresh tab scans the disk.
    final (fresh, _) = await folderApp(fs: fs);
    await fresh.rescan();
    for (final tab in [c, fresh]) {
      final rows = {
        for (final row in listOf(await callApi(tab, 'GET', '/notes/'))) row['id']: row,
      };
      expect(rows, expected);
      final recent = listOf(await callApi(tab, 'GET', '/courses/')).single['recent_notes'] as List;
      expect(recent.single, expected[source['id']]);
    }
  });
}
