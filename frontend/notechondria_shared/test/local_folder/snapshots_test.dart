import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_snapshots.dart';

import 'folder_fixtures.dart';

const String _uuid = '1b4e28ba-2fa1-41d2-883f-0016d3cca427';

HistoryEntry _v(int id, String reason) => HistoryEntry(
    id: id,
    reason: reason,
    label: '',
    createdAt: '2026-10-19T00:00:${id.toString().padLeft(2, '0')}Z');

void main() {
  group('two-pool prune (3.8)', () {
    test('each pool keeps its 12 newest; one pool never prunes the other', () {
      final versions = [
        for (var i = 1; i <= 15; i++) _v(i, 'autosave_1m'),
        for (var i = 16; i <= 30; i++)
          _v(i, i.isEven ? 'concurrent_edit' : 'external_edit'),
        _v(31, 'manual'),
      ];
      final result = pruneHistory(versions);
      final backend = result.kept.where((v) => !v.isFolderOnly).map((v) => v.id);
      final folderOnly = result.kept.where((v) => v.isFolderOnly).map((v) => v.id);
      expect(backend, [31, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5]);
      expect(folderOnly, [for (var i = 30; i >= 19; i--) i]);
      expect(result.kept, hasLength(24));
      expect(result.pruned.map((v) => v.id).toSet(),
          {1, 2, 3, 4, 16, 17, 18});
    });

    test('many folder-only snapshots never push out a manual one', () {
      final result = pruneHistory([
        _v(1, 'manual'),
        for (var i = 2; i <= 40; i++) _v(i, 'concurrent_edit'),
      ]);
      expect(result.kept.map((v) => v.id), contains(1));
    });
  });

  group('which snapshot before an overwrite (T7(j))', () {
    const disk = FolderStat(size: 10, lastModified: 500);

    test('unchanged since the last app write and last serve: none', () {
      expect(
          overwriteSnapshotReason(
              disk: disk,
              sidecarSize: 10,
              sidecarLastModified: 500,
              servedLastModified: 500),
          isNull);
      expect(overwriteSnapshotReason(disk: null, sidecarSize: 1), isNull);
    });

    test('another tab wrote it through the app: concurrent_edit', () {
      expect(
          overwriteSnapshotReason(
              disk: disk,
              sidecarSize: 10,
              sidecarLastModified: 500,
              servedLastModified: 400),
          'concurrent_edit');
    });

    test('another editor changed it: external_edit, even when both trip', () {
      expect(
          overwriteSnapshotReason(
              disk: disk,
              sidecarSize: 9,
              sidecarLastModified: 400,
              servedLastModified: 400),
          'external_edit');
      expect(
          overwriteSnapshotReason(
              disk: disk, sidecarSize: 10, sidecarLastModified: 499),
          'external_edit');
    });
  });

  group('snapshot writer', () {
    test('allocates a version id, writes body and index, prunes its pool',
        () async {
      final fs = await newNotechondriaFolder();
      final writer = FolderSnapshotWriter(fs,
          now: () => DateTime.utc(2026, 10, 19, 8, 30));
      final path = 'notes/${uuidHex(_uuid)}.md';
      HistoryEntry? last;
      for (var i = 0; i < 14; i++) {
        last = await writer.write(
            noteUuid: _uuid,
            reason: 'external_edit',
            text: noteText(_uuid, 'T$i', 'v$i'),
            notePath: path,
            opId: 'op$i');
      }
      expect(last!.id, 14);
      expect(last.title, 'T13');
      expect((await readFolderManifest(fs))!.counter('version'), 14);
      final index = (await writer.readIndex(uuidHex(_uuid)))!;
      expect(index.noteUuid, _uuid);
      expect(index.versions, hasLength(12));
      expect(index.versions.first.id, 14);
      expect(fs.exists(historyBodyPath(uuidHex(_uuid), 1)), isFalse);
      expect(fs.exists(historyBodyPath(uuidHex(_uuid), 2)), isFalse);
      expect(fs.exists(historyBodyPath(uuidHex(_uuid), 3)), isTrue);
      expect(await writer.hasEntryForOp(uuidHex(_uuid), 'op13'), isTrue);
      expect(await writer.hasEntryForOp(uuidHex(_uuid), 'op0'), isFalse);
    });

    test('plan changes nothing on disk', () async {
      final fs = await newNotechondriaFolder();
      final before = folderTexts(fs);
      final plan = await FolderSnapshotWriter(fs).plan(
          noteUuid: _uuid,
          reason: 'concurrent_edit',
          text: 'x',
          notePath: 'notes/a.md');
      expect(folderTexts(fs), before);
      expect(plan.entry.id, 1);
      expect(plan.bodyPath, historyBodyPath(uuidHex(_uuid), 1));
      expect(decodeFolderManifest(plan.manifestText).counter('version'), 1);
    });

    test('labels follow version_label', () {
      final t = DateTime(2026, 10, 19, 8, 5);
      expect(historyVersionLabel('autosave_1m', t), 'AutoSave-1m');
      expect(historyVersionLabel('AUTOSAVE_1H', t), 'AutoSave-1h');
      expect(historyVersionLabel('external_edit', t), '2026-10-19 08:05');
    });
  });
}
