// Chromium timing check for the index-backed note lookups (phase 1b review
// P1B-1, loop 2a review L2A-1 and L2A-7): 2,000 notes on OPFS through the
// 8.3 hook, the real Web Locks wrapper, and the in-page transport. Every
// route below, the first list after an open from `index.json` (which
// compares every stored entry with the disk), the `index.json` flush, and
// a course delete (which stats every note body) must hold the folder lock
// for less than R4's 2 s target (6.2 R4, `kFolderLockHoldTarget`); a
// single-note GET or PATCH must also answer within it. The seed, scan, and
// open times and the scan's longest hold are only printed. Runs with the
// OPFS test:
//
//   flutter test --platform chrome \
//     --dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true \
//     test/local_folder_opfs_timing_test.dart
//
// The numbers are printed for the progress note; nothing else reads them.
// ignore_for_file: avoid_print
@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/change_channel.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs_web.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock_web.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_platform.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';
import 'package:notechondria_shared/src/local_folder/qualification.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_folder/backend_harness.dart';

const int _kNotes = 2000;

/// The browser platform of the test: the OPFS folder in a memory handle
/// store, and the real `navigator.locks` wrapper.
class _OpfsPlatform implements LocalFolderPlatform {
  _OpfsPlatform(this.locks);

  @override
  final FolderLocks locks;
  @override
  final MemoryHandleStore handleStore = MemoryHandleStore();
  @override
  final FolderPicker picker = MemoryFolderPicker();
  @override
  bool get isWeb => true;
  @override
  Uri get origin => Uri.parse('http://127.0.0.1:9068');
  @override
  FolderChangeChannel openChangeChannel(Zone zone) => NoopFolderChangeChannel();
  @override
  LocalFolderQualification probe() => MemoryFolderPlatform().probe();
}

/// [_kNotes] notes written straight to the folder (body and sidecar), in
/// batches, and a manifest whose note counter covers them.
Future<List<({int id, String uuid})>> _seed(
    FolderFs fs, String folderId) async {
  final now = DateTime.utc(2026, 10, 19);
  final notes = <({int id, String uuid})>[];
  for (var start = 1; start <= _kNotes; start += 50) {
    final batch = <Future<void>>[];
    for (var id = start; id < start + 50 && id <= _kNotes; id++) {
      final uuid = newUuidV4();
      final path = noteBodyPath(uuidHex(uuid));
      final edited = now.add(Duration(minutes: id)).toIso8601String();
      notes.add((id: id, uuid: uuid));
      batch.add(() async {
        await fs.writeText(
            path,
            encodeNoteFile(
                NoteFrontmatter(
                    title: 'Note $id',
                    uuid: uuid,
                    lastEdit: edited,
                    dateCreated: edited),
                'Body of note $id.\n\nA second paragraph with a few words.',
                path: path));
        await fs.writeText(sidecarPathForBody(path),
            NoteSidecar(id: id, uuid: uuid, description: 'd$id').encode());
      }());
    }
    await Future.wait(batch);
  }
  for (final file
      in initialFolderFiles(folderId: folderId, appVersion: 'test', now: now)) {
    final text = file.path == kManifestPath
        ? decodeFolderManifest(file.text).raisedTo({'note': _kNotes})!.encode()
        : file.text;
    await fs.writeText(file.path, text);
  }
  return notes;
}

