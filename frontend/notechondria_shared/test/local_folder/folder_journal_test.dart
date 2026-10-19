import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_journal.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_snapshots.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

import 'folder_fixtures.dart';

const String _uuid = '1b4e28ba-2fa1-41d2-883f-0016d3cca427';

FolderJournal _journal(MemoryFolderFs fs, [List<String>? logs]) =>
    FolderJournal(fs,
        app: 'editor',
        now: () => DateTime.utc(2026, 10, 19, 12),
        log: (level, message) => logs?.add(message));

/// Runs [operation] with a crash before mutation [n]; true if it crashed.
Future<bool> _crashAt(MemoryFolderFs fs, int n, Future<void> Function() operation) async {
  fs.crashAfterWrites(n);
  try {
    await operation();
    fs.cancelCrash();
    return false;
  } on MemoryFolderCrash {
    return true;
  }
}

void main() {
  group('commit (3.4.1 steps 2 to 5)', () {
    test('a create writes body, sidecar, manifest and leaves no record',
        () async {
      final fs = await newNotechondriaFolder();
      final created = await createNoteOp(fs, _journal(fs), uuid: _uuid);
      expect(created.id, 1);
      final path = noteBodyPath(uuidHex(_uuid));
      expect(fs.exists(path), isTrue);
      expect(decodeSidecar(fs.textOf(sidecarPathForBody(path))!)!.id, 1);
      expect((await readFolderManifest(fs))!.counter('note'), 1);
      expect(await _journal(fs).listPending(), isEmpty);
    });

    test('writes apply bodies, sidecars, other, shared indexes, manifest',
        () async {
      final fs = await newNotechondriaFolder();
      final journal = _journal(fs);
      final record = journal.newRecord([
        JournalWrite(kManifestPath, fs.textOf(kManifestPath)!),
        const JournalWrite('planner/events.json', '[]\n'),
        const JournalWrite('history/h/1.md', 'snap'),
        const JournalWrite('notes/a.meta.json', '{}\n'),
        const JournalWrite('courses/c.json', '{}\n'),
        const JournalWrite('notes/a.md', 'body'),
        const JournalWrite(kRecycleBinPath, '[]\n'),
      ]);
      await journal.commit(record);
      // Each write gets the fake's next lastModified, so it shows the order.
      final stamps = {
        for (final w in record.writes)
          w.path: (await fs.stat(w.path))!.lastModified,
      };
      final order = stamps.keys.toList()
        ..sort((a, b) => stamps[a]!.compareTo(stamps[b]!));
      expect(order, [
        'notes/a.md',
        'notes/a.meta.json',
        'history/h/1.md',
        'courses/c.json',
        'planner/events.json',
        kRecycleBinPath,
        kManifestPath,
      ]);
    });

    test('removals come last: an interrupted move keeps the source', () async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, _journal(fs), uuid: _uuid);
      final journal = _journal(fs);
      final record = await trashNoteRecord(fs, journal, _uuid);
      // record write + 3 writes = 4 mutations, then the first removal.
      expect(await _crashAt(fs, 4, () => journal.commit(record)), isTrue);
      expect(fs.exists(noteBodyPath(uuidHex(_uuid))), isTrue);
      expect(fs.exists(noteBodyPath(uuidHex(_uuid), trashed: true)), isTrue);
      await _journal(fs).rollForward();
      expect(fs.exists(noteBodyPath(uuidHex(_uuid))), isFalse);
      expect(fs.exists(noteBodyPath(uuidHex(_uuid), trashed: true)), isTrue);
    });

    test('step 4 runs before removals: a failed check keeps the source',
        () async {
      final fs = await newNotechondriaFolder();
      await fs.writeText('notes/keep.md', 'source');
      final journal = _journal(fs);
      final record = journal.newRecord(
          [const JournalWrite('trash/notes/keep.md', 'copy')],
          [const JournalRemoval('notes/keep.md')]);
      fs.failNext(FolderErrorKind.notFound,
          operation: 'stat', pathPrefix: 'trash/');
      await expectLater(journal.commit(record), throwsA(anything));
      expect(fs.textOf('notes/keep.md'), 'source');
      expect(await journal.listPending(), [record.opId]);
    });
  });

  group('crash at each step, then roll-forward', () {
    Future<void> runCreate(int n) async {
      final fs = await newNotechondriaFolder();
      final before = folderTexts(fs);
      final crashed =
          await _crashAt(fs, n, () => createNoteOp(fs, _journal(fs), uuid: _uuid));
      expect(crashed, isTrue, reason: 'crash point $n');
      await _journal(fs).rollForward();
      final after = folderTexts(fs);
      final path = noteBodyPath(uuidHex(_uuid));
      if (n == 0) {
        expect(after, before, reason: 'no record: old state');
      } else {
        expect(after[path], noteText(_uuid, 'Note', 'Body'));
        expect(decodeSidecar(after[sidecarPathForBody(path)]!)!.id, 1);
        expect(decodeFolderManifest(after[kManifestPath]!).counter('note'), 1);
      }
      expect(await _journal(fs).listPending(), isEmpty);
    }

    // Mutations: record, body, sidecar, manifest, record removal.
    for (var n = 0; n < 5; n++) {
      test('note create, crash before mutation $n', () => runCreate(n));
    }

    Future<void> runTrash(int n) async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, _journal(fs), uuid: _uuid);
      final before = folderTexts(fs);
      final journal = _journal(fs);
      final record = await trashNoteRecord(fs, journal, _uuid);
      expect(await _crashAt(fs, n, () => journal.commit(record)), isTrue);
      await _journal(fs).rollForward();
      final after = folderTexts(fs);
      final live = noteBodyPath(uuidHex(_uuid));
      final trash = noteBodyPath(uuidHex(_uuid), trashed: true);
      if (n == 0) {
        expect(after, before);
      } else {
        expect(after.containsKey(live), isFalse);
        expect(after.containsKey(sidecarPathForBody(live)), isFalse);
        expect(decodeNoteFile(after[trash]!, path: trash).frontmatter.isPublic,
            isFalse);
        expect(decodeSidecar(after[sidecarPathForBody(trash)]!)!.deletedAt,
            isNotNull);
      }
    }

    // Mutations: record, 3 writes, 2 removals, record removal.
    for (var n = 0; n < 7; n++) {
      test('trash move, crash before mutation $n', () => runTrash(n));
    }

    test('a crash in the middle of a replay replays again to the end',
        () async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, _journal(fs), uuid: _uuid);
      final journal = _journal(fs);
      final record = await trashNoteRecord(fs, journal, _uuid);
      expect(await _crashAt(fs, 1, () => journal.commit(record)), isTrue);
      expect(await _crashAt(fs, 2, () => _journal(fs).rollForward()), isTrue);
      final result = await _journal(fs).rollForward();
      expect(result.replayed, [record.opId]);
      expect(fs.exists(noteBodyPath(uuidHex(_uuid))), isFalse);
      expect(fs.exists(noteBodyPath(uuidHex(_uuid), trashed: true)), isTrue);
    });
  });

  group('roll-forward rules', () {
    test('three leftover records apply in op-id order', () async {
      final fs = await newNotechondriaFolder();
      final journal = _journal(fs);
      final records = [
        for (final text in ['first', 'second', 'third'])
          journal.newRecord([JournalWrite('profile/skill.md', text)]),
      ];
      for (final r in records.reversed) {
        await fs.writeText(r.path, encodeFolderJson(r.toJson()));
      }
      final result = await _journal(fs).rollForward();
      expect(result.replayed, records.map((r) => r.opId).toList());
      expect(fs.textOf('profile/skill.md'), 'third');
    });

    test('op ids sort by creation', () {
      final ids = JournalOpIds();
      final a = ids.next(DateTime.utc(2026, 1, 1));
      final b = ids.next(DateTime.utc(2026, 1, 1));
      final c = ids.next(DateTime.utc(2026, 1, 2));
      expect([c, a, b]..sort(), [a, b, c]);
      expect(a, matches(RegExp(r'^\d{13}-\d{4}-[0-9a-f]{8}$')));
    });

    test('replaying an applied record is a no-op; missing removals are fine',
        () async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, _journal(fs), uuid: _uuid);
      final journal = _journal(fs);
      final record = await trashNoteRecord(fs, journal, _uuid);
      await journal.commit(record);
      final done = folderTexts(fs);
      await fs.writeText(record.path, encodeFolderJson(record.toJson()));
      await _journal(fs).rollForward();
      expect(folderTexts(fs), done);
    });

    test('an unreadable record is logged and discarded', () async {
      final fs = await newNotechondriaFolder();
      await fs.writeText('$kJournalDir/0000000000001-0000-00000000.json', '{');
      final logs = <String>[];
      final result = await _journal(fs, logs).rollForward();
      expect(result.replayed, isEmpty);
      expect(await _journal(fs).listPending(), isEmpty);
      expect(logs.single, startsWith('Folder change discarded: Shared.LocalFolder/journal — '));
    });
  });

  group('the expect check (N15)', () {
    Future<(MemoryFolderFs, JournalRecord)> patchCrashedAfterRecord() async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, _journal(fs), uuid: _uuid);
      final path = noteBodyPath(uuidHex(_uuid));
      final journal = _journal(fs);
      final record = journal.newRecord([
        JournalWrite(path, noteText(_uuid, 'Note', 'Journaled'),
            expect: JournalExpect.of((await fs.stat(path))!)),
      ]);
      expect(await _crashAt(fs, 1, () => journal.commit(record)), isTrue);
      return (fs, record);
    }

    test('an edit after the crash is kept as one external_edit snapshot',
        () async {
      final (fs, record) = await patchCrashedAfterRecord();
      final path = noteBodyPath(uuidHex(_uuid));
      final external = noteText(_uuid, 'Note', 'Edited in another editor');
      fs.externalEdit(path, external);
      final logs = <String>[];
      final result = await _journal(fs, logs).rollForward();
      expect(result.snapshots, 1);
      expect(fs.textOf(path), noteText(_uuid, 'Note', 'Journaled'));
      final index = decodeHistoryIndex(
          fs.textOf(historyIndexPath(uuidHex(_uuid)))!)!;
      final entry = index.versions.single;
      expect(entry.reason, 'external_edit');
      expect(entry.opId, record.opId);
      expect(fs.textOf(historyBodyPath(uuidHex(_uuid), entry.id)), external);
      expect((await readFolderManifest(fs))!.counter('version'), entry.id);
      expect(logs.single, startsWith('External edit kept: Shared.LocalFolder/journal — '));
    });

    test('a second replay of the same record adds no snapshot', () async {
      final (fs, record) = await patchCrashedAfterRecord();
      final path = noteBodyPath(uuidHex(_uuid));
      fs.externalEdit(path, noteText(_uuid, 'Note', 'External'));
      // Crash after the snapshot's three writes, before the body write.
      expect(await _crashAt(fs, 3, () => _journal(fs).rollForward()), isTrue);
      final again = await _journal(fs).rollForward();
      expect(again.snapshots, 0);
      final index = decodeHistoryIndex(
          fs.textOf(historyIndexPath(uuidHex(_uuid)))!)!;
      expect(index.versions, hasLength(1));
      expect(fs.textOf(path), noteText(_uuid, 'Note', 'Journaled'));
    });

    test('no snapshot when the body is unchanged or already journaled',
        () async {
      final (fs, _) = await patchCrashedAfterRecord();
      expect((await _journal(fs).rollForward()).snapshots, 0);
      expect(fs.exists(historyIndexPath(uuidHex(_uuid))), isFalse);
    });

    test('a delete interrupted before its removals keeps a later edit',
        () async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, _journal(fs), uuid: _uuid);
      final journal = _journal(fs);
      final record = await trashNoteRecord(fs, journal, _uuid);
      expect(await _crashAt(fs, 4, () => journal.commit(record)), isTrue);
      final live = noteBodyPath(uuidHex(_uuid));
      final edited = noteText(_uuid, 'Note', 'Edited after the crash');
      fs.externalEdit(live, edited);
      final result = await _journal(fs).rollForward();
      expect(result.snapshots, 1);
      expect(fs.exists(live), isFalse);
      final index = decodeHistoryIndex(
          fs.textOf(historyIndexPath(uuidHex(_uuid)))!)!;
      expect(fs.textOf(historyBodyPath(uuidHex(_uuid), index.versions.single.id)),
          edited);
    });

    test('a journaled manifest never lowers a counter the replay raised',
        () async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, _journal(fs), uuid: _uuid);
      final path = noteBodyPath(uuidHex(_uuid));
      final journal = _journal(fs);
      final manifest = (await readFolderManifest(fs))!;
      final record = journal.newRecord([
        JournalWrite(path, noteText(_uuid, 'Note', 'New'),
            expect: JournalExpect.of((await fs.stat(path))!)),
        JournalWrite(kManifestPath, manifest.encode()),
      ]);
      expect(await _crashAt(fs, 1, () => journal.commit(record)), isTrue);
      fs.externalEdit(path, noteText(_uuid, 'Note', 'External'));
      await _journal(fs).rollForward();
      final after = (await readFolderManifest(fs))!;
      expect(after.counter('version'), 1);
      expect(after.counter('note'), 1);
      expect(jsonDecode(fs.textOf(kManifestPath)!)['folder_id'], kTestFolderId);
    });
  });
}
