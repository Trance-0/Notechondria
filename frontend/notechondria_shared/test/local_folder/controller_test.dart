import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/local_folder/folder_fs.dart';
import 'package:notechondria_shared/src/local_folder/folder_layout.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/folder_pick_flow.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'folder_fixtures.dart';

const String _otherId = 'f0000000-0000-4000-8000-000000000002';

StorageModeRecord _record({bool remember = true}) => StorageModeRecord(
    folderId: kTestFolderId,
    folderName: 'Notes',
    connectedBy: 'editor',
    connectedAt: '2026-10-19T00:00:00Z',
    remember: remember);

Future<LocalFolderBootSnapshot> _boot(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  await LocalFolderBoot.preload();
  return LocalFolderBoot.snapshot!;
}

Future<String?> _sharedKey() async =>
    (await SharedPreferences.getInstance()).getString(kSharedStorageModeKey);

/// An app in folder mode whose folder is [fs] (remembered unless [stored]
/// is false).
Future<(LocalFolderController, MemoryFolderPlatform)> _folderApp(
  MemoryFolderFs fs, {
  bool remember = true,
  bool stored = true,
  MemoryFolderPlatform? platform,
  String app = 'editor',
}) async {
  final boot =
      await _boot({kSharedStorageModeKey: _record(remember: remember).encode()});
  final p = platform ?? MemoryFolderPlatform();
  if (stored) p.handleStore.records[kTestFolderId] = fs;
  final c = LocalFolderController.forTest(app: app, platform: p, boot: boot);
  addTearDown(c.dispose);
  return (c, p);
}

