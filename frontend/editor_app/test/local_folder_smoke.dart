// Local folder smoke checks (design testing.md 8.5). Client level (Phase 1):
// the editor's real HttpNotechondriaClient over a LocalFolderController's
// StorageModeClient and MemoryFolderPlatform, inside http.runWithClient
// with a recorder, and no app wiring. App level (Phase 2):
// NotechondriaApp(localFolder:) with no client, so the production
// default-client line runs and its inner http.Client() is the zone's
// failing recorder.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/notechondria_shared.dart';
// The probe inputs of an unqualified browser (no barrel export).
// ignore: implementation_imports
import 'package:notechondria_shared/src/local_folder/qualification.dart'
    show LocalFolderProbeInputs;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:editor_app/main.dart' as app;

const String _base = 'https://notechondria.trance-0.com/api/v1';
const String _token = 'local-folder';

/// Stands in for every `http.Client()` (8.5): records each request.
class _Recorder extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
        http.ByteStream.fromBytes(utf8.encode(jsonEncode({
          'service': 'notechondria-backend',
          'api_version': 'v1',
          'version': '9.9.9',
        }))),
        200,
        headers: {'content-type': 'application/json'});
  }
}

/// A dart:io client created outside the zone fails the test (8.5).
class _NoDartIo extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('dart:io HttpClient created during a folder smoke test');
}

/// A browser-local controller that connects an empty folder, as the
/// sign-in option does.
Future<(LocalFolderController, MemoryFolderFs)> _connected() async {
  SharedPreferences.setMockInitialValues({});
  await LocalFolderBoot.preload();
  final platform = MemoryFolderPlatform();
  final folder = MemoryFolderFs(name: 'Smoke');
  platform.picker.willReturn(folder);
  final c = LocalFolderController.forTest(
      app: 'editor', platform: platform, boot: LocalFolderBoot.snapshot);
  addTearDown(c.dispose);
  final pick = await c.pickForConnect();
  await c.connectPicked(pick!, remember: false);
  expect(c.state, LocalFolderState.active);
  return (c, folder);
}

Future<String> _error(Future<Object?> call) async {
  try {
    await call;
  } catch (e) {
    return '$e';
  }
  fail('expected the request to fail');
}

void registerLocalFolderSmokeTests() {
  _registerAppLevelTests();
  group('local folder, client level (Phase 1)', () {
    HttpOverrides? previous;
    setUp(() {
      previous = HttpOverrides.current;
      HttpOverrides.global = _NoDartIo();
    });
    tearDown(() => HttpOverrides.global = previous);

    test('notes live in the folder and nothing reaches the network', () async {
      final recorder = _Recorder();
      await http.runWithClient(() async {
        final (c, fs) = await _connected();
        final client = app.HttpNotechondriaClient(
            httpClient: c.httpClient, initialBaseUrl: _base);
        final note = await client
            .createNote(_token, {'title': 'Smoke', 'content': '# Smoke\n\nBody'});
        final hex = '${note['uuid']}'.replaceAll('-', '');
        expect(fs.exists('notes/$hex.md'), isTrue);
        expect(fs.exists('notes/$hex.meta.json'), isTrue);
        final id = note['id'] as int;
        await client.updateNote(_token, id, {'content': 'Edited'});
        expect(fs.textOf('notes/$hex.md'), contains('Edited'));
        // Multipart reaches the transport (the 8 `_httpClient.send` sites)
        // and the attachment lands in the folder (Phase 2, 8.5 editor row).
        final upload = await client.uploadNoteAttachment(_token, id,
            XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'a.png'));
        expect('${upload['url']}', startsWith('nc-folder:///assets/notes/$hex/'));
        expect(fs.paths.any((p) => p.startsWith('assets/notes/$hex/')), isTrue);
        await client.deleteNote(_token, id);
        expect(fs.exists('trash/notes/$hex.md'), isTrue);
        await client.restoreDeletedNote(_token, id);
        await client.deleteNote(_token, id);
        expect((await client.emptyDeletedNotes(_token))['count'], 1);
        expect(fs.paths.where((p) => p.contains(hex)), isEmpty);
        final handshake = await client.verifyHandshake(_base);
        expect(handshake.ok, isTrue);
        final ping = await pingBackend(_base, client: c.httpClient);
        expect(ping.ok, isTrue);
      }, () => recorder);
      expect(recorder.requests, isEmpty);
    });

    test('revoked mid-session: 503 with the needsPermission detail, no request',
        () async {
      final recorder = _Recorder();
      await http.runWithClient(() async {
        final (c, fs) = await _connected();
        final client = app.HttpNotechondriaClient(
            httpClient: c.httpClient, initialBaseUrl: _base);
        final note = await client.createNote(_token, {'title': 'Draft'});
        fs.revoke();
        final save = await _error(
            client.updateNote(_token, note['id'] as int, {'content': 'x'}));
        expect(save, contains(LocalFolderMessages.needsPermission('Smoke')));
        expect(c.state, LocalFolderState.needsPermission);
        final list = await _error(client.listNotes(token: _token));
        expect(list, contains('Folder access lost: '));
        expect(list.toLowerCase(), isNot(contains('session rejected:')));
        expect((await pingBackend(_base, client: c.httpClient)).ok, isTrue);
      }, () => recorder);
      expect(recorder.requests, isEmpty);
    });

    test('Check for updates is the one request that leaves the page',
        () async {
      final recorder = _Recorder();
      await http.runWithClient(() async {
        final (c, _) = await _connected();
        final client = app.HttpNotechondriaClient(
            httpClient: c.httpClient, initialBaseUrl: _base);
        final check = await checkCloudVersion(client: c.httpClient, apiBaseUrl: _base);
        expect(check.ok, isTrue);
        await runCloudVersionCheck(_base, () async {
          await client.createNote(_token, {'title': 'inside the zone'});
        });
      }, () => recorder);
      expect(recorder.requests, hasLength(1));
      expect(recorder.requests.single.url.toString(), '$_base/handshake/');
      expect(recorder.requests.single.headers.containsKey('Authorization'), isFalse);
    });
  });
}

