// Local folder smoke checks for the planner (design testing.md 8.5, Phase
// 3). App level: NotechondriaApp(localFolder:) with no client, so the
// production default-client line runs and its inner http.Client() is the
// zone's failing recorder; a dart:io client created outside the zone fails
// too.
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
import 'package:planner_app/main.dart' as app;

const String _base = 'https://notechondria.trance-0.com/api/v1';
const String _token = 'local-folder';

/// A 40-character DRF-shaped token for the in-memory cloud session.
const String _cloudToken = 'fedcba9876543210fedcba9876543210fedcba98';

/// A 1x1 PNG.
final Uint8List _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8Dw'
    'HwAFBQIAX8jx0gAAAABJRU5ErkJggg==');

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
  'notechondria.planner.local_stats':
      jsonEncode({'onboarding_seen': true, 'install_hint_dismissed': true}),
};

typedef _Seeded = ({
  MemoryFolderPlatform tab,
  MemoryFolderFs fs,
  String imageUrl,
});

/// An earlier page load connected the folder 'Smoke', saved a course and
/// two notes in it (one with an `nc-folder:` image), and already pushed
/// this browser's data (2.10 rule 3); this page load has a fresh tab of
/// the same origin and a preloaded snapshot. Runs with real async.
Future<_Seeded> _seedFolder(
    {required bool remember, Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({..._seenFirstRun, ...prefs});
  await LocalFolderBoot.preload();
  final platform = MemoryFolderPlatform();
  final fs = MemoryFolderFs(name: 'Smoke');
  platform.picker.willReturn(fs);
  final seed = LocalFolderController.forTest(
      app: 'planner', platform: platform, boot: LocalFolderBoot.snapshot);
  final pick = await seed.pickForConnect();
  await seed.connectPicked(pick!, remember: remember);
  final client = app.HttpNotechondriaClient(
      httpClient: seed.httpClient, initialBaseUrl: _base);
  final course = await client.createCourse(
      _token, {'title': 'Folder course', 'description': 'From the folder'});
  await client.createNote(_token, {
    'title': 'Folder note',
    'content': '# Folder note\n\nBody from the folder',
    'course_id': course['id'],
  });
  final image = await client.createNote(_token, {
    'title': 'Image note',
    'content': '# Image note\n\nPicture below.',
    'course_id': course['id'],
  });
  final hex = '${image['uuid']}'.replaceAll('-', '');
  final url = 'nc-folder:///assets/notes/$hex/dot.png';
  await fs.writeBytes('assets/notes/$hex/dot.png', _png);
  await client.updateNote(_token, image['id'] as int,
      {'content': '# Image note\n\nPicture below.\n\n![dot]($url)\n'});
  await seed.flushIndex();
  final folderId = seed.record!.folderId;
  seed.dispose();
  final stored = await SharedPreferences.getInstance();
  await stored.setString('notechondria.planner.folder_pushed', folderId);
  await LocalFolderBoot.preload();
  return (tab: platform.anotherTab(), fs: fs, imageUrl: url);
}

Future<void> _pumpSeconds(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _pumpShort(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

/// Mounts the planner with [folder] and no client (the production
/// default-client line, 2.7) on a tall compact surface.
Future<void> _pumpApp(WidgetTester tester, LocalFolderController folder,
    {int initialIndex = 1}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app.NotechondriaApp(
    localFolder: folder,
    initialIndex: initialIndex,
    title: 'Notechondria Planner',
    visibleIndices: const <int>[0, 1, 2, 3],
  ));
  await _pumpSeconds(tester, 3);
}

/// Unmounts the app and lets the remaining timers (splash, index flush,
/// version probe) run out on the fake clock.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpSeconds(tester, 13);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(label)));
  await _pumpSeconds(tester, 1);
}

LocalFolderController _appController(MemoryFolderPlatform tab) {
  final c = LocalFolderController.forTest(
      app: 'planner', platform: tab, boot: LocalFolderBoot.snapshot);
  addTearDown(c.dispose);
  return c;
}

Future<List<String>> _logs() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('notechondria.planner.local_logs') ?? '[]';
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

/// A cloud backend: password login, empty lists, a 7-day week.
class _CloudBackend {
  final List<http.Request> requests = [];

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    Object body = <String, Object?>{};
    if (path.endsWith('/handshake/')) {
      body = {
        'service': 'notechondria-backend',
        'api_version': 'v1',
        'version': '0.1.21',
        'min_frontend_version': '',
      };
    } else if (path.endsWith('/auth/login/')) {
      body = {
        'token': _cloudToken,
        'user': {'username': 'alice', 'email': 'alice@example.com'},
      };
    } else if (path.endsWith('/activity/week/')) {
      final today = DateTime.now();
      body = {
        'days': [
          for (var i = 0; i < 7; i++)
            {
              'date': today
                  .add(Duration(days: i))
                  .toIso8601String()
                  .split('T')
                  .first,
              'events': <Object>[],
            },
        ],
        'deadlines': <Object>[],
      };
    } else if (request.method == 'GET' &&
        (path.endsWith('/courses/') ||
            path.endsWith('/activity/') ||
            path.endsWith('/planner-events/') ||
            path.endsWith('/calendar-feeds/') ||
            path.endsWith('/notes/deleted/'))) {
      body = <Object?>[];
    } else if (request.method == 'GET' && path.endsWith('/notes/')) {
      body = {'results': <Object?>[], 'has_more': false};
    }
    return http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});
  }
}