Future<void> _deliver() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mode and startup (2.8, 2.9)', () {
    test('folder mode starts in opening; a granted handle scans to active',
        () async {
      final fs = await newNotechondriaFolder();
      final (c, _) = await _folderApp(fs);
      expect(c.storageMode, StorageMode.folder);
      expect(c.state, LocalFolderState.opening);
      expect(c.zone, Zone.current);
      final states = <LocalFolderState>[];
      c.addListener(() => states.add(c.state));
      await c.open();
      expect(c.state, LocalFolderState.active);
      expect(states, containsAllInOrder([LocalFolderState.scanning, LocalFolderState.active]));
      expect(fs.exists(kIndexPath), isTrue);
      expect(c.unavailableDetail(isRead: true), isNull);
    });

    test('a usable index makes the controller active without a scan',
        () async {
      final fs = await newNotechondriaFolder();
      final (first, _) = await _folderApp(fs);
      await first.open();
      final (c, _) = await _folderApp(fs);
      final states = <LocalFolderState>[];
      c.addListener(() => states.add(c.state));
      await c.open();
      expect(states, isNot(contains(LocalFolderState.scanning)));
      expect(c.state, LocalFolderState.active);
      expect((await c.rescan())!.index.folderId, kTestFolderId);
    });

    test('the web check comes from the platform (T7(b))', () async {
      final boot = await _boot({kSharedStorageModeKey: _record().encode()});
      final c = LocalFolderController.forTest(
          app: 'editor', platform: MemoryFolderPlatform(isWeb: false), boot: boot);
      addTearDown(c.dispose);
      expect(c.storageMode, StorageMode.browserOrCloud);
    });

    test('a saved cloud session wins and open() does nothing', () async {
      final boot = await _boot({
        kSharedStorageModeKey: _record().encode(),
        'notechondria.editor.session': jsonEncode({'token': 'cloud'}),
      });
      final c = LocalFolderController.forTest(
          app: 'editor', platform: MemoryFolderPlatform(), boot: boot);
      addTearDown(c.dispose);
      expect(c.storageMode, StorageMode.browserOrCloud);
      expect(c.cloudSessionWins, isTrue);
      await c.open();
      expect(c.folder, isNull);
    });

    test('prompt: needsPermission, then Reconnect requests and opens',
        () async {
      final fs = await newNotechondriaFolder();
      fs.revoke();
      final (c, _) = await _folderApp(fs);
      await c.open();
      expect(c.state, LocalFolderState.needsPermission);
      expect(c.unavailableDetail(isRead: false),
          LocalFolderMessages.needsPermission('Notes'));
      await c.reconnect();
      expect(c.state, LocalFolderState.active);
    });

    test('denied: error with the 6.3 message', () async {
      final fs = await newNotechondriaFolder();
      fs.deny();
      fs.requestAnswer = FolderPermission.denied;
      final (c, _) = await _folderApp(fs);
      await c.open();
      expect(c.state, LocalFolderState.error);
      expect(c.failure!.message, LocalFolderMessages.permissionDenied('Notes'));
      expect(
          c.unavailableDetail(isRead: true),
          "Folder unavailable: Shared.LocalFolder/permission — the browser "
          "denies access to 'Notes'. Choose the folder again or switch to "
          'browser-local mode.');
    });

    test('a granted handle without manifest.json is an error (T7(g))',
        () async {
      final fs = await newNotechondriaFolder();
      fs.externalRemove(kManifestPath);
      final (c, _) = await _folderApp(fs);
      await c.open();
      expect(c.state, LocalFolderState.error);
      expect(c.failure!.message,
          LocalFolderMessages.manifestMissing('Notes', importPending: false));
      fs.externalEdit(kImportProgressPath, '{}');
      await c.open();
      expect(c.failure!.message,
          LocalFolderMessages.manifestMissing('Notes', importPending: true));
    });

    test('a moved folder: error with the not-found message', () async {
      final fs = await newNotechondriaFolder();
      fs.removeRoot();
      final (c, _) = await _folderApp(fs);
      await c.open();
      expect(c.state, LocalFolderState.error);
      expect(c.failure!.message, LocalFolderMessages.folderNotFound('Notes'));
    });

    test('a newer layout is refused with the 3.2 message', () async {
      final fs = await newNotechondriaFolder();
      final json = jsonDecode(fs.textOf(kManifestPath)!) as Map;
      fs.externalEdit(kManifestPath, jsonEncode({...json, 'layout_version': 2}));
      final (c, _) = await _folderApp(fs);
      await c.open();
      expect(c.failure!.message, LocalFolderMessages.layoutTooNew(2, 1));
    });

    test('revoked mid-session moves to needsPermission (6.3)', () async {
      final fs = await newNotechondriaFolder();
      final (c, _) = await _folderApp(fs);
      await c.open();
      c.reportFolderError(const FolderFsException(FolderErrorKind.notAllowed,
          operation: 'write', path: 'notes/a.md'));
      expect(c.state, LocalFolderState.needsPermission);
    });

    test('waitWhileOpening ends on a state change or at the time left',
        () async {
      final fs = await newNotechondriaFolder();
      final (c, _) = await _folderApp(fs);
      expect(await c.waitWhileOpening(const Duration(milliseconds: 10)), isFalse);
      final waiting = c.waitWhileOpening(const Duration(seconds: 5));
      await c.open();
      expect(await waiting, isTrue);
    });
  });

  group('no handle: needsPick and Choose again (2.9, T3)', () {
    test('session-only and missing-record wordings', () async {
      final fs = await newNotechondriaFolder();
      final (session, _) = await _folderApp(fs, remember: false, stored: false);
      await session.open();
      expect(session.state, LocalFolderState.needsPick);
      expect(session.unavailableDetail(isRead: true),
          LocalFolderMessages.needsPickSessionOnly('Notes'));
      final (missing, _) = await _folderApp(fs, remember: true, stored: false);
      await missing.open();
      expect(missing.unavailableDetail(isRead: true),
          LocalFolderMessages.needsPickMissingRecord('Notes'));
    });

    test('the picker is called first; cancel leaves the view as it was',
        () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs, remember: false, stored: false);
      await c.open();
      final outcome = await c.chooseAgain();
      expect(p.picker.calls, 1);
      expect(outcome, isA<PickCancelled>());
      expect(c.state, LocalFolderState.needsPick);
    });

    test('an empty folder is refused and left empty', () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs, remember: false, stored: false);
      await c.open();
      final empty = MemoryFolderFs(name: 'Empty');
      p.picker.willReturn(empty);
      final outcome = await c.chooseAgain();
      expect((outcome as PickRefused).message,
          LocalFolderMessages.pickNoManifest('Empty', 'Notes'));
      expect(outcome.canSwitch, isFalse);
      expect(empty.paths, isEmpty);
      expect(c.state, LocalFolderState.needsPick);
    });

    test('the same folder opens; with Remember on, the handle is stored',
        () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs, remember: true, stored: false);
      await c.open();
      p.picker.willReturn(fs.view());
      expect(await c.chooseAgain(), isA<PickOpened>());
      expect(c.state, LocalFolderState.active);
      expect(p.handleStore.records[kTestFolderId], isNotNull);
    });

    test('another folder_id is refused; Switch rewrites the key and tells tabs',
        () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs, remember: false, stored: false);
      final other = LocalFolderController.forTest(
          app: 'planner',
          platform: p.anotherTab(),
          boot: LocalFolderBoot.snapshot);
      addTearDown(other.dispose);
      await c.open();
      final picked = await newNotechondriaFolder(name: 'Other', folderId: _otherId);
      p.picker.willReturn(picked);
      final keyBefore = await _sharedKey();
      final outcome = await c.chooseAgain() as PickRefused;
      expect(outcome.canSwitch, isTrue);
      expect(outcome.message, contains("'Other' is a different Notechondria folder"));
      expect(await _sharedKey(), keyBefore);
      await c.switchToPicked();
      expect(StorageModeRecord.tryParse(await _sharedKey())!.folderId, _otherId);
      expect(c.state, LocalFolderState.active);
      expect(c.record!.folderName, 'Other');
      expect(p.hub.posted.last, {
        'op': 'switch',
        'folder_id': _otherId,
        'folder_name': 'Other',
      });
      await _deliver();
      expect(other.state, LocalFolderState.disconnected);
      expect(other.disconnectReason, DisconnectReason.switchedElsewhere);
      expect(other.unavailableDetail(isRead: true),
          LocalFolderMessages.switchedElsewhere('Notes', 'Other'));
    });

    test('a copy of a remembered folder asks before it is used (3.7)',
        () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs, remember: true, stored: true);
      final copy = fs.copy(name: 'Notes copy');
      p.picker.willReturn(copy);
      final outcome = await c.chooseAgain();
      expect(outcome, isA<PickLooksLikeCopy>());
      final refused = await c.giveCopyOwnIdentity() as PickRefused;
      expect(refused.canSwitch, isTrue);
      final copyId = (await readFolderManifest(copy))!.folderId;
      expect(copyId, isNot(kTestFolderId));
      expect((await readFolderManifest(fs))!.folderId, kTestFolderId);
    });

    test('a remembered folder without a grant: ask, then check it', () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs, remember: true, stored: true);
      fs.revoke();
      final copy = fs.copy(name: 'Notes copy')..grant();
      p.picker.willReturn(copy);
      expect(await c.chooseAgain(), isA<PickMayBeCopy>());
      expect(await c.checkRememberedCopy(), isA<PickLooksLikeCopy>());
      expect(await c.treatPickedAsMoved(), isA<PickOpened>());
      expect(c.folder, same(copy));
      expect(p.handleStore.records[kTestFolderId], same(copy));
    });
  });

  group('connect and disconnect (1.3, 2.10)', () {
    test('Connect an empty folder: README, then manifest, key, and message',
        () async {
      final boot = await _boot({});
      final p = MemoryFolderPlatform();
      final c = LocalFolderController.forTest(app: 'editor', platform: p, boot: boot);
      final listener = LocalFolderController.forTest(
          app: 'portal', platform: p.anotherTab(), boot: boot);
      addTearDown(c.dispose);
      addTearDown(listener.dispose);
      expect(c.storageMode, StorageMode.browserOrCloud);
      final folder = MemoryFolderFs(name: 'Fresh');
      p.picker.willReturn(folder);
      final pick = (await c.pickForConnect())!;
      expect(pick.isEmpty, isTrue);
      await c.connectPicked(pick, remember: false);
      expect(c.storageMode, StorageMode.folder);
      expect(c.state, LocalFolderState.active);
      expect((await folder.stat(kReadmePath))!.lastModified,
          lessThan((await folder.stat(kManifestPath))!.lastModified));
      final record = StorageModeRecord.tryParse(await _sharedKey())!;
      expect(record.folderName, 'Fresh');
      expect(record.remember, isFalse);
      expect(record.connectedBy, 'editor');
      expect(p.handleStore.records, isEmpty);
      await _deliver();
      expect(listener.connectedElsewhere, 'Fresh');
    });

    test('a non-empty folder without a manifest needs the count confirmed',
        () async {
      final boot = await _boot({});
      final p = MemoryFolderPlatform();
      final c = LocalFolderController.forTest(app: 'editor', platform: p, boot: boot);
      addTearDown(c.dispose);
      final folder = MemoryFolderFs(name: 'Docs');
      await folder.writeText('notes/hand.md', '# Hand\n');
      await folder.writeText(kReadmePath, 'my readme');
      p.picker.willReturn(folder);
      final pick = (await c.pickForConnect())!;
      expect(pick.entryCount, 2);
      await expectLater(
          c.connectPicked(pick, remember: true), throwsA(isA<StateError>()));
      expect(folder.exists(kManifestPath), isFalse);
      await c.connectPicked(pick, remember: true, confirmedEntryCount: true);
      expect(folder.textOf(kReadmePath), 'my readme');
      expect(folder.exists('notes/hand.meta.json'), isTrue);
      expect(p.handleStore.records.values.single, same(folder));
    });

    test('Disconnect runs its four steps in order and tells other tabs',
        () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs);
      final other = LocalFolderController.forTest(
          app: 'planner', platform: p.anotherTab(), boot: LocalFolderBoot.snapshot);
      addTearDown(other.dispose);
      await c.open();
      final steps = <String>[];
      await c.disconnect(clearSession: () async {
        steps.add('clear:${c.state.name}:${c.storageMode.name}');
        steps.add('key:${await _sharedKey() != null}');
        steps.add('posted:${p.hub.posted.length}');
      });
      expect(steps, ['clear:disconnected:folder', 'key:true', 'posted:0']);
      expect(c.storageMode, StorageMode.browserOrCloud);
      expect(await _sharedKey(), isNull);
      expect(p.handleStore.records, isEmpty);
      expect(p.hub.posted.single['op'], 'disconnect');
      expect(c.unavailableDetail(isRead: false),
          LocalFolderMessages.disconnectedHereWrite('Notes'));
      expect(c.unavailableDetail(isRead: true),
          LocalFolderMessages.disconnectedHereRead('Notes'));
      await _deliver();
      expect(other.state, LocalFolderState.disconnected);
      expect(other.unavailableDetail(isRead: true),
          LocalFolderMessages.disconnectedElsewhere('Notes'));
    });

    test('a dropped change message changes nothing in other tabs', () async {
      final fs = await newNotechondriaFolder();
      final (c, p) = await _folderApp(fs);
      final other = LocalFolderController.forTest(
          app: 'planner', platform: p.anotherTab(), boot: LocalFolderBoot.snapshot);
      addTearDown(other.dispose);
      p.hub.dropAll = true;
      await c.disconnect();
      await _deliver();
      expect(other.state, LocalFolderState.opening);
    });
  });
}