// --- App level (Phase 2) ---

/// The zone client of the folder checks: records every request and fails
/// it, so a request that escapes the folder fails the app call too (8.5).
class _FailingRecorder extends http.BaseClient {
  final List<http.BaseRequest> requests = [];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    throw http.ClientException(
        'network request in a folder smoke test', request.url);
  }
}

/// First-run overlays (tour, what's new) would cover the shell.
final Map<String, Object> _seenFirstRun = {
  'notechondria.editor.local_stats':
      jsonEncode({'onboarding_seen': true, 'install_hint_dismissed': true}),
};

typedef _Seeded = ({MemoryFolderPlatform tab, MemoryFolderFs fs, String uuid});

/// An earlier page load connected the folder 'Smoke' and saved one note;
/// this page load has a fresh tab of the same origin (shared handle store
/// and locks) and a preloaded snapshot. Runs with real async.
Future<_Seeded> _seedFolder(
    {required bool remember, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({..._seenFirstRun, ...prefs});
  await LocalFolderBoot.preload();
  final platform = MemoryFolderPlatform();
  final fs = MemoryFolderFs(name: 'Smoke');
  platform.picker.willReturn(fs);
  final seed = LocalFolderController.forTest(
      app: 'editor', platform: platform, boot: LocalFolderBoot.snapshot);
  final pick = await seed.pickForConnect();
  await seed.connectPicked(pick!, remember: remember);
  final client = app.HttpNotechondriaClient(
      httpClient: seed.httpClient, initialBaseUrl: _base);
  final note = await client.createNote(
      _token, {'title': 'Folder note', 'content': 'Body from the folder'});
  await seed.flushIndex();
  final folderId = seed.record!.folderId;
  seed.dispose();
  final stored = await SharedPreferences.getInstance();
  await stored.setString('notechondria.editor.folder_pushed', folderId);
  await LocalFolderBoot.preload();
  return (tab: platform.anotherTab(), fs: fs, uuid: '${note['uuid']}');
}

Future<void> _pumpSeconds(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Mounts the editor with [folder] and no client (the production
/// default-client line, 2.7) on a tall compact surface.
Future<void> _pumpApp(WidgetTester tester, LocalFolderController folder,
    {int initialIndex = 1}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app.NotechondriaApp(
    localFolder: folder,
    initialIndex: initialIndex,
    title: 'Notechondria Editor',
    visibleIndices: const <int>[1, 4],
  ));
  await _pumpSeconds(tester, 3);
}

/// Unmounts the app and lets the remaining timers (splash, index flush,
/// version probe) run out on the fake clock.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpSeconds(tester, 13);
}

LocalFolderController _appController(MemoryFolderPlatform tab) {
  final c = LocalFolderController.forTest(
      app: 'editor', platform: tab, boot: LocalFolderBoot.snapshot);
  addTearDown(c.dispose);
  return c;
}

Future<List<String>> _logs() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('notechondria.editor.local_logs') ?? '[]';
  return (jsonDecode(raw) as List<dynamic>).cast<String>();
}

/// Every folder check: the zone client is the failing recorder and a
/// dart:io client created outside the zone fails too (8.5).
Future<_FailingRecorder> _inFolderZone(Future<void> Function() body) async {
  final recorder = _FailingRecorder();
  final previous = HttpOverrides.current;
  HttpOverrides.global = _NoDartIo();
  try {
    await http.runWithClient(body, () => recorder);
  } finally {
    HttpOverrides.global = previous;
  }
  return recorder;
}

