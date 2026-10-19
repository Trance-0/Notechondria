import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/handle_store.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _folderKey =
    '{"mode":"folder","folder_id":"f1","folder_name":"Notes","connected_by":"editor","connected_at":"2026-10-19T00:00:00Z","remember":true}';
final String _session = jsonEncode({'token': 't', 'profile': {}});

Future<LocalFolderBootSnapshot> _boot(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  LocalFolderBoot.snapshot = null;
  await LocalFolderBoot.preload();
  return LocalFolderBoot.snapshot!;
}

StorageModeDecision _decide(String app, LocalFolderBootSnapshot boot,
        {bool isWeb = true}) =>
    decideStorageMode(app: app, isWeb: isWeb, snapshot: boot);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decideStorageMode (2.8)', () {
    test('folder for every app when the key is set and no session is saved',
        () async {
      final boot = await _boot({kSharedStorageModeKey: _folderKey});
      for (final app in ['editor', 'planner', 'portal']) {
        final d = _decide(app, boot);
        expect(d.mode, StorageMode.folder, reason: app);
        expect(d.record!.folderId, 'f1');
        expect(d.record!.remember, isTrue);
        expect(d.cloudSessionWins, isFalse);
      }
    });

    test('no key, or a native build, or no snapshot: browserOrCloud',
        () async {
      final none = await _boot({});
      expect(_decide('editor', none).mode, StorageMode.browserOrCloud);
      final withKey = await _boot({kSharedStorageModeKey: _folderKey});
      expect(_decide('editor', withKey, isWeb: false).mode,
          StorageMode.browserOrCloud);
      expect(
          decideStorageMode(app: 'editor', isWeb: true, snapshot: null).mode,
          StorageMode.browserOrCloud);
    });

    test('a saved cloud session wins (2.10 rule 2), per app', () async {
      final boot = await _boot({
        kSharedStorageModeKey: _folderKey,
        'notechondria.portal.session': _session,
      });
      final portal = _decide('portal', boot);
      expect(portal.mode, StorageMode.browserOrCloud);
      expect(portal.cloudSessionWins, isTrue);
      expect(portal.record!.folderName, 'Notes');
      expect(_decide('editor', boot).mode, StorageMode.folder);
      expect(_decide('planner', boot).mode, StorageMode.folder);
    });

    test('the editor reads the legacy session key when its own is absent',
        () async {
      final legacy = await _boot({
        kSharedStorageModeKey: _folderKey,
        'notechondria.session': _session,
      });
      expect(_decide('editor', legacy).mode, StorageMode.browserOrCloud);
      expect(_decide('portal', legacy).mode, StorageMode.folder,
          reason: 'the portal has no legacy session key');
    });

    test('an empty namespaced editor key hides the legacy session', () async {
      final boot = await _boot({
        kSharedStorageModeKey: _folderKey,
        'notechondria.editor.session': '',
        'notechondria.session': _session,
      });
      expect(_decide('editor', boot).mode, StorageMode.folder);
    });

    test('a session without a token does not count', () async {
      final boot = await _boot({
        kSharedStorageModeKey: _folderKey,
        'notechondria.editor.session': jsonEncode({'token': null}),
        'notechondria.portal.session': 'not json',
      });
      expect(_decide('editor', boot).mode, StorageMode.folder);
      expect(_decide('portal', boot).mode, StorageMode.folder);
    });

    test('one session-key table, keyed by app id (T7(a))', () {
      expect(kAppSessionKeys.keys, unorderedEquals(['editor', 'planner', 'portal']));
      expect(kAppSessionKeys['planner'], isNull);
      expect(kAppSessionKeys['editor']!.legacyKey, 'notechondria.session');
    });

    test('a key that is not folder mode, or broken, is ignored', () async {
      for (final raw in [
        '{"mode":"cloud","folder_id":"f1"}',
        '{"mode":"folder"}',
        'not json',
        '[]',
      ]) {
        final boot = await _boot({kSharedStorageModeKey: raw});
        expect(_decide('editor', boot).mode, StorageMode.browserOrCloud,
            reason: raw);
      }
    });
  });

  group('StorageModeRecord', () {
    test('round-trips with the remember flag (T3)', () {
      const record = StorageModeRecord(
          folderId: 'f1',
          folderName: 'Notes',
          connectedBy: 'planner',
          connectedAt: '2026-10-19T00:00:00Z',
          remember: false);
      final back = StorageModeRecord.tryParse(record.encode())!;
      expect(back.encode(), record.encode());
      expect(jsonDecode(record.encode())['remember'], isFalse);
    });

    test('a record written before T3 reads as remember off', () {
      final back = StorageModeRecord.tryParse(
          '{"mode":"folder","folder_id":"f1","folder_name":"N"}')!;
      expect(back.remember, isFalse);
    });
  });

  group('preload', () {
    test('a failing preload logs the 2.8 line and starts browserOrCloud', () {
      LocalFolderBoot.snapshot =
          const LocalFolderBootSnapshot.empty(error: 'QuotaExceededError');
      expect(
          LocalFolderBoot.preloadFailureMessage('planner'),
          'Local folder not checked: Planner.Startup/local_folder — browser '
          'storage could not be read (QuotaExceededError); starting in '
          'browser-local or cloud mode.');
      expect(_decide('planner', LocalFolderBoot.snapshot!).mode,
          StorageMode.browserOrCloud);
    });
  });

  group('remember default per origin (T3)', () {
    test('off on github.io, the loopback preview, and any self-host', () {
      for (final origin in [
        'https://trance-0.github.io/Notechondria/editor/',
        'http://127.0.0.1:9068/editor/',
        'http://localhost:8080/',
        'https://notes.example.org/editor/',
      ]) {
        expect(rememberDefaultForOrigin(Uri.parse(origin)), isFalse,
            reason: origin);
      }
    });

    test('the shared-origin notice applies only to *.github.io', () {
      expect(needsSharedOriginNotice(Uri.parse('https://trance-0.github.io/x')),
          isTrue);
      expect(needsSharedOriginNotice(Uri.parse('http://127.0.0.1:9068/')),
          isFalse);
      expect(classifyLocalFolderOrigin(Uri.parse('http://[::1]:9068/')),
          LocalFolderOriginKind.loopback);
      expect(classifyLocalFolderOrigin(Uri.parse('https://example.org')),
          LocalFolderOriginKind.other);
    });
  });
}
