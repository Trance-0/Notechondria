// Chromium tests for the web folder backend and the Web Locks wrapper
// (design 8.3). They need a browser and the compile-time OPFS hook:
//
//   flutter test --platform chrome \
//     --dart-define=NOTECHONDRIA_TEST_OPFS_FOLDER=true \
//     test/local_folder_opfs_test.dart
//
// The lock tests fail if the grant callback is bound with a guarded (void)
// wrapper, which would release every lock before the operation's first
// await (main 2.5); they are the regression test for that rule.
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/change_channel_web.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs_web.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock_web.dart';
import 'package:web/web.dart' as web;

var _serial = 0;
String _name(String what) =>
    'notechondria.local_folder.test-$what-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';

Future<({int held, int pending})> _query(String name) async {
  final snapshot = await web.window.navigator.locks.query().toDart;
  int count(JSArray<web.LockInfo> list) =>
      list.toDart.where((info) => info.name == name).length;
  return (held: count(snapshot.held), pending: count(snapshot.pending));
}

/// The browser releases a lock when the grant callback's promise settles,
/// a task after the Dart result is delivered, so wait for the release.
Future<({int held, int pending})> _released(String name) async {
  var state = await _query(name);
  for (var i = 0; i < 50 && state != (held: 0, pending: 0); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    state = await _query(name);
  }
  return state;
}

Future<void> _ticks(int n, Duration each) async {
  for (var i = 0; i < n; i++) {
    await Future<void>.delayed(each);
  }
}

void main() {
  group('Web Locks wrapper (folder_lock_web.dart)', () {
    test('overlapping exclusive requests on one name serialize', () async {
      final locks = WebFolderLocks();
      final name = _name('serialize');
      final events = <String>[];
      final first = locks.run(name, FolderLockMode.exclusive, () async {
        events.add('first start');
        await _ticks(4, const Duration(milliseconds: 50));
        events.add('first end');
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final second = locks.run(name, FolderLockMode.exclusive, () async {
        events.add('second start');
      });
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(await _query(name), (held: 1, pending: 1));
      await Future.wait([first, second]);
      expect(events, ['first start', 'first end', 'second start']);
      expect(await _released(name), (held: 0, pending: 0));
    });

    test('a throwing operation still releases the lock', () async {
      final locks = WebFolderLocks(maxWait: const Duration(milliseconds: 500));
      final name = _name('throw');
      await expectLater(
          locks.run(name, FolderLockMode.exclusive, () async {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            throw StateError('operation failed');
          }),
          throwsA(isA<StateError>()));
      expect(await _released(name), (held: 0, pending: 0));
      final watch = Stopwatch()..start();
      expect(
          await locks.run(name, FolderLockMode.exclusive, () async => 'next'),
          'next');
      expect(watch.elapsedMilliseconds, lessThan(400));
    });

    test('two shared holds overlap; an exclusive request waits for both',
        () async {
      final locks = WebFolderLocks();
      final name = _name('shared');
      final events = <String>[];
      final release = Completer<void>();
      Future<void> reader(String id) =>
          locks.run(name, FolderLockMode.shared, () async {
            events.add('$id start');
            await release.future;
            events.add('$id end');
          });
      final r1 = reader('r1');
      final r2 = reader('r2');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final writer = locks.run(name, FolderLockMode.exclusive, () async {
        events.add('writer');
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(await _query(name), (held: 2, pending: 1));
      release.complete();
      await Future.wait([r1, r2, writer]);
      expect(events.last, 'writer');
      expect(events.sublist(0, 2), unorderedEquals(['r1 start', 'r2 start']));
    });

    test('a wait longer than its AbortSignal.timeout fails with the lock error',
        () async {
      final locks = WebFolderLocks(maxWait: const Duration(milliseconds: 100));
      final name = _name('timeout');
      final release = Completer<void>();
      final holder =
          locks.run(name, FolderLockMode.exclusive, () => release.future);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await expectLater(
          locks.run(name, FolderLockMode.exclusive, () async {}),
          throwsA(isA<FolderLockTimeout>()
              .having((e) => e.cutByDeadline, 'cutByDeadline', isFalse)));
      await expectLater(
          locks.run(name, FolderLockMode.exclusive, () async {},
              timeLeft: const Duration(milliseconds: 50)),
          throwsA(isA<FolderLockTimeout>()
              .having((e) => e.cutByDeadline, 'cutByDeadline', isTrue)));
      release.complete();
      await holder;
      expect(await _released(name), (held: 0, pending: 0));
    });
  });

  group('BroadcastChannel listener (change_channel_web.dart)', () {
    test('a throwing listener reaches the zone error handler', () async {
      final caught = Completer<Object>();
      late WebFolderChangeChannel receiver;
      runZonedGuarded(() {
        receiver = WebFolderChangeChannel(Zone.current);
        receiver.messages.listen((_) => throw StateError('listener failed'));
      }, (error, _) {
        if (!caught.isCompleted) caught.complete(error);
      });
      final sender = WebFolderChangeChannel(Zone.root);
      sender.post({'op': 'disconnect', 'folder_id': 'x'});
      final error = await caught.future.timeout(const Duration(seconds: 5));
      expect(error, isA<StateError>());
      sender.close();
      receiver.close();
    });
  });

  group('OPFS FolderFs (folder_fs_web.dart through the 8.3 hook)', () {
    test('the hook is compiled in for this run', () {
      expect(kLocalFolderOpfsTestHook, isTrue);
    });

    test('reads, writes, lists, stats, and removes', () async {
      final fs = await openOpfsTestFolder('rw-${_serial++}');
      expect(await fs.queryPermission(), FolderPermission.granted);
      await fs.writeText('notes/a.md', 'hello');
      expect(await fs.readText('notes/a.md'), 'hello');
      expect((await fs.stat('notes/a.md'))!.size, 5);
      await fs.writeText('notes/a.md', 'hi');
      expect(await fs.readText('notes/a.md'), 'hi',
          reason: 'createWritable replaces the old content');
      await fs.writeBytes(
          'assets/notes/x/attachments/b.bin', Uint8List.fromList([1, 2, 3]));
      expect(await fs.readBytes('assets/notes/x/attachments/b.bin'),
          [1, 2, 3]);
      expect((await fs.list('notes')).map((e) => e.name), ['a.md']);
      final root = await fs.list('');
      expect(root.map((e) => e.name), containsAll(['assets', 'notes']));
      expect(root.every((e) => e.isDirectory), isTrue);
      expect(await fs.stat('notes/missing.md'), isNull);
      await expectLater(
          fs.readText('notes/missing.md'),
          throwsA(isA<FolderFsException>()
              .having((e) => e.kind, 'kind', FolderErrorKind.notFound)));
      await expectLater(
          fs.list('nowhere'),
          throwsA(isA<FolderFsException>()
              .having((e) => e.kind, 'kind', FolderErrorKind.notFound)));
      await fs.remove('notes/a.md');
      expect(await fs.stat('notes/a.md'), isNull);
      await fs.remove('assets', recursive: true);
      expect((await fs.list('')).map((e) => e.name), ['notes']);
      expect(await fs.isSameEntry(fs), isTrue);
      await fs.remove('notes', recursive: true);
    });
  });
}
