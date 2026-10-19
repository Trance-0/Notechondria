import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_identity.dart';
import 'package:notechondria_shared/src/local_folder/folder_index.dart';
import 'package:notechondria_shared/src/local_folder/folder_journal.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock.dart';
import 'package:notechondria_shared/src/local_folder/folder_scanner.dart';
import 'package:notechondria_shared/src/local_folder/folder_snapshots.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

import 'folder_fixtures.dart';

const String _u1 = '1b4e28ba-2fa1-41d2-883f-0016d3cca427';
const String _u2 = '2c5ea4c0-4067-41fb-8f04-0c0f1e8cbe00';

({FolderScanner scanner, List<String> logs, List<ScanProgress> progress})
    _scanner(MemoryFolderFs fs, {int pageSize = kScanPageSize}) {
  final logs = <String>[];
  final progress = <ScanProgress>[];
  final journal =
      FolderJournal(fs, app: 'editor', log: (level, message) => logs.add(message));
  return (
    scanner: FolderScanner(
      fs: fs,
      locks: MemoryFolderLocks(),
      lockName: folderLockName(kTestFolderId),
      journal: journal,
      folderId: kTestFolderId,
      pageSize: pageSize,
      onProgress: progress.add,
    ),
    logs: logs,
    progress: progress,
  );
}

Future<void> _note(MemoryFolderFs fs, String uuid,
    {int? id, String? stem, bool sidecar = true, String title = 'T'}) async {
  final path = noteBodyPath(stem ?? uuidHex(uuid));
  await fs.writeText(path, noteText(uuid, title, 'body of $title'));
  if (sidecar && id != null) {
    await fs.writeText(
        sidecarPathForBody(path), NoteSidecar(id: id, uuid: uuid).encode());
  }
}

String? _uuidAt(MemoryFolderFs fs, String mdPath) =>
    decodeSidecar(fs.textOf(sidecarPathForBody(mdPath))!)?.uuid;