/// A cloud backend for the precedence check: the saved session validates.
Future<http.Response> _cloudBackend(http.Request request) async {
  final path = request.url.path;
  Object body = <String, Object?>{};
  if (path.endsWith('/handshake/')) {
    body = {
      'service': 'notechondria-backend',
      'api_version': 'v1',
      'version': '0.1.21',
      'min_frontend_version': '',
    };
  } else if (path.endsWith('/auth/session/')) {
    body = {
      'authenticated': true,
      'token': 'cloud-token',
      'user': {'username': 'alice', 'email': 'alice@example.com'},
    };
  } else if (path.endsWith('/courses/') ||
      path.endsWith('/activity/') ||
      path.endsWith('/notes/deleted/')) {
    body = <Object?>[];
  } else if (path.endsWith('/notes/')) {
    body = {'results': <Object?>[], 'has_more': false};
  }
  return http.Response(jsonEncode(body), 200,
      headers: {'content-type': 'application/json'});
}

void _registerAppLevelTests() {
  group('local folder, app level (Phase 2)', () {
    testWidgets(
        'folder mode: startup, the note list, and the settings card send '
        'zero network requests', (tester) async {
      final seeded =
          (await tester.runAsync(() => _seedFolder(remember: true)))!;
      late LocalFolderController c;
      final recorder = await _inFolderZone(() async {
        c = _appController(seeded.tab);
        await _pumpApp(tester, c);
        expect(c.storageMode, StorageMode.folder);
        expect(c.state, LocalFolderState.active);
        expect(find.text('Folder note'), findsWidgets);
        await _unmount(tester);
        await _pumpApp(tester, c, initialIndex: 4);
        expect(find.text('Local folder'), findsOneWidget);
        expect(find.text('Disconnect folder'), findsOneWidget);
        expect(find.byType(AuthHub), findsNothing);
        await _unmount(tester);
      });
      expect(recorder.requests, isEmpty,
          reason: recorder.requests.map((r) => '${r.url}').join('\n'));
      final logs = await _logs();
      expect(logs.any((l) => l.contains('Folder opened: Editor.Startup/local_folder')),
          isTrue);
      expect(logs.any((l) => l.contains('Cloud data not loaded')), isFalse);
    });

    testWidgets(
        'revoked mid-session: the reconnect view replaces the shell, '
        'Reconnect resumes, and nothing reaches the network', (tester) async {
      final seeded =
          (await tester.runAsync(() => _seedFolder(remember: true)))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        await _pumpApp(tester, c, initialIndex: 4);
        expect(c.state, LocalFolderState.active);
        seeded.fs.revoke();
        await tester.tap(find.text('Rescan folder'));
        await _pumpSeconds(tester, 2);
        expect(c.state, LocalFolderState.needsPermission);
        expect(find.text("Reconnect 'Smoke'"), findsOneWidget);
        expect(find.text(LocalFolderMessages.needsPermission('Smoke')),
            findsOneWidget);
        await tester.tap(find.text("Reconnect 'Smoke'"));
        await _pumpSeconds(tester, 3);
        expect(c.state, LocalFolderState.active);
        expect(find.text('Disconnect folder'), findsOneWidget);
        await _unmount(tester);
      });
      expect(recorder.requests, isEmpty,
          reason: recorder.requests.map((r) => '${r.url}').join('\n'));
    });

    testWidgets(
        'a saved cloud session wins over the connected folder, with the '
        'notice', (tester) async {
      final record = const StorageModeRecord(
        folderId: '11111111-2222-4333-8444-555555555555',
        folderName: 'Smoke',
        connectedBy: 'editor',
        connectedAt: '2026-10-19T00:00:00Z',
        remember: false,
      ).encode();
      final session = jsonEncode({
        'token': 'cloud-token',
        'user': {'username': 'alice'},
      });
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          ..._seenFirstRun,
          kSharedStorageModeKey: record,
          'notechondria.editor.session': session,
        });
        await LocalFolderBoot.preload();
      });
      var sessionChecks = 0;
      await http.runWithClient(() async {
        final c = _appController(MemoryFolderPlatform());
        expect(c.storageMode, StorageMode.browserOrCloud);
        expect(c.cloudSessionWins, isTrue);
        await _pumpApp(tester, c, initialIndex: 4);
        expect(find.textContaining('Local folder not used: '), findsWidgets);
        await _unmount(tester);
      }, () => MockClient((request) {
            if (request.url.path.endsWith('/auth/session/')) sessionChecks++;
            return _cloudBackend(request);
          }));
      expect(sessionChecks, greaterThan(0));
      final prefs = await SharedPreferences.getInstance();
      final kept = jsonDecode(prefs.getString('notechondria.editor.session')!);
      expect((kept as Map)['token'], 'cloud-token');
      expect(prefs.getString(kSharedStorageModeKey), record);
      final logs = await _logs();
      expect(
          logs.any((l) => l.contains(LocalFolderMessages.cloudSessionWins(
              'Editor', 'alice', 'Smoke'))),
          isTrue);
    });

    testWidgets(
        'Disconnect never signs out of the cloud and sends no folder token',
        (tester) async {
      final portalSession = jsonEncode({'token': 'portal-token'});
      final seeded = (await tester.runAsync(() => _seedFolder(
          remember: true,
          prefs: {'notechondria.portal.session': portalSession})))!;
      late LocalFolderController c;
      final recorder = await _inFolderZone(() async {
        c = _appController(seeded.tab);
        await _pumpApp(tester, c, initialIndex: 4);
        expect(c.state, LocalFolderState.active);
        await tester.tap(find.text('Disconnect folder'));
        await _pumpSeconds(tester, 3);
        expect(c.storageMode, StorageMode.browserOrCloud);
        expect(find.byType(AuthHub), findsOneWidget);
        await _unmount(tester);
      });
      // After the switch the signed-out app loads public data again; no
      // request carries a token and none is a logout.
      for (final r in recorder.requests) {
        expect(r.headers.containsKey('Authorization'), isFalse, reason: '${r.url}');
        expect(r.url.path, isNot(contains('auth/logout')));
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notechondria.portal.session'), portalSession);
      expect(prefs.containsKey(kSharedStorageModeKey), isFalse);
      final logs = await _logs();
      expect(logs.any((l) => l.contains('auth/logout')), isFalse);
      expect(logs.any((l) => l.contains('Editor.Auth/logout')), isFalse);
      expect(
          logs.any((l) =>
              l.contains('Folder disconnected: Shared.LocalFolder/disconnect')),
          isTrue);
    });

    for (final pending in ['needsPick', 'needsPermission']) {
      testWidgets(
          'a cold #/notes/<uuid> in $pending opens the note after the '
          'reconnect view, with no sign-in prompt (T2)', (tester) async {
        final seeded = (await tester.runAsync(
            () => _seedFolder(remember: pending == 'needsPermission')))!;
        if (pending == 'needsPermission') {
          seeded.fs.revoke();
        } else {
          seeded.tab.picker.willReturn(seeded.fs);
        }
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        app.bootInitialFragment = '/notes/${seeded.uuid}';
        addTearDown(() => app.bootInitialFragment = '');
        final recorder = await _inFolderZone(() async {
          final c = _appController(seeded.tab);
          await _pumpApp(tester, c);
          final button = pending == 'needsPick'
              ? "Choose 'Smoke' again"
              : "Reconnect 'Smoke'";
          expect(find.text(button), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
          await tester.tap(find.text(button));
          await _pumpSeconds(tester, 3);
          expect(c.state, LocalFolderState.active);
          expect(
              find.descendant(
                  of: find.byType(Dialog),
                  matching: find.textContaining('Folder note')),
              findsWidgets);
          expect(find.text(l10n.privateNoteTitle), findsNothing);
          await _unmount(tester);
        });
        expect(recorder.requests, isEmpty,
            reason: recorder.requests.map((r) => '${r.url}').join('\n'));
      });
    }

    testWidgets(
        'the sign-in option is enabled when qualified and disabled with the '
        'gap message when not', (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(_seenFirstRun);
        await LocalFolderBoot.preload();
      });
      const firefox = LocalFolderProbeInputs(
          hasDirectoryPicker: false,
          isSecureContext: true,
          hasPermissionApi: false,
          hasDirectoryIteration: true,
          hasWebLocks: true,
          userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Firefox/130.0');
      final backend = MockClient(_cloudBackend);
      await http.runWithClient(() async {
        for (final qualified in [true, false]) {
          final c = _appController(qualified
              ? MemoryFolderPlatform()
              : MemoryFolderPlatform(probeInputs: firefox));
          await _pumpApp(tester, c, initialIndex: 4);
          final option = find.widgetWithText(
              OutlinedButton, 'Use a local folder (no account)');
          expect(option, findsOneWidget);
          final button = tester.widget<OutlinedButton>(option);
          expect(button.onPressed != null, qualified);
          expect(
              find.textContaining(
                  localFolderGapMessage(LocalFolderGap.noDirectoryPicker)),
              qualified ? findsNothing : findsOneWidget);
          await _unmount(tester);
        }
      }, () => backend);
    });
  });
}
