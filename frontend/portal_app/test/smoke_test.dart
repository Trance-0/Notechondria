import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:portal_app/main.dart' as app;
import 'package:notechondria_shared/notechondria_shared.dart';

import 'local_folder_smoke.dart';

/// Fake backend for the startup-fallback tests: either never answers
/// (an unresponsive server) or answers every request with empty data.
class _Backend {
  bool hang = true;
  int requests = 0;
  int handshakes = 0;

  Future<http.Response> handle(http.Request request) {
    requests++;
    if (hang) return Completer<http.Response>().future;
    final path = request.url.path;
    if (path.endsWith('/handshake/')) {
      handshakes++;
      // 0.1.21 = the test build's APP_VERSION, so no update banner.
      return Future.value(http.Response(
          jsonEncode({
            'service': 'notechondria-backend',
            'api_version': 'v1',
            'version': '0.1.21',
            'min_frontend_version': '',
          }),
          200,
          headers: {'content-type': 'application/json'}));
    }
    final isList = path.endsWith('/courses/') || path.endsWith('/activity/');
    return Future.value(http.Response(isList ? '[]' : '{}', 200,
        headers: {'content-type': 'application/json'}));
  }
}

/// First-run overlays (tour, what's new) would cover the shell.
Map<String, Object> _seenFirstRun([Map<String, Object> extra = const {}]) => {
      'notechondria.portal.local_stats':
          jsonEncode({'onboarding_seen': true, 'install_hint_dismissed': true}),
      ...extra,
    };

Future<void> _pumpPortal(WidgetTester tester, _Backend backend) {
  return tester.pumpWidget(app.NotechondriaApp(
    client: app.HttpNotechondriaClient(httpClient: MockClient(backend.handle)),
    initialIndex: 0,
    title: 'Notechondria Portal',
    visibleIndices: const <int>[0, 1, 2, 3, 4],
  ));
}