void main() {
  group('duplicate UUIDs (3.7)', () {
    test('a file-manager copy without a sidecar gets a new identity', () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 1);
      final copy = 'notes/${uuidHex(_u1)} copy.md';
      fs.externalEdit(copy, fs.textOf(noteBodyPath(uuidHex(_u1)))!);
      final s = _scanner(fs);
      final result = await s.scanner.scan();
      expect(result.fixes.single, isA<ReassignNoteUuid>());
      expect(_uuidAt(fs, noteBodyPath(uuidHex(_u1))), _u1);
      final fresh = _uuidAt(fs, copy)!;
      expect(fresh, isNot(_u1));
      expect(frontmatterUuidOf(fs.textOf(copy)!), fresh);
      expect(decodeSidecar(fs.textOf(sidecarPathForBody(copy))!)!.id, 2);
      expect((await readFolderManifest(fs))!.counter('note'), 2);
      expect(
          s.logs,
          contains("Note identity reassigned: Shared.LocalFolder/scan — '$copy' "
              "claimed uuid $_u1, which '${noteBodyPath(uuidHex(_u1))}' already "
              'uses; it now has uuid $fresh.'));
    });

    test('a copy with its sidecar: the stem that spells the UUID keeps it',
        () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 1);
      final original = noteBodyPath(uuidHex(_u1));
      await _note(fs, _u1, id: 1, stem: 'aaa copy');
      final result = await _scanner(fs).scanner.scan();
      expect(result.fixes.whereType<ReassignNoteUuid>().single.path,
          'notes/aaa copy.md');
      expect(_uuidAt(fs, original), _u1);
      expect(decodeSidecar(fs.textOf(sidecarPathForBody(original))!)!.id, 1);
      final copySidecar =
          decodeSidecar(fs.textOf('notes/aaa copy.meta.json')!)!;
      expect(copySidecar.uuid, isNot(_u1));
      expect(copySidecar.id, 2);
      expect(copySidecar.clientDraftId, 'fld_${uuidHex(copySidecar.uuid!)}');
    });

    test('keeper order: own sidecar, then hex stem, then first path', () {
      IndexedFile note(String path, String? uuid) => IndexedFile(
          path: path, size: 1, lastModified: 1, kind: IndexedKind.note, uuid: uuid);
      IndexedFile side(String md, String uuid, int id) => IndexedFile(
          path: sidecarPathForBody(md),
          size: 1,
          lastModified: 1,
          kind: IndexedKind.sidecar,
          uuid: uuid,
          id: id);
      final files = {
        for (final f in [
          note('notes/a.md', _u1),
          note('notes/b.md', _u1),
          side('notes/b.md', _u1, 4),
          note('notes/${uuidHex(_u2)}.md', _u2),
          note('notes/c.md', _u2),
          note('notes/d.md', _u2),
        ])
          f.path: f,
      };
      final fixes = planIdentityFixes(files).whereType<ReassignNoteUuid>();
      expect({for (final f in fixes) f.path: f.keeper}, {
        'notes/a.md': 'notes/b.md',
        'notes/c.md': 'notes/${uuidHex(_u2)}.md',
        'notes/d.md': 'notes/${uuidHex(_u2)}.md',
      });
    });

    test('a scan during a trash move never reports the note twice', () async {
      final fs = await newNotechondriaFolder();
      final journal = FolderJournal(fs, app: 'editor');
      await createNoteOp(fs, journal, uuid: _u1);
      final record = await trashNoteRecord(fs, journal, _u1);
      fs.crashAfterWrites(4);
      await expectLater(journal.commit(record), throwsA(isA<MemoryFolderCrash>()));
      final result = await _scanner(fs).scanner.scan();
      final notes = [
        ...result.index.ofKind(IndexedKind.note),
        ...result.index.ofKind(IndexedKind.trashNote),
      ];
      expect(notes.map((n) => n.path), ['trash/notes/${uuidHex(_u1)}.md']);
      expect(result.fixes, isEmpty);
    });
  });

  group('adoption and duplicate ids', () {
    test('a hand-added note gets a sidecar; its .md is untouched', () async {
      final fs = await newNotechondriaFolder();
      fs.externalEdit('notes/Shopping list.md', '# Shopping\n- milk\n');
      final s = _scanner(fs);
      final result = await s.scanner.scan();
      expect(result.fixes.single, isA<AdoptNote>());
      expect(fs.textOf('notes/Shopping list.md'), '# Shopping\n- milk\n');
      final sidecar = decodeSidecar(fs.textOf('notes/Shopping list.meta.json')!)!;
      expect(sidecar.id, 1);
      expect(isUuid(sidecar.uuid), isTrue);
      final stat = (await fs.stat('notes/Shopping list.md'))!;
      expect([sidecar.mdSize, sidecar.mdLastModified], [stat.size, stat.lastModified]);
      expect(s.logs.single, startsWith('Note adopted: Shared.LocalFolder/scan — '));
      final note = result.index.files['notes/Shopping list.md']!;
      expect(note.title, 'Shopping');
    });

    test('two notes with one id: the hex stem keeps it', () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 5);
      await _note(fs, _u2, id: 5, stem: 'other');
      final result = await _scanner(fs).scanner.scan();
      expect(result.fixes.single, isA<ReassignNoteId>());
      expect(decodeSidecar(fs.textOf(sidecarPathForBody(noteBodyPath(uuidHex(_u1))))!)!.id, 5);
      expect(decodeSidecar(fs.textOf('notes/other.meta.json')!)!.id, 6);
    });

    test('courses: a repeated id or client_course_id is reassigned', () async {
      final fs = await newNotechondriaFolder();
      for (final slug in ['bio', 'chem']) {
        await fs.writeText('courses/$slug.json',
            encodeFolderJson({'id': 3, 'slug': slug, 'client_course_id': 'fld_x'}));
      }
      await _scanner(fs).scanner.scan();
      final bio = jsonDecode(fs.textOf('courses/bio.json')!) as Map;
      final chem = jsonDecode(fs.textOf('courses/chem.json')!) as Map;
      expect(bio['id'], 3);
      expect(bio['client_course_id'], 'fld_x');
      expect(chem['id'], 4);
      expect(chem['client_course_id'], isNot('fld_x'));
    });

    test('planner records: missing and repeated ids get new ones', () async {
      final fs = await newNotechondriaFolder();
      await fs.writeText(kPlannerEventsPath, encodeFolderJson({
        'schema_version': 1,
        'events': [
          {'id': 2, 'title': 'a'},
          {'id': 2, 'title': 'b'},
          {'title': 'c'},
        ],
      }));
      await _scanner(fs).scanner.scan();
      final events = (jsonDecode(fs.textOf(kPlannerEventsPath)!) as Map)['events'] as List;
      expect(events.map((e) => (e as Map)['id']), [2, 3, 4]);
      expect((await readFolderManifest(fs))!.counter('event'), 4);
    });
  });

  group('counters (3.7)', () {
    test('every counter is raised above the largest id seen', () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 40);
      await fs.writeText('courses/bio.json', encodeFolderJson({'id': 9, 'slug': 'bio'}));
      await fs.writeText(kPlannerFeedsPath, encodeFolderJson([{'id': 12}]));
      await fs.writeText(kPlannerSessionsPath,
          encodeFolderJson({'sessions': [{'id': 3}]}));
      await fs.writeText(historyIndexPath(uuidHex(_u1)), encodeFolderJson({
        'versions': [{'id': 21, 'reason': 'manual', 'created_at': 'x'}],
      }));
      await fs.writeText(attachmentsIndexPath(uuidHex(_u1)),
          encodeFolderJson([{'id': 7, 'filename': 'a.png'}]));
      final s = _scanner(fs);
      final result = await s.scanner.scan();
      expect(result.countersRaised, isTrue);
      final m = (await readFolderManifest(fs))!;
      expect({for (final k in kIdKinds) k: m.counter(k)}, {
        'course': 9,
        'note': 40,
        'version': 21,
        'session': 3,
        'event': 0,
        'feed': 12,
        'attachment': 7,
      });
      expect(s.logs.first, startsWith('Folder ID counters raised: Shared.LocalFolder/scan — '));
      // A new note continues after the largest id seen.
      final created = await createNoteOp(fs, FolderJournal(fs, app: 'editor'));
      expect(created.id, 41);
    });

    test('counters above every id stay as they are', () async {
      final fs = await newNotechondriaFolder();
      await createNoteOp(fs, FolderJournal(fs, app: 'editor'), uuid: _u1);
      final result = await _scanner(fs).scanner.scan();
      expect(result.countersRaised, isFalse);
    });
  });

  group('hand-edited files (3.8)', () {
    test('wrong-typed fields read as absent and the scan finishes', () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 1);
      final hex = uuidHex(_u1);
      final sidecarPath = sidecarPathForBody(noteBodyPath(hex));
      final sidecar = jsonDecode(fs.textOf(sidecarPath)!) as Map;
      fs.externalEdit(sidecarPath, jsonEncode({
        ...sidecar,
        'description': 5,
        'word_count': 'many',
        'client_draft_id': 3,
        'md_size': '12',
      }));
      fs.externalEdit('courses/bio.json',
          jsonEncode({'id': 2, 'slug': ['bio'], 'title': 7}));
      fs.externalEdit(historyIndexPath(hex), jsonEncode({
        'note_uuid': 9,
        'versions': [
          {'id': 3, 'reason': 1, 'title': false, 'created_at': 5, 'op_id': []},
        ],
      }));
      final manifest = jsonDecode(fs.textOf(kManifestPath)!) as Map;
      fs.externalEdit(kManifestPath, jsonEncode({
        ...manifest,
        'github_sync_schema_version': 'one',
        'restored_from_folder_id': 4,
      }));

      final result = await _scanner(fs).scanner.scan();
      final indexed = result.index.files[sidecarPath]!;
      expect([indexed.uuid, indexed.id], [_u1, 1]);
      final course = result.index.files['courses/bio.json']!;
      expect([course.id, course.slug, course.title], [2, null, null]);
      expect(result.fixes, isEmpty);
      final m = (await readFolderManifest(fs))!;
      expect([m.counter('course'), m.counter('version')], [2, 3]);
      final decoded = decodeSidecar(fs.textOf(sidecarPath)!)!;
      expect([decoded.description, decoded.wordCount, decoded.clientDraftId],
          [null, null, null]);
      final entry =
          decodeHistoryIndex(fs.textOf(historyIndexPath(hex))!)!.versions.single;
      expect([entry.id, entry.reason, entry.title, entry.createdAt, entry.opId],
          [3, 'manual', null, '', null]);
    });
  });

  group('a journal record that keeps failing (6.2 R3)', () {
    test('the scan finishes and skips every change that touches it',
        () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 40);
      fs.externalEdit('notes/hand.md', '# Hand\n');
      fs.externalEdit('notes/old.md', 'old');
      final journal = FolderJournal(fs, app: 'planner');
      final record = journal.newRecord([
        const JournalWrite('notes/new.md', 'new'),
        JournalWrite(kManifestPath, fs.textOf(kManifestPath)!),
      ], [
        const JournalRemoval('notes/old.md'),
      ]);
      fs.externalEdit(record.path, encodeFolderJson(record.toJson()));
      fs.failNext(FolderErrorKind.noModificationAllowed,
          operation: 'remove', pathPrefix: 'notes/old.md', count: 1000);

      final s = _scanner(fs);
      final result = await s.scanner.scan();
      expect(result.countersRaised, isFalse);
      expect((await readFolderManifest(fs))!.counter('note'), 0);
      expect(result.fixes, isEmpty);
      expect(fs.exists('notes/hand.meta.json'), isFalse);
      expect(result.index.files.keys,
          containsAll([noteBodyPath(uuidHex(_u1)), 'notes/hand.md']));
      expect(result.index.files.keys, isNot(contains('notes/old.md')));
      expect(result.index.files.keys, isNot(contains('notes/new.md')));
      expect(await journal.listPending(), [record.opId]);
      expect(
          s.logs,
          anyElement(startsWith('Folder change not finished: '
              'Shared.LocalFolder/journal — ${record.opId} ')));
    });
  });

  group('index (T7(e))', () {
    test('the index is written with schema_version and reused for unchanged files',
        () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 1, title: 'First');
      final first = await _scanner(fs).scanner.scan();
      final json = jsonDecode(fs.textOf(kIndexPath)!) as Map;
      expect(json['schema_version'], kFolderIndexSchemaVersion);
      expect(json['layout_version'], 1);
      expect(json['folder_id'], kTestFolderId);
      final read = (await readFolderIndex(fs, folderId: kTestFolderId))!;
      expect(read.files.keys, unorderedEquals(first.index.files.keys));
      expect(read.counts.notes, 1);
      expect(await readFolderIndex(fs, folderId: 'another'), isNull);
      fs.externalEdit(kIndexPath, '{"schema_version": 99}');
      expect(await readFolderIndex(fs, folderId: kTestFolderId), isNull);

      fs.failNext(FolderErrorKind.notFound, operation: 'read',
          pathPrefix: 'notes/');
      final second = await _scanner(fs).scanner.scan(previous: first.index);
      expect(second.index.files[noteBodyPath(uuidHex(_u1))]!.title, 'First');
    });

    test('a vanished note is dropped and logged; swap files are ignored',
        () async {
      final fs = await newNotechondriaFolder();
      await _note(fs, _u1, id: 1);
      final first = await _scanner(fs).scanner.scan();
      fs.externalRemove(noteBodyPath(uuidHex(_u1)));
      fs.externalEdit('notes/x.md.crswap', 'swap');
      final s = _scanner(fs);
      final second = await s.scanner.scan(previous: first.index);
      expect(second.dropped, [noteBodyPath(uuidHex(_u1))]);
      expect(s.logs, contains(
          "Note dropped from index: Shared.LocalFolder/scan — '${noteBodyPath(uuidHex(_u1))}' no longer exists on disk."));
      expect(second.index.files.keys.where((p) => p.endsWith('.crswap')), isEmpty);
    });

    test('pages of the given size report progress', () async {
      final fs = await newNotechondriaFolder();
      for (var i = 0; i < 12; i++) {
        await createNoteOp(fs, FolderJournal(fs, app: 'editor'));
      }
      final s = _scanner(fs, pageSize: 5);
      final result = await s.scanner.scan();
      expect(result.index.counts.notes, 12);
      expect(s.progress.length, greaterThan(4));
      expect(s.progress.last.done, s.progress.last.total);
    });
  });
}
