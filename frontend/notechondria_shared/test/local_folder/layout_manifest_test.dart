import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';

void main() {
  group('manifest (3.2)', () {
    test('a new manifest has every counter at 0 and round-trips', () {
      final m = FolderManifest.create(
          folderId: 'abc', appVersion: '0.1.200', now: DateTime.utc(2026, 1, 2));
      final json = jsonDecode(m.encode()) as Map<String, Object?>;
      expect(json['format'], 'notechondria-folder');
      expect(json['layout_version'], 1);
      expect(json['github_sync_schema_version'], 1);
      expect(json['created_by_app_version'], '0.1.200');
      expect(json['id_counters'], {
        'attachment': 0,
        'course': 0,
        'event': 0,
        'feed': 0,
        'note': 0,
        'session': 0,
        'version': 0,
      });
      final back = decodeFolderManifest(m.encode());
      expect(back.encode(), m.encode());
    });

    test('allocate issues last+1 and never changes the original', () {
      final m = FolderManifest.create(
          folderId: 'abc', appVersion: 't', now: DateTime.utc(2026));
      final (m1, id1) = m.allocate('note');
      final (m2, id2) = m1.allocate('note');
      expect([id1, id2], [1, 2]);
      expect(m.counter('note'), 0);
      expect(m2.counter('note'), 2);
      expect(m2.counter('course'), 0);
    });

    test('raisedTo only raises, and answers null when nothing is lower', () {
      final m = FolderManifest.create(
              folderId: 'abc', appVersion: 't', now: DateTime.utc(2026))
          .allocate('note')
          .$1;
      expect(m.raisedTo({'note': 1}), isNull);
      expect(m.raisedTo({'note': 0}), isNull);
      final raised = m.raisedTo({'note': 7, 'event': 3})!;
      expect(raised.counter('note'), 7);
      expect(raised.counter('event'), 3);
      expect(raised.folderId, 'abc');
    });

    test('a newer layout_version is refused with the 3.2 message', () {
      final json = {
        'format': 'notechondria-folder',
        'layout_version': 2,
        'folder_id': 'abc',
      };
      expect(
          () => FolderManifest.fromJson(json),
          throwsA(isA<FolderLayoutException>()
              .having((e) => e.newerLayout, 'newerLayout', 2)
              .having(
                  (e) => e.message,
                  'message',
                  'Folder not opened: Shared.LocalFolder/scan — manifest.json '
                      'layout_version 2 is newer than this build supports (1). '
                      'Update the app.')));
    });

    test('a foreign or broken manifest is refused', () {
      expect(() => decodeFolderManifest('not json'),
          throwsA(isA<FolderLayoutException>()));
      expect(
          () => FolderManifest.fromJson(
              {'format': 'other', 'layout_version': 1, 'folder_id': 'x'}),
          throwsA(isA<FolderLayoutException>()));
      expect(
          () => FolderManifest.fromJson(
              {'format': 'notechondria-folder', 'layout_version': 1}),
          throwsA(isA<FolderLayoutException>()));
    });

    test('unknown keys and restored_from_folder_id survive a rewrite', () {
      final m = FolderManifest.fromJson({
        'format': 'notechondria-folder',
        'layout_version': 1,
        'folder_id': 'new',
        'restored_from_folder_id': 'old',
        'future_key': {'a': 1},
        'id_counters': {'note': 4},
      });
      final json = jsonDecode(m.allocate('note').$1.encode()) as Map;
      expect(json['future_key'], {'a': 1});
      expect(json['restored_from_folder_id'], 'old');
      expect((json['id_counters'] as Map)['note'], 5);
    });

    test('withFolderId keeps counters and records the source', () {
      final m = FolderManifest.create(
              folderId: 'a', appVersion: 't', now: DateTime.utc(2026))
          .allocate('course')
          .$1;
      final copy = m.withFolderId('b', restoredFrom: 'a');
      expect(copy.folderId, 'b');
      expect(copy.restoredFromFolderId, 'a');
      expect(copy.counter('course'), 1);
    });
  });

  group('initial folder', () {
    test('README.md first, manifest.json last (6.2 R4)', () async {
      final files = initialFolderFiles(
          folderId: 'abc', appVersion: 't', now: DateTime.utc(2026));
      expect(files.map((f) => f.path), [kReadmePath, kManifestPath]);
      final fs = MemoryFolderFs();
      for (final f in files) {
        await fs.writeText(f.path, f.text);
      }
      expect((await readFolderManifest(fs))!.folderId, 'abc');
    });

    test('a folder without manifest.json reads as null', () async {
      expect(await readFolderManifest(MemoryFolderFs()), isNull);
    });
  });

  group('paths and ids', () {
    test('note paths, sidecars, and stems', () {
      expect(noteBodyPath('abc'), 'notes/abc.md');
      expect(noteBodyPath('abc', trashed: true), 'trash/notes/abc.md');
      expect(sidecarPathForBody('notes/abc.md'), 'notes/abc.meta.json');
      expect(bodyPathForSidecar('trash/notes/abc.meta.json'),
          'trash/notes/abc.md');
      expect(noteStemOf('notes/My note.md'), 'My note');
      expect(isNoteBodyPath('notes/a.md'), isTrue);
      expect(isNoteBodyPath('trash/notes/a.md'), isTrue);
      expect(isNoteBodyPath('notes/sub/a.md'), isFalse);
      expect(isNoteBodyPath('history/x/1.md'), isFalse);
      expect(isSidecarPath('notes/a.meta.json'), isTrue);
      expect(historyIndexPath('h'), 'history/h/index.json');
      expect(historyBodyPath('h', 3), 'history/h/3.md');
    });

    test('UUIDs are version 4 and map to and from hex stems', () {
      final ids = {for (var i = 0; i < 50; i++) newUuidV4()};
      expect(ids, hasLength(50));
      for (final id in ids) {
        expect(isUuid(id), isTrue);
        expect(id[14], '4');
        expect('89ab'.contains(id[19]), isTrue);
        expect(uuidFromHex(uuidHex(id)), id);
      }
      expect(uuidFromHex('not-hex'), isNull);
    });

    test('folder JSON is sorted, indented, and ends with a newline', () {
      final text = encodeFolderJson({
        'b': 1,
        'a': {'d': 2, 'c': 3},
      });
      expect(text, '{\n  "a": {\n    "c": 3,\n    "d": 2\n  },\n  "b": 1\n}\n');
    });

    test('folder paths are validated', () {
      expect(splitFolderPath(''), isEmpty);
      expect(splitFolderPath('a/b.md'), ['a', 'b.md']);
      for (final bad in ['/a', 'a/', 'a//b', '../a', 'a/./b', r'a\b']) {
        expect(() => splitFolderPath(bad), throwsA(isA<FolderFsException>()),
            reason: bad);
      }
      expect(isSwapFileName('a.md.crswap'), isTrue);
    });
  });

  group('MemoryFolderFs', () {
    test('lists skip *.crswap, writes create parents, removals need recursive',
        () async {
      final fs = MemoryFolderFs();
      await fs.writeText('notes/a.md', 'x');
      fs.externalEdit('notes/a.md.crswap', 'swap');
      expect((await fs.list('notes')).map((e) => e.name), ['a.md']);
      expect((await fs.list('')).single.isDirectory, isTrue);
      await expectLater(fs.remove('notes'),
          throwsA(isA<FolderFsException>().having(
              (e) => e.kind, 'kind', FolderErrorKind.invalidModification)));
      await fs.remove('notes', recursive: true);
      expect(fs.paths, isEmpty);
    });

    test('revoke makes every call throw NotAllowedError', () async {
      final fs = MemoryFolderFs();
      await fs.writeText('a.txt', 'x');
      fs.revoke();
      expect(await fs.queryPermission(), FolderPermission.prompt);
      await expectLater(
          fs.readText('a.txt'),
          throwsA(isA<FolderFsException>()
              .having((e) => e.kind, 'kind', FolderErrorKind.notAllowed)));
      expect(await fs.requestPermission(), FolderPermission.granted);
      expect(await fs.readText('a.txt'), 'x');
    });

    test('an aborted write leaves the old file', () async {
      final fs = MemoryFolderFs();
      await fs.writeText('a.txt', 'old');
      fs.failNext(FolderErrorKind.abort, operation: 'write');
      await expectLater(fs.writeText('a.txt', 'new'), throwsA(anything));
      expect(fs.textOf('a.txt'), 'old');
    });

    test('views share the entry; copies do not', () async {
      final fs = MemoryFolderFs();
      expect(await fs.isSameEntry(fs.view()), isTrue);
      expect(await fs.isSameEntry(fs.copy()), isFalse);
    });
  });
}
