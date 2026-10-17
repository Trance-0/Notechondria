import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

/// Startup and HTTP logging (0.1.199): specific failure causes, startup
/// step records with durations, the slow-request warning, the non-JSON
/// response message, and the splash status suffix.
class _Probe with HttpClientInternalsMixin {
  _Probe(this.httpClient);

  @override
  final http.Client httpClient;
  @override
  final ValueNotifier<ApiDebugSnapshot?> debugSnapshot = ValueNotifier(null);
  @override
  final ValueNotifier<List<ApiDebugSnapshot>> debugHistory =
      ValueNotifier(const []);
  final List<(DebugLogLevel, String, String)> lines = [];

  @override
  void Function(DebugLogLevel, String, String)? get logger =>
      (level, source, message) => lines.add((level, source, message));
  @override
  String get httpLogTagPrefix => 'Test';

  Future<http.Response> get(Uri uri) =>
      send('GET', uri, () => httpClient.get(uri));
}

class _LogHost extends StatefulWidget {
  const _LogHost();

  @override
  State<_LogHost> createState() => _LogHostState();
}

class _LogHostState extends State<_LogHost> with AppShellLogMixin<_LogHost> {
  @override
  final List<String> uiLogs = <String>[];
  @override
  final DebugLogController logController = DebugLogController();
  @override
  Future<void> persistUiLogs() async {}

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

final _uri = Uri.parse('https://backend.test/api/v1/front-page/');

void main() {
  group('describeRequestFailure', () {
    test('names startup timeouts and skips', () {
      const timeout = BackendStartupTimeout(
        source: 'Test.Startup/bootstrap',
        request: 'GET /api/v1/handshake/',
        timeout: Duration(seconds: 10),
      );
      expect(describeRequestFailure(timeout),
          'timeout after 10s (server did not respond)');
      const skipped = BackendStartupTimeout(
        source: 'Test.Startup/bootstrap',
        request: 'GET /api/v1/courses/',
        timeout: Duration(seconds: 10),
        skipped: true,
      );
      expect(describeRequestFailure(skipped),
          'skipped: an earlier startup request timed out after 10s');
      expect(describeRequestFailure(Exception(timeout.toString())),
          'timeout after 10s (server did not respond)');
      expect(
          describeRequestFailure(
              TimeoutException('x', const Duration(seconds: 8))),
          'timeout after 8s (server did not respond)');
    });

    test('tells refused, DNS, browser-opaque, and TLS failures apart', () {
      expect(describeRequestFailure(http.ClientException('Connection refused')),
          'connection refused');
      expect(
          describeRequestFailure(
              http.ClientException('Failed host lookup: backend.test')),
          'DNS lookup failed');
      expect(
          describeRequestFailure(http.ClientException('XMLHttpRequest error.')),
          startsWith('network error with no readable response'));
      expect(
          describeRequestFailure(
              Exception('HandshakeException: CERTIFICATE_VERIFY_FAILED')),
          'TLS handshake failed');
      expect(describeRequestFailure(StateError('bad')),
          'StateError: Bad state: bad');
    });

    test('reads HTML-instead-of-JSON and HTTP-layer causes', () {
      expect(
          describeRequestFailure(Exception(
              'Server response not usable: Test.HTTP/response — expected '
              'JSON from GET https://backend.test/api/v1/a/ but received '
              'HTML (HTTP 502, text/html, 12B); check the API base URL.')),
          'HTML instead of JSON (HTTP 502)');
      expect(
          describeRequestFailure(Exception(
              'Server request failed: Test.HTTP/request — client failed to '
              'fetch GET https://backend.test/api/v1/a/ before a response '
              'arrived (network error with no readable response (browser '
              'hides the reason)).')),
          'network error with no readable response (browser hides the '
          'reason)');
    });

    test('drops query strings and redacts credentials', () {
      final text = describeRequestFailure(Exception(
          'boom at https://backend.test/api/v1/notes/?search=private '
          'with Bearer eyJsecret.value and Token 0123abcd'));
      expect(text, isNot(contains('private')));
      expect(text, isNot(contains('eyJsecret')));
      expect(text, isNot(contains('0123abcd')));
      expect(text, contains('Bearer <redacted>'));
      expect(text, contains('https://backend.test/api/v1/notes/'));
    });
  });

  group('HttpClientInternalsMixin logging', () {
    test('a failed request logs host, path, duration, and the cause',
        () async {
      final probe = _Probe(MockClient(
          (_) async => throw http.ClientException('Connection refused')));
      final secretUri =
          Uri.parse('https://backend.test/api/v1/front-page/?q=secret');
      Object? caught;
      try {
        await probe.get(secretUri);
      } catch (error) {
        caught = error;
      }
      final failure =
          probe.lines.singleWhere((l) => l.$2 == 'Test.HTTP/request_failed');
      expect(failure.$1, DebugLogLevel.warning);
      expect(
          failure.$3,
          allOf(
            contains('GET backend.test/api/v1/front-page/ after '),
            endsWith('ms: connection refused.'),
          ));
      expect(caught.toString(), contains('Server request failed: '));
      expect(caught.toString(), contains('failed to fetch'));
      expect(caught.toString(), contains('(connection refused)'));
      expect(caught.toString(), isNot(contains('secret')));
    });

    test('a slow startup request logs an HTTP/slow warning', () async {
      final probe = _Probe(MockClient((_) => Future.delayed(
            const Duration(milliseconds: 3100),
            () => http.Response('{}', 200),
          )));
      await runWithStartupBudget(
        StartupRequestBudget(source: 'Test.Startup/bootstrap'),
        () => probe.get(_uri),
      );
      final slow = probe.lines.singleWhere((l) => l.$2 == 'Test.HTTP/slow');
      expect(slow.$1, DebugLogLevel.warning);
      expect(slow.$3, startsWith('HTTP response slow: Test.HTTP/slow — GET '));
      expect(slow.$3, contains('during startup (limit 10s)'));
    });

    test('an HTML body is a logged, shaped Test.HTTP/response failure',
        () async {
      final probe = _Probe(MockClient((_) async => http.Response(
          '<html>bad gateway</html>', 502,
          headers: {'content-type': 'text/html'})));
      final response = await probe.get(_uri);
      Object? caught;
      try {
        await probe.decode(response, uri: _uri, method: 'GET');
      } catch (error) {
        caught = error;
      }
      final expected = 'Server response not usable: Test.HTTP/response — '
          'expected JSON from GET $_uri but received HTML (HTTP 502, '
          'text/html, 24B); check the API base URL and backend routing.';
      expect(caught.toString(), 'Exception: $expected');
      expect(
          probe.lines.where((l) =>
              l.$1 == DebugLogLevel.warning && l.$3 == expected),
          hasLength(1));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(friendlyError(en, caught), en.errorServer('Test.HTTP/response'));
    });
  });

  group('AppShellLogMixin.startupStep', () {
    testWidgets('logs start, outcome, and duration; sets the splash status',
        (tester) async {
      await tester.pumpWidget(const _LogHost());
      final state = tester.state<_LogHostState>(find.byType(_LogHost));
      final status = ValueNotifier<String>('');
      addTearDown(status.dispose);
      final value = await state.startupStep<int>(
        'Test.Startup/handshake',
        () async => 7,
        status: status,
        label: 'Connecting to server',
        outcome: (v) => (
          level: DebugLogLevel.info,
          message: 'Backend reachable: Test.Startup/handshake — got $v.',
        ),
      );
      expect(value, 7);
      expect(status.value, 'Connecting to server: Test.Startup/handshake');
      final lines = state.uiLogs.reversed.toList();
      expect(lines, hasLength(2));
      expect(lines[0], contains('[D] Test.Startup/handshake — '
          'Startup step started: Test.Startup/handshake — '
          'Connecting to server.'));
      expect(lines[1], contains('[I] Test.Startup/handshake — '
          'Backend reachable: Test.Startup/handshake — got 7.'));
      expect(lines[1], matches(RegExp(r'\(\d+ms\)$')));
    });

    testWidgets('a failing step logs the cause and rethrows', (tester) async {
      await tester.pumpWidget(const _LogHost());
      final state = tester.state<_LogHostState>(find.byType(_LogHost));
      Object? caught;
      try {
        await state.startupStep<void>(
          'Test.Startup/config',
          () async => throw http.ClientException('Connection refused'),
          failureConsequence: 'API base not resolved',
        );
      } catch (error) {
        caught = error;
      }
      expect(caught, isA<http.ClientException>());
      final last = state.uiLogs.first;
      expect(last, contains('[E] Test.Startup/config — API base not '
          'resolved: Test.Startup/config — connection refused.'));
      expect(last, matches(RegExp(r'\(\d+ms\)$')));
    });
  });

  testWidgets('the splash localizes the label and keeps the step name',
      (tester) async {
    final status =
        ValueNotifier<String>('Connecting to server: Planner.Startup/handshake');
    addTearDown(status.dispose);
    Widget host(Locale locale) => MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SplashScreen(
            appTitle: 'Notechondria Planner',
            appVersion: '0.1.199',
            loadingStatus: status,
          ),
        );
    await tester.pumpWidget(host(const Locale('en')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Connecting to server: Planner.Startup/handshake'),
        findsOneWidget);
    await tester.pumpWidget(host(const Locale('zh')));
    await tester.pump(const Duration(milliseconds: 400));
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text('${zh.splashConnectingToServer}: Planner.Startup/handshake'),
        findsOneWidget);
    expect(kIsWeb, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
