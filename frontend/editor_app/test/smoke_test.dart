import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notechondria_shared/notechondria_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:editor_app/main.dart' as app;

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
      'notechondria.editor.local_stats':
          jsonEncode({'onboarding_seen': true, 'install_hint_dismissed': true}),
      ...extra,
    };

Future<void> _pumpEditor(WidgetTester tester, _Backend backend) {
  return tester.pumpWidget(app.NotechondriaApp(
    client: app.HttpNotechondriaClient(httpClient: MockClient(backend.handle)),
    initialIndex: 1,
    title: 'Notechondria Editor',
    visibleIndices: const <int>[1, 4],
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
  testWidgets('editor app boots with starter offline content', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // main() installs the startup ErrorWidget.builder; flutter_test
    // requires it restored before the test body ends.
    final errorWidgetBuilder = ErrorWidget.builder;
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Welcome to the editor workspace'), findsOneWidget);
    ErrorWidget.builder = errorWidgetBuilder;
  });

  group('startup fallbacks (0.1.198)', () {
    testWidgets(
        'unresponsive backend shows the backend-unavailable banner over '
        'local drafts, and Retry recovers', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend();
      await _pumpEditor(tester, backend);
      await _pumpSeconds(tester, 12);
      // Not blank: the local starter draft still renders.
      expect(find.text('Welcome to the editor workspace'), findsOneWidget);
      final banner = find.byType(LoadErrorBanner);
      expect(banner, findsOneWidget);
      expect(
          find.descendant(
              of: banner,
              matching: find.textContaining(
                  'Editor.Startup/bootstrap — the server did not respond '
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
        'notechondria.editor.local_cache': jsonEncode({'courses': 'corrupt'}),
      }));
      final backend = _Backend()..hang = false;
      await _pumpEditor(tester, backend);
      await _pumpSeconds(tester, 1);
      expect(find.text('The app could not finish starting'), findsOneWidget);
      expect(find.textContaining('Editor.Startup/bootstrap'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Continue anyway'));
      await _pumpSeconds(tester, 1);
      expect(find.text('The app could not finish starting'), findsNothing);
    });
  });
  group('startup logs and loading surface (0.1.199)', () {
    testWidgets(
        'a hanging backend: one loading surface at a time, then startup '
        'records with durations and the timeout cause', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun({
        'notechondria.editor.session': jsonEncode({'token': _secretToken}),
      }));
      final clipboard = _mockClipboard(tester);
      final backend = _Backend();
      await _pumpEditor(tester, backend);
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
                matching: find.textContaining('Editor.Startup/'))
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
      final raw = prefs.getString('notechondria.editor.local_logs')!;
      expect(raw, isNot(contains(_secretToken)));
      final logs = (jsonDecode(raw) as List<dynamic>).cast<String>();
      bool has(String pattern) => logs.any((l) => l.contains(pattern));
      expect(has('Editor.Startup/local_state'), isTrue);
      expect(has('API base resolved: Editor.Startup/config'), isTrue);
      expect(
          logs.any((l) =>
              l.contains('Backend not reachable: Editor.Startup/handshake') &&
              l.contains('timeout after 10s')),
          isTrue,
          reason: logs.join('\n'));
      expect(
          has('Session not restored yet: Editor.Startup/session_restore'),
          isTrue);
      expect(has('Editor.Startup/initial_data'), isTrue);
      expect(
          logs.any((l) =>
              l.contains('Editor.HTTP/request_failed') && l.contains('ms: ')),
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
                l.contains('] Editor.Startup/$step — ') &&
                !l.contains('Startup step started') &&
                l.endsWith('ms)')),
            isTrue,
            reason: 'outcome line with duration for $step');
      }

      await tester.tap(find.descendant(
          of: banner, matching: find.byTooltip('Copy message')));
      await tester.pump();
      expect(clipboard, hasLength(1));
      expect(clipboard.single, contains('Editor.Startup/bootstrap'));
      await _pumpSeconds(tester, 8);
    });

    testWidgets(
        'a responsive backend logs the reachable handshake and the session '
        'restore outcome, never the token', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun({
        'notechondria.editor.session': jsonEncode({'token': _secretToken}),
      }));
      final backend = _Backend()..hang = false;
      await _pumpEditor(tester, backend);
      await _pumpSeconds(tester, 3);
      expect(find.byType(SplashScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getString('notechondria.editor.local_logs')!;
      expect(logs, contains('Backend reachable: Editor.Startup/handshake'));
      // The version banner reuses the startup handshake (also after the
      // splash closes and the banner is rebuilt).
      expect(backend.handshakes, 1);
      expect(logs, contains('notechondria-backend v0.1.21'));
      expect(logs, contains('Editor.Startup/session_restore'));
      expect(logs, contains('saved session cleared'));
      expect(logs, isNot(contains(_secretToken)));
      expect(find.textContaining('A new version is available'), findsNothing);
    });
  });
}
