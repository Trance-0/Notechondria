import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_journal.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_lock.dart';
import 'package:notechondria_shared/src/local_folder/note_codec.dart';

import 'folder_fixtures.dart';

final String _lock = folderLockName(kTestFolderId);

/// One "tab": its own handle on the folder and its own journal, sharing the
/// lock manager with the other tabs.
class _Tab {
  _Tab(MemoryFolderFs folder, this.locks, String app)
      : fs = folder.view(),
        journal = FolderJournal(folder.view(), app: app);

  final MemoryFolderFs fs;
  final MemoryFolderLocks locks;
  final FolderJournal journal;

  /// A write as a handler runs it: exclusive hold, roll forward first, then
  /// re-read from disk (6.2 R2) and journal the change.
  Future<int> createNote(String title) =>
      locks.run(_lock, FolderLockMode.exclusive, () async {
        await journal.rollForward();
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return (await createNoteOp(fs, journal, title: title)).id;
      });
}

void main() {
  group('two writers over one MemoryFolderFs (6.2 R2)', () {
    test('concurrent creates get distinct ids and the higher counter wins',
        () async {
      final folder = await newNotechondriaFolder();
      final locks = MemoryFolderLocks();
      final a = _Tab(folder, locks, 'editor');
      final b = _Tab(folder, locks, 'planner');
      final ids = await Future.wait([
        for (var i = 0; i < 10; i++) (i.isEven ? a : b).createNote('n$i'),
      ]);
      expect(ids.toSet(), hasLength(10));
      expect(ids.toSet(), {for (var i = 1; i <= 10; i++) i});
      expect((await readFolderManifest(folder))!.counter('note'), 10);
      final sidecars = [
        for (final p in folder.paths)
          if (p.endsWith('.meta.json')) decodeSidecar(folder.textOf(p)!)!.id,
      ];
      expect(sidecars.toSet(), hasLength(10));
    });

    test('writers in two tabs continue one counter',
        () async {
      final folder = await newNotechondriaFolder();
      final locks = MemoryFolderLocks();
      final a = _Tab(folder, locks, 'editor');
      final b = _Tab(folder, locks, 'planner');
      final first = await a.createNote('x');
      final second = await b.createNote('y');
      expect(second, first + 1);
    });
  });

  group('concurrent roll-forward (3.4.1)', () {
    test('two tabs that both find one leftover record roll it forward once',
        () async {
      final folder = await newNotechondriaFolder();
      final locks = MemoryFolderLocks();
      final writer = FolderJournal(folder, app: 'editor');
      const uuid = '1b4e28ba-2fa1-41d2-883f-0016d3cca427';
      folder.crashAfterWrites(1);
      await expectLater(
          createNoteOp(folder, writer, uuid: uuid), throwsA(isA<MemoryFolderCrash>()));
      final a = _Tab(folder, locks, 'editor');
      final b = _Tab(folder, locks, 'planner');
      // Both see the record before either holds the lock.
      expect(await a.journal.listPending(), hasLength(1));
      expect(await b.journal.listPending(), hasLength(1));
      final results = await Future.wait([
        rollForwardUnderLock(locks: locks, lockName: _lock, journal: a.journal),
        rollForwardUnderLock(locks: locks, lockName: _lock, journal: b.journal),
      ]);
      expect(results.map((r) => r.replayed.length).toList()..sort(), [0, 1]);
      expect(folder.exists(noteBodyPath(uuidHex(uuid))), isTrue);
      expect(await a.journal.listPending(), isEmpty);
    });

    test('a reader meeting a journal rolls it forward before it reads (R3)',
        () async {
      final folder = await newNotechondriaFolder();
      final locks = MemoryFolderLocks();
      final journal = FolderJournal(folder, app: 'editor');
      const uuid = '1b4e28ba-2fa1-41d2-883f-0016d3cca427';
      folder.crashAfterWrites(2);
      await expectLater(createNoteOp(folder, journal, uuid: uuid),
          throwsA(isA<MemoryFolderCrash>()));
      final seen = await readWithJournalCheck(
        locks: locks,
        lockName: _lock,
        journal: journal,
        read: (skip) async {
          expect(skip, isEmpty);
          expect(locks.isHeldExclusive(_lock), isFalse);
          return folder.exists(sidecarPathForBody(noteBodyPath(uuidHex(uuid))));
        },
      );
      expect(seen, isTrue);
    });

    test('a failed roll-forward makes readers skip the record paths', () async {
      final folder = await newNotechondriaFolder();
      final locks = MemoryFolderLocks();
      final journal = FolderJournal(folder, app: 'editor');
      const uuid = '1b4e28ba-2fa1-41d2-883f-0016d3cca427';
      folder.crashAfterWrites(1);
      await expectLater(createNoteOp(folder, journal, uuid: uuid),
          throwsA(isA<MemoryFolderCrash>()));
      folder.failNext(FolderErrorKind.notAllowed,
          operation: 'write', pathPrefix: 'notes/');
      final skipped = await readWithJournalCheck(
        locks: locks,
        lockName: _lock,
        journal: journal,
        read: (skip) async => skip,
      );
      expect(skipped, contains(noteBodyPath(uuidHex(uuid))));
      expect(skipped, contains(kManifestPath));
    });
  });

  group('MemoryFolderLocks (Web Locks grant order)', () {
    test('shared holds overlap; an exclusive request waits for both', () async {
      final locks = MemoryFolderLocks();
      final events = <String>[];
      final release = Completer<void>();
      final r1 = locks.run(_lock, FolderLockMode.shared, () async {
        events.add('r1');
        await release.future;
      });
      final r2 = locks.run(_lock, FolderLockMode.shared, () async {
        events.add('r2');
        await release.future;
      });
      final w = locks.run(_lock, FolderLockMode.exclusive, () async {
        events.add('w');
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, ['r1', 'r2']);
      expect(locks.heldCount(_lock), 2);
      release.complete();
      await Future.wait([r1, r2, w]);
      expect(events, ['r1', 'r2', 'w']);
      expect(locks.heldCount(_lock), 0);
    });

    test('a reader behind a waiting writer waits (no writer starvation)',
        () async {
      final locks = MemoryFolderLocks();
      final events = <String>[];
      final release = Completer<void>();
      final r1 = locks.run(_lock, FolderLockMode.shared, () => release.future);
      final w = locks.run(_lock, FolderLockMode.exclusive, () async {
        events.add('w');
      });
      final r2 = locks.run(_lock, FolderLockMode.shared, () async {
        events.add('r2');
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      release.complete();
      await Future.wait([r1, w, r2]);
      expect(events, ['w', 'r2']);
    });

    test('a throwing operation releases the lock', () async {
      final locks = MemoryFolderLocks();
      await expectLater(
          locks.run(_lock, FolderLockMode.exclusive,
              () async => throw StateError('boom')),
          throwsA(isA<StateError>()));
      expect(locks.heldCount(_lock), 0);
      expect(await locks.run(_lock, FolderLockMode.exclusive, () async => 1), 1);
    });

    test('a wait at the cap is not cut by the deadline (R5)', () async {
      final locks = MemoryFolderLocks(maxWait: const Duration(milliseconds: 30));
      final release = Completer<void>();
      final holder =
          locks.run(_lock, FolderLockMode.exclusive, () => release.future);
      await expectLater(
          locks.run(_lock, FolderLockMode.shared, () async {},
              timeLeft: const Duration(seconds: 8)),
          throwsA(isA<FolderLockTimeout>()
              .having((e) => e.cutByDeadline, 'cutByDeadline', isFalse)
              .having((e) => e.waited, 'waited',
                  const Duration(milliseconds: 30))));
      release.complete();
      await holder;
      expect(locks.pendingCount(_lock), 0);
    });

    test('a wait shorter than the cap is cut by the deadline (T7(h))',
        () async {
      final locks = MemoryFolderLocks();
      final release = Completer<void>();
      final holder =
          locks.run(_lock, FolderLockMode.exclusive, () => release.future);
      await expectLater(
          locks.run(_lock, FolderLockMode.exclusive, () async {},
              timeLeft: const Duration(milliseconds: 20)),
          throwsA(isA<FolderLockTimeout>()
              .having((e) => e.cutByDeadline, 'cutByDeadline', isTrue)));
      await expectLater(
          locks.run(_lock, FolderLockMode.exclusive, () async {},
              timeLeft: Duration.zero),
          throwsA(isA<FolderLockTimeout>()));
      release.complete();
      await holder;
    });

    test('folderLockWait takes min(cap, time left)', () {
      const cap = Duration(seconds: 5);
      expect(folderLockWait(null, cap), (wait: cap, cutByDeadline: false));
      expect(folderLockWait(const Duration(seconds: 7), cap),
          (wait: cap, cutByDeadline: false));
      expect(folderLockWait(const Duration(seconds: 3), cap),
          (wait: const Duration(seconds: 3), cutByDeadline: true));
      expect(folderLockWait(const Duration(seconds: -1), cap),
          (wait: Duration.zero, cutByDeadline: true));
    });
  });
}