/// Signs in through Settings > "Use email / password instead" > Login.
Future<void> _signIn(WidgetTester tester) async {
  final expander = find.text('Use email / password instead');
  await tester.ensureVisible(expander);
  await tester.pump();
  await tester.tap(expander);
  await _pumpShort(tester);
  final open = find.widgetWithText(OutlinedButton, 'Login');
  await tester.ensureVisible(open);
  await tester.pump();
  await tester.tap(open);
  await _pumpShort(tester);
  final dialog = find.byType(AlertDialog);
  await tester.enterText(
      find.descendant(
          of: dialog,
          matching: find.widgetWithText(TextField, 'Email or username')),
      'alice');
  await tester.enterText(
      find.descendant(
          of: dialog, matching: find.widgetWithText(TextField, 'Password')),
      'alice-password');
  await tester.tap(find.descendant(
      of: dialog, matching: find.widgetWithText(FilledButton, 'Login')));
  await _pumpSeconds(tester, 2);
  expect(find.byType(AlertDialog), findsNothing);
}

void registerLocalFolderSmokeTests() {
  group('local folder, planner app level (Phase 3)', () {
    testWidgets(
        'folder mode: startup, the course, learner, activity, and settings '
        'views send zero network requests', (tester) async {
      // Another app's saved cloud session does not decide for the planner,
      // which keeps its own session in memory only (2.10 rule 2).
      final editorSession = jsonEncode({
        'token': 'editor-token',
        'user': {'username': 'alice'},
      });
      final seeded = (await tester.runAsync(() => _seedFolder(
          remember: true,
          prefs: {'notechondria.editor.session': editorSession})))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        expect(c.storageMode, StorageMode.folder);
        await _pumpApp(tester, c);
        expect(c.state, LocalFolderState.active);
        await _openTab(tester, 'Learner');
        expect(find.text('Folder note'), findsWidgets);
        await _openTab(tester, 'Activity');
        await _openTab(tester, 'Settings');
        expect(find.text('Local folder'), findsOneWidget);
        expect(find.text('Disconnect folder'), findsOneWidget);
        expect(find.byType(AuthHub), findsNothing);
        await _unmount(tester);
      });
      expect(recorder.requests, isEmpty,
          reason: recorder.requests.map((r) => '${r.url}').join('\n'));
      final logs = await _logs();
      expect(
          logs.any(
              (l) => l.contains('Folder opened: Planner.Startup/local_folder')),
          isTrue);
      expect(logs.any((l) => l.contains('Cloud data not loaded')), isFalse);
    });

    testWidgets('an nc-folder image renders in the note viewer from the folder',
        (tester) async {
      final seeded =
          (await tester.runAsync(() => _seedFolder(remember: true)))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        await _pumpApp(tester, c, initialIndex: 0);
        expect(c.state, LocalFolderState.active);
        await tester.tap(find.text('Image note').first);
        await _pumpSeconds(tester, 2);
        final images = tester
            .widgetList<Image>(find.byType(Image))
            .where((i) => i.image is FolderImage)
            .toList();
        expect(images, isNotEmpty);
        expect((images.first.image as FolderImage).url, seeded.imageUrl);
        expect((images.first.image as FolderImage).folder, same(c));
        await _unmount(tester);
      });
      expect(recorder.requests, isEmpty,
          reason: recorder.requests.map((r) => '${r.url}').join('\n'));
    });

    testWidgets(
        'revoked mid-session: the reconnect view replaces the shell, '
        'Reconnect resumes, and nothing reaches the network', (tester) async {
      final seeded =
          (await tester.runAsync(() => _seedFolder(remember: true)))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        await _pumpApp(tester, c, initialIndex: 3);
        expect(c.state, LocalFolderState.active);
        seeded.fs.revoke();
        await tester.tap(find.text('Rescan folder'));
        await _pumpSeconds(tester, 2);
        expect(c.state, LocalFolderState.needsPermission);
        expect(find.text("Reconnect 'Smoke'"), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);
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
        'an in-memory cloud session stays on the cloud when another tab '
        'connects a folder', (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues(_seenFirstRun);
        await LocalFolderBoot.preload();
      });
      final backend = _CloudBackend();
      final tab = MemoryFolderPlatform();
      final fs = MemoryFolderFs(name: 'Smoke');
      await http.runWithClient(() async {
        final c = _appController(tab);
        expect(c.storageMode, StorageMode.browserOrCloud);
        await _pumpApp(tester, c, initialIndex: 3);
        await _signIn(tester);
        expect(find.text('Signed in as alice@example.com.'), findsOneWidget);
        await tester.runAsync(() async {
          final other = tab.anotherTab();
          other.picker.willReturn(fs);
          final editor = LocalFolderController.forTest(
              app: 'editor', platform: other, boot: LocalFolderBoot.snapshot);
          final pick = await editor.pickForConnect();
          await editor.connectPicked(pick!, remember: false);
          editor.dispose();
        });
        await _pumpSeconds(tester, 1);
        expect(find.textContaining('Folder connected in another tab: '),
            findsOneWidget);
        expect(c.storageMode, StorageMode.browserOrCloud);
        expect(c.folder, isNull);
        expect(find.text('Signed in as alice@example.com.'), findsOneWidget);
        final before = backend.requests.length;
        final push = find.text('Push local \u2192 cloud');
        await tester.ensureVisible(push);
        await tester.pump();
        await tester.tap(push);
        await _pumpSeconds(tester, 2);
        final after = backend.requests.sublist(before);
        expect(after, isNotEmpty);
        expect(after.any((r) => '${r.headers['Authorization']}'.contains(_cloudToken)),
            isTrue);
        await _unmount(tester);
      }, () => MockClient(backend.handle));
      for (final r in backend.requests) {
        expect('${r.headers['Authorization']}', isNot(contains(_token)),
            reason: '${r.url}');
        expect(r.url.path, isNot(contains('auth/logout')));
      }
      final logs = await _logs();
      expect(logs.any((l) => l.contains('Planner.Startup/local_folder')),
          isFalse);
    });

    testWidgets('Disconnect never signs out of the cloud and sends no token',
        (tester) async {
      final portalSession = jsonEncode({'token': 'portal-token'});
      final editorSession = jsonEncode({'token': 'editor-token'});
      final seeded = (await tester.runAsync(() => _seedFolder(remember: true,
          prefs: {
            'notechondria.portal.session': portalSession,
            'notechondria.editor.session': editorSession,
          })))!;
      final recorder = await _inFolderZone(() async {
        final c = _appController(seeded.tab);
        await _pumpApp(tester, c, initialIndex: 3);
        expect(c.state, LocalFolderState.active);
        await tester.tap(find.text('Disconnect folder'));
        await _pumpSeconds(tester, 3);
        expect(c.storageMode, StorageMode.browserOrCloud);
        expect(find.byType(AuthHub), findsOneWidget);
        await _openTab(tester, 'Learner');
        expect(find.text('Folder note'), findsNothing);
        await _unmount(tester);
      });
      // After the switch the signed-out planner loads public data again; no
      // request carries a token and none is a logout.
      for (final r in recorder.requests) {
        expect(r.headers.containsKey('Authorization'), isFalse,
            reason: '${r.url}');
        expect(r.url.path, isNot(contains('auth/logout')));
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notechondria.portal.session'), portalSession);
      expect(prefs.getString('notechondria.editor.session'), editorSession);
      expect(prefs.containsKey(kSharedStorageModeKey), isFalse);
      final cache = prefs.getString('notechondria.planner.local_cache') ?? '';
      expect(cache, isNot(contains('Folder course')));
      final logs = await _logs();
      expect(logs.any((l) => l.contains('Planner.Auth/logout')), isFalse);
      expect(
          logs.any((l) =>
              l.contains('Folder disconnected: Shared.LocalFolder/disconnect')),
          isTrue);
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
      final backend = _CloudBackend();
      await http.runWithClient(() async {
        for (final qualified in [true, false]) {
          final c = _appController(qualified
              ? MemoryFolderPlatform()
              : MemoryFolderPlatform(probeInputs: firefox));
          await _pumpApp(tester, c, initialIndex: 3);
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
      }, () => MockClient(backend.handle));
    });
  });
}
