import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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

  Future<http.Response> handle(http.Request request) {
    requests++;
    if (hang) return Completer<http.Response>().future;
    final path = request.url.path;
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
}