void main() {
  test('routes over 2,000 OPFS notes hold the lock within R4', () async {
    final folderId = newUuidV4();
    final fs = await openOpfsTestFolder('timing-$folderId');
    final seedWatch = Stopwatch()..start();
    final notes = await _seed(fs, folderId);
    seedWatch.stop();

    final record = StorageModeRecord(
        folderId: folderId,
        folderName: fs.name,
        connectedBy: 'editor',
        connectedAt: '2026-10-19T00:00:00Z',
        remember: true);
    SharedPreferences.setMockInitialValues(
        {kSharedStorageModeKey: record.encode()});
    await LocalFolderBoot.preload();
    final holds = <Duration>[];
    final platform = _OpfsPlatform(
        WebFolderLocks(onHold: (_, __, held) => holds.add(held)));
    platform.handleStore.records[folderId] = fs;
    Future<(LocalFolderController, Duration)> open() async {
      // The flush is timed on its own below, so no timer flush lands inside
      // a timed route.
      final c = LocalFolderController.forTest(
          app: 'editor',
          platform: platform,
          boot: LocalFolderBoot.snapshot,
          indexFlushDelay: const Duration(hours: 1));
      final w = Stopwatch()..start();
      await c.open();
      return (c, w.elapsed);
    }

    Duration longest() => holds.fold(Duration.zero, (a, b) => a > b ? a : b);
    final (scanned, scanTime) = await open(); // no index.json yet: full scan
    expect(scanned.state, LocalFolderState.active);
    scanned.dispose();
    final scanHold = longest();
    final (c, indexTime) = await open();
    expect(c.state, LocalFolderState.active);
    addTearDown(c.dispose);
    print('[P1B-1 timing] seeded $_kNotes notes in '
        '${seedWatch.elapsedMilliseconds} ms; first open (full scan) '
        '${scanTime.inMilliseconds} ms, longest scan hold '
        '${scanHold.inMilliseconds} ms; open from index.json '
        '${indexTime.inMilliseconds} ms');

    final results = <String, ({int status, Duration total, Duration hold})>{};
    Future<void> timed(String label, String method, String path,
        {Object? json}) async {
      holds.clear();
      final w = Stopwatch()..start();
      final r = await callApi(c, method, path, json: json);
      w.stop();
      // The hold observer runs as the operation ends, before the reply.
      final hold = longest();
      results[label] = (status: r.statusCode, total: w.elapsed, hold: hold);
      print('[P1B-1 timing] $label: $method $path -> ${r.statusCode} in '
          '${w.elapsedMilliseconds} ms, longest hold ${hold.inMilliseconds} ms '
          '(${holds.length} holds)');
    }

    final target = notes[_kNotes ~/ 2];
    await timed('GET note by id', 'GET', '/notes/${target.id}/');
    await timed('GET note by uuid', 'GET', '/notes/uuid/${target.uuid}/');
    await timed('PATCH note by id', 'PATCH', '/notes/${target.id}/',
        json: {'content': 'Edited body.'});
    await timed('PATCH note by uuid', 'PATCH', '/notes/uuid/${target.uuid}/',
        json: {'title': 'Renamed note'});
    // The first list after the open from index.json stats every stored
    // note entry (L2A-1).
    await timed('GET notes page, first list after open', 'GET',
        '/notes/?limit=20&offset=0');
    await timed('GET notes page', 'GET', '/notes/?limit=20&offset=0');
    await timed('GET all notes', 'GET', '/notes/');
    await timed('GET notes search', 'GET', '/notes/?q=renamed');
    await timed('GET courses', 'GET', '/courses/');
    await timed('POST note with draft id', 'POST', '/notes/',
        json: {'title': 'New', 'content': 'x', 'client_draft_id': 'timing-1'});
    await timed('DELETE note', 'DELETE', '/notes/${notes.first.id}/');
    holds.clear();
    final flushWatch = Stopwatch()..start();
    await c.flushIndex();
    flushWatch.stop();
    results['index.json flush'] =
        (status: 200, total: flushWatch.elapsed, hold: longest());
    print('[P1B-1 timing] index.json flush: ${flushWatch.elapsedMilliseconds} '
        'ms, longest hold ${longest().inMilliseconds} ms (${holds.length} holds)');
    final course = await callApi(c, 'POST', '/courses/', json: {'title': 'Timing'});
    expect(course.statusCode, 201, reason: course.body);
    final courseId = (jsonDecode(course.body) as Map)['id'];
    await timed('DELETE course, stats every note', 'DELETE', '/courses/$courseId/');
    // Notes the index lacks (another tab's, or written since the last
    // scan): the list's listing reads only those.
    for (var start = 0; start < 300; start += 50) {
      await Future.wait([
        for (var i = start; i < start + 50; i++)
          () async {
            final uuid = newUuidV4();
            final path = noteBodyPath(uuidHex(uuid));
            await fs.writeText(path,
                encodeNoteFile(NoteFrontmatter(title: 'Added $i', uuid: uuid), 'x', path: path));
            await fs.writeText(sidecarPathForBody(path),
                NoteSidecar(id: 5000 + i, uuid: uuid).encode());
          }(),
      ]);
    }
    await timed('GET notes page, 300 new on disk', 'GET', '/notes/?limit=20&offset=0');

    for (final label in const [
      'GET note by id',
      'GET note by uuid',
      'PATCH note by id',
      'PATCH note by uuid',
    ]) {
      final r = results[label]!;
      expect(r.status, 200, reason: label);
      expect(r.total, lessThan(kFolderLockHoldTarget), reason: label);
    }
    // L2A-7: every route's hold, not only the single-note ones.
    for (final e in results.entries) {
      expect(e.value.status, anyOf(200, 201, 204), reason: e.key);
      expect(e.value.hold, lessThan(kFolderLockHoldTarget), reason: e.key);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
