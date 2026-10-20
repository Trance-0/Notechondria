// Local folder smoke checks for the portal (design testing.md 8.5, Phase 3).
// Each check boots NotechondriaApp(localFolder:) with no client, so the
// production default-client line runs and its inner http.Client() is the
// zone's failing recorder; a dart:io client created outside the zone fails
// too (HttpOverrides).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
import 'package:portal_app/main.dart' as app;

const String _base = 'https://notechondria.trance-0.com/api/v1';
const String _token = 'local-folder';

/// A 1x1 transparent PNG.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

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

/// A dart:io client created outside the zone fails the test (8.5).
class _NoDartIo extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('dart:io HttpClient created during a folder smoke test');
}

/// First-run overlays (tour, what's new) would cover the shell.
final Map<String, Object> _seenFirstRun = {
  'notechondria.portal.local_stats':
      jsonEncode({'onboarding_seen': true, 'install_hint_dismissed': true}),
};

typedef _Seeded = ({
  MemoryFolderPlatform tab,
  MemoryFolderFs fs,
  String uuid,
  String imageUrl,
});

/// An earlier page load connected the folder 'Smoke' and saved one note
/// whose body shows a folder image; this page load has a fresh tab of the
/// same origin (shared handle store and locks) and a preloaded snapshot.
/// Runs with real async.
Future<_Seeded> _seedFolder(
    {required bool remember,
    Map<String, Object> prefs = const {},
    bool pushed = true}) async {
  SharedPreferences.setMockInitialValues({..._seenFirstRun, ...prefs});
  await LocalFolderBoot.preload();
  final platform = MemoryFolderPlatform();
  final fs = MemoryFolderFs(name: 'Smoke');
  platform.picker.willReturn(fs);
  final seed = LocalFolderController.forTest(
      app: 'portal', platform: platform, boot: LocalFolderBoot.snapshot);
  final pick = await seed.pickForConnect();
  await seed.connectPicked(pick!, remember: remember);
  final client = app.HttpNotechondriaClient(
      httpClient: seed.httpClient, initialBaseUrl: _base);
  final note = await client.createNote(_token, {
    'title': 'Folder note',
    'content': 'Body from the folder',
  });
  final hex = '${note['uuid']}'.replaceAll('-', '');
  final imagePath = 'assets/notes/$hex/attachments/a.png';
  await fs.writeBytes(imagePath, _png);
  final imageUrl = 'nc-folder:///$imagePath';
  await client.updateNote(_token, note['id'] as int, {
    'content': 'Body from the folder\n\n![x]($imageUrl)\n',
  });
  await seed.flushIndex();
  final folderId = seed.record!.folderId;
  seed.dispose();
  if (pushed) {
    final stored = await SharedPreferences.getInstance();
    await stored.setString('notechondria.portal.folder_pushed', folderId);
  }
  await LocalFolderBoot.preload();
  return (
    tab: platform.anotherTab(),
    fs: fs,
    uuid: '${note['uuid']}',
    imageUrl: imageUrl,
  );
}