Future<void> _pumpSeconds(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Captures `Clipboard.setData`; reset after the test.
List<String> _mockClipboard(WidgetTester tester) {
  final writes = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      writes.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return writes;
}

/// A saved session whose token must never reach the debug log.
const String _secretToken = 'phase1-secret-token';

void main() {
  testWidgets('portal app boots with front page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // main() installs the startup ErrorWidget.builder; flutter_test
    // requires it restored before the test body ends.
    final errorWidgetBuilder = ErrorWidget.builder;
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Front page'), findsWidgets);
    ErrorWidget.builder = errorWidgetBuilder;
  });

  group('startup fallbacks (0.1.198)', () {
    testWidgets(
        'unresponsive backend shows the backend-unavailable banner, '
        'and Retry recovers', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend();
      await _pumpPortal(tester, backend);
      await _pumpSeconds(tester, 12);
      // Not blank: the shell renders local data plus the banner.
      expect(find.text('Front page'), findsWidgets);
      final banner = find.byType(LoadErrorBanner);
      expect(banner, findsOneWidget);
      expect(
          find.descendant(
              of: banner,
              matching: find.textContaining(
                  'Portal.Startup/bootstrap — the server did not respond '
                  'within 10s')),
          findsOneWidget);

      final before = backend.requests;
      backend.hang = false;
      await tester.tap(
          find.descendant(of: banner, matching: find.text('Retry')));
      await _pumpSeconds(tester, 2);
      expect(backend.requests, greaterThan(before));
      expect(find.byType(LoadErrorBanner), findsNothing);
      // Let the version-banner handshake probe that started while the
      // backend hung reach its own 8s timeout (no pending timers).
      await _pumpSeconds(tester, 8);
    });

    testWidgets('a bootstrap exception renders the startup failure screen',
        (tester) async {
      // A corrupt local cache makes _loadLocalState throw a TypeError.
      SharedPreferences.setMockInitialValues(_seenFirstRun({
        'notechondria.portal.local_cache': jsonEncode({'courses': 'corrupt'}),
      }));
      final backend = _Backend()..hang = false;
      await _pumpPortal(tester, backend);
      await _pumpSeconds(tester, 1);
      expect(find.text('The app could not finish starting'), findsOneWidget);
      expect(find.textContaining('Portal.Startup/bootstrap'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // "Continue anyway" reaches the shell (and its local-data settings).
      await tester.tap(find.text('Continue anyway'));
      await _pumpSeconds(tester, 1);
      expect(find.text('The app could not finish starting'), findsNothing);
      expect(find.text('Front page'), findsWidgets);
    });
  });

  group('note-conflict line diff (#31)', () {
    test('identical text yields only equal rows', () {
      final rows = diffLines('a\nb\nc', 'a\nb\nc');
      expect(rows.every((r) => r.kind == DiffLineKind.equal), isTrue);
      expect(rows.map((r) => r.left).toList(), ['a', 'b', 'c']);
    });
    test('a replaced line is a changed row (old left, new right)', () {
      final rows = diffLines('a\nB\nc', 'a\nX\nc');
      final changed = rows.where((r) => r.kind == DiffLineKind.changed).toList();
      expect(changed.length, 1);
      expect(changed.single.left, 'B');
      expect(changed.single.right, 'X');
      // The unchanged lines survive as equal rows.
      expect(rows.where((r) => r.kind == DiffLineKind.equal).length, 2);
    });
    test('remote-only lines are added; local-only lines are removed', () {
      final added = diffLines('a\nc', 'a\nb\nc');
      expect(added.where((r) => r.kind == DiffLineKind.added).single.right, 'b');
      final removed = diffLines('a\nb\nc', 'a\nc');
      expect(
          removed.where((r) => r.kind == DiffLineKind.removed).single.left, 'b');
    });
    test('CRLF vs LF alone is not a difference', () {
      final rows = diffLines('a\r\nb', 'a\nb');
      expect(rows.every((r) => r.kind == DiffLineKind.equal), isTrue);
    });
    test('empty local vs non-empty remote is all added', () {
      final rows = diffLines('', 'x\ny');
      expect(rows.map((r) => r.kind).toSet(), {DiffLineKind.added});
      expect(rows.map((r) => r.right).toList(), ['x', 'y']);
    });
  });

  group('cross-user offline-cache ownership (#13)', () {
    test('unrecorded owner is claimed by the current user', () {
      final d = resolveLocalDataOwner(recordedOwner: null, currentUser: 'alice');
      expect(d.status, LocalDataOwnership.claimed);
      expect(d.owner, 'alice');
      expect(d.isForeign, isFalse);
    });
    test('empty recorded owner is claimed', () {
      final d = resolveLocalDataOwner(recordedOwner: '', currentUser: 'alice');
      expect(d.status, LocalDataOwnership.claimed);
      expect(d.owner, 'alice');
    });
    test('same user (case/space-insensitive) is sameUser', () {
      final d =
          resolveLocalDataOwner(recordedOwner: ' Alice ', currentUser: 'alice');
      expect(d.status, LocalDataOwnership.sameUser);
      expect(d.isForeign, isFalse);
    });
    test('different user is flagged foreign with the prior owner', () {
      final d =
          resolveLocalDataOwner(recordedOwner: 'alice', currentUser: 'bob');
      expect(d.status, LocalDataOwnership.foreignUser);
      expect(d.isForeign, isTrue);
      expect(d.priorOwner, 'alice');
      // The owner stamp is NOT reassigned to bob — that would let alice's
      // cache sync as bob's.
      expect(d.owner, 'alice');
    });
    test('empty current user is a no-op (nothing to decide)', () {
      final d = resolveLocalDataOwner(recordedOwner: 'alice', currentUser: '');
      expect(d.status, LocalDataOwnership.sameUser);
    });
  });

  group('startup logs and loading surface (0.1.199)', () {
    testWidgets(
        'a hanging backend: one loading surface at a time, then startup '
        'records with durations and the timeout cause', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun({
        'notechondria.portal.session': jsonEncode({'token': _secretToken}),
      }));
      final clipboard = _mockClipboard(tester);
      final backend = _Backend();
      await _pumpPortal(tester, backend);
      var sawStepStatus = false;
      for (var i = 0; i < 48; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final surfaces = find.byType(SplashScreen).evaluate().length +
            find.byType(CircularProgressIndicator).evaluate().length +
            find.byType(LinearProgressIndicator).evaluate().length;
        expect(surfaces, lessThanOrEqualTo(1), reason: 'frame $i');
        if (find
            .descendant(
                of: find.byType(SplashScreen),
                matching: find.textContaining('Portal.Startup/'))
            .evaluate()
            .isNotEmpty) {
          sawStepStatus = true;
        }
      }
      expect(sawStepStatus, isTrue);
      expect(find.byType(SplashScreen), findsNothing);
      final banner = find.byType(LoadErrorBanner);
      expect(banner, findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('notechondria.portal.local_logs')!;
      expect(raw, isNot(contains(_secretToken)));
      final logs = (jsonDecode(raw) as List<dynamic>).cast<String>();
      bool has(String pattern) => logs.any((l) => l.contains(pattern));
      expect(has('Portal.Startup/local_state'), isTrue);
      expect(has('API base resolved: Portal.Startup/config'), isTrue);
      expect(
          logs.any((l) =>
              l.contains('Backend not reachable: Portal.Startup/handshake') &&
              l.contains('timeout after 10s')),
          isTrue,
          reason: logs.join('\n'));
      expect(
          has('Session not restored yet: Portal.Startup/session_restore'),
          isTrue);
      expect(has('Portal.Startup/initial_data'), isTrue);
      expect(
          logs.any((l) =>
              l.contains('Portal.HTTP/request_failed') && l.contains('ms: ')),
          isTrue);
      for (final step in [
        'local_state',
        'handshake',
        'session_restore',
        'oauth_callback',
        'initial_data'
      ]) {
        expect(
            logs.any((l) =>
                l.contains('] Portal.Startup/$step — ') &&
                !l.contains('Startup step started') &&
                l.endsWith('ms)')),
            isTrue,
            reason: 'outcome line with duration for $step');
      }

      await tester.tap(find.descendant(
          of: banner, matching: find.byTooltip('Copy message')));
      await tester.pump();
      expect(clipboard, hasLength(1));
      expect(clipboard.single, contains('Portal.Startup/bootstrap'));
      await _pumpSeconds(tester, 8);
    });

    testWidgets(
        'a responsive backend logs the reachable handshake and the session '
        'restore outcome, never the token', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun({
        'notechondria.portal.session': jsonEncode({'token': _secretToken}),
      }));
      final backend = _Backend()..hang = false;
      await _pumpPortal(tester, backend);
      await _pumpSeconds(tester, 3);
      expect(find.byType(SplashScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getString('notechondria.portal.local_logs')!;
      expect(logs, contains('Backend reachable: Portal.Startup/handshake'));
      // The version banner reuses the startup handshake (also after the
      // splash closes and the banner is rebuilt).
      expect(backend.handshakes, 1);
      expect(logs, contains('notechondria-backend v0.1.21'));
      expect(logs, contains('Portal.Startup/session_restore'));
      expect(logs, contains('saved session cleared'));
      expect(logs, isNot(contains(_secretToken)));
      expect(find.textContaining('A new version is available'), findsNothing);
    });
  });
  // Last: the boot test above draws app.main()'s warm-up frame, which reuses
  // the binding's last frame time, so it must run before these tests pump
  // frames on their own fake clocks.
  registerLocalFolderSmokeTests();
}