Future<void> _pumpSeconds(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Mounts the portal with [folder] and no client (the production
/// default-client line, 2.7) on a tall compact surface. [route] is the
/// cold-start URL fragment (`#/note/<uuid>`, `#/notes`).
Future<void> _pumpApp(WidgetTester tester, LocalFolderController folder,
    {int initialIndex = 0, String? route}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dispatcher = tester.binding.platformDispatcher;
  if (route != null) {
    dispatcher.defaultRouteNameTestValue = route;
    addTearDown(dispatcher.clearDefaultRouteNameTestValue);
  } else {
    dispatcher.clearDefaultRouteNameTestValue();
  }
  await tester.pumpWidget(app.NotechondriaApp(
    localFolder: folder,
    initialIndex: initialIndex,
    title: 'Notechondria Portal',
    visibleIndices: const <int>[0, 1, 2, 3, 4],
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
      app: 'portal', platform: tab, boot: LocalFolderBoot.snapshot);
  addTearDown(c.dispose);
  return c;
}

Future<List<String>> _logs() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('notechondria.portal.local_logs') ?? '[]';
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

String _urls(_FailingRecorder r) => r.requests.map((q) => '${q.url}').join('\n');

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
      path.endsWith('/planner-events/') ||
      path.endsWith('/calendar-feeds/') ||
      path.endsWith('/notes/deleted/')) {
    body = <Object?>[];
  } else if (path.endsWith('/notes/')) {
    body = {'results': <Object?>[], 'has_more': false};
  }
  return http.Response(jsonEncode(body), 200,
      headers: {'content-type': 'application/json'});
}

void registerLocalFolderSmokeTests() {
  group('local folder, portal (Phase 3)', () {
    testWidgets(
        'folder mode: a cold #/notes start and the settings card send zero '
        'network requests', (tester) async {
      final seeded =
          (await tester.runAsync(() => _seedFolder(remember: true)))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        await _pumpApp(tester, c, route: '/notes');
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
      expect(recorder.requests, isEmpty, reason: _urls(recorder));
      final logs = await _logs();
      expect(
          logs.any(
              (l) => l.contains('Folder opened: Portal.Startup/local_folder')),
          isTrue);
      expect(logs.any((l) => l.contains('Cloud data not loaded')), isFalse);
    });

    testWidgets(
        'a cold #/note/<uuid> renders the folder note and its nc-folder image '
        'with zero requests', (tester) async {
      final seeded =
          (await tester.runAsync(() => _seedFolder(remember: true)))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        await _pumpApp(tester, c, route: '/note/${seeded.uuid}');
        expect(c.state, LocalFolderState.active);
        expect(find.text('Folder note'), findsWidgets);
        final image = find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is FolderImage &&
            (w.image as FolderImage).url == seeded.imageUrl);
        expect(image, findsOneWidget);
        // The provider reads the bytes through the app's controller.
        final provider = tester.widget<Image>(image).image;
        Object? error;
        ImageInfo? info;
        await tester.runAsync(() async {
          final done = Completer<void>();
          provider.resolve(ImageConfiguration.empty).addListener(
              ImageStreamListener((i, _) {
            info = i;
            if (!done.isCompleted) done.complete();
          }, onError: (e, _) {
            error = e;
            if (!done.isCompleted) done.complete();
          }));
          await done.future.timeout(const Duration(seconds: 5));
        });
        expect(error, isNull);
        expect(info!.image.width, 1);
        // Decoding needs real async; then the frame shows the image.
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
        expect(find.textContaining('failed to load'), findsNothing);
        await _unmount(tester);
      });
      expect(recorder.requests, isEmpty, reason: _urls(recorder));
    });

    testWidgets(
        'a cold #/note/<uuid> with no remembered handle shows the reconnect '
        'view; after Choose again the note renders, and popping the route '
        'shows the shell in the folder session (T1)', (tester) async {
      final seeded =
          (await tester.runAsync(() => _seedFolder(remember: false)))!;
      seeded.tab.picker.willReturn(seeded.fs);
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        await _pumpApp(tester, c,
            initialIndex: 4, route: '/note/${seeded.uuid}');
        expect(c.state, LocalFolderState.needsPick);
        expect(find.text("Choose 'Smoke' again"), findsOneWidget);
        expect(find.textContaining('may be private'), findsNothing);
        await tester.tap(find.text("Choose 'Smoke' again"));
        await _pumpSeconds(tester, 3);
        expect(c.state, LocalFolderState.active);
        expect(find.text('Folder note'), findsWidgets);
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await _pumpSeconds(tester, 2);
        expect(find.text('Folder note'), findsNothing);
        expect(find.text('Disconnect folder'), findsOneWidget);
        expect(find.byType(AuthHub), findsNothing);
        await _unmount(tester);
      });
      expect(recorder.requests, isEmpty, reason: _urls(recorder));
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
      expect(recorder.requests, isEmpty, reason: _urls(recorder));
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
          'notechondria.portal.session': session,
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
      final kept = jsonDecode(prefs.getString('notechondria.portal.session')!);
      expect((kept as Map)['token'], 'cloud-token');
      expect(prefs.getString(kSharedStorageModeKey), record);
      final logs = await _logs();
      expect(
          logs.any((l) => l.contains(LocalFolderMessages.cloudSessionWins(
              'Portal', 'alice', 'Smoke'))),
          isTrue);
    });

    testWidgets(
        'Disconnect never signs out of the cloud and sends no folder token',
        (tester) async {
      final editorSession = jsonEncode({'token': 'editor-token'});
      final seeded = (await tester.runAsync(() => _seedFolder(
          remember: true,
          prefs: {'notechondria.editor.session': editorSession})))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
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
        expect(r.headers.containsKey('Authorization'), isFalse,
            reason: '${r.url}');
        expect(r.url.path, isNot(contains('auth/logout')));
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notechondria.editor.session'), editorSession);
      expect(prefs.containsKey('notechondria.portal.session'), isFalse);
      expect(prefs.containsKey(kSharedStorageModeKey), isFalse);
      final logs = await _logs();
      expect(logs.any((l) => l.contains('auth/logout')), isFalse);
      expect(logs.any((l) => l.contains('Portal.Auth/logout')), isFalse);
      expect(
          logs.any((l) =>
              l.contains('Folder disconnected: Shared.LocalFolder/disconnect')),
          isTrue);
    });

    testWidgets(
        'the first start in a connected folder pushes the local course and '
        'events, and a repeat push leaves one copy (7.1)', (tester) async {
      const event = <String, Object?>{
        'id': 'local-1',
        'is_local': true,
        'title': 'Exam',
        'event_date': '2026-10-21',
        'starts_at': '2026-10-21T09:00:00.000',
        'ends_at': '2026-10-21T10:00:00.000',
        'difficulty_weight': 3,
        'description': '',
        'is_completed': false,
        'completed_at': null,
        'course_id': -5,
      };
      // A weekly event from the edit dialog: the repeat rule must reach the
      // folder record.
      const weekly = <String, Object?>{
        'id': 'local-2',
        'is_local': true,
        'title': 'Lab',
        'event_date': '2026-10-22',
        'starts_at': null,
        'ends_at': null,
        'difficulty_weight': 1,
        'description': '',
        'is_completed': false,
        'completed_at': null,
        'course_id': null,
        'recurrence_freq': 'W',
        'recurrence_interval': 1,
        'recurrence_end_date': null,
        'recurrence_count': 3,
      };
      final local = <String, Object>{
        'notechondria.portal.local_events': jsonEncode([event, weekly]),
        'notechondria.portal.local_courses': jsonEncode([
          {
            'id': -5,
            'title': 'Local course',
            'description': '',
            'client_course_id': 'local-course-5',
            'is_local': true,
          }
        ]),
      };
      final seeded = (await tester.runAsync(
          () => _seedFolder(remember: true, prefs: local, pushed: false)))!;
      List<Map<String, dynamic>> folderEvents([String id = 'local-1']) {
        final raw = jsonDecode(seeded.fs.textOf('planner/events.json')!);
        return [
          for (final e in (raw as Map)['events'] as List)
            if ((e as Map)['client_local_id'] == 'portal:$id')
              Map<String, dynamic>.from(e),
        ];
      }

      late LocalFolderController c;
      final recorder = await _inFolderZone(() async {
        c = _appController(seeded.tab);
        await _pumpApp(tester, c);
        expect(c.state, LocalFolderState.active);
        await _unmount(tester);
      });
      expect(recorder.requests, isEmpty, reason: _urls(recorder));
      var events = folderEvents();
      expect(events, hasLength(1));
      expect(events.single['title'], 'Exam');
      expect(events.single['course_id'], isA<int>());
      expect(events.single['course_id'] as int, greaterThan(0));
      final repeating = folderEvents('local-2');
      expect(repeating, hasLength(1));
      expect(repeating.single['recurrence_freq'], 'W');
      expect(repeating.single['recurrence_interval'], 1);
      expect(repeating.single['recurrence_count'], 3);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notechondria.portal.local_events'), '[]');
      expect(prefs.getString('notechondria.portal.folder_pushed'),
          c.record!.folderId);
      final recovery = jsonDecode(
          prefs.getString('notechondria.portal.pushed_to_folder')!) as Map;
      expect(recovery['folder_id'], c.record!.folderId);
      expect(recovery['events'], hasLength(2));
      // The push again (a reconnect, or another browser copy of the
      // event): the folder upserts on client_local_id.
      await prefs.remove('notechondria.portal.folder_pushed');
      await prefs.setString(
          'notechondria.portal.local_events', jsonEncode([event]));
      final again = await _inFolderZone(() async {
        await _pumpApp(tester, c);
        await _unmount(tester);
      });
      expect(again.requests, isEmpty, reason: _urls(again));
      events = folderEvents();
      expect(events, hasLength(1));
      expect(prefs.getString('notechondria.portal.local_events'), '[]');
    });

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
