import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

/// Startup resilience (0.1.198): bounded startup requests, the
/// backend-unavailable banner, the bootstrap failure screen, and the
/// global error guards. Timers are driven with bounded pumps (the fake
/// clock), never pumpAndSettle.
class _Probe with HttpClientInternalsMixin {
  _Probe(this.httpClient);

  @override
  final http.Client httpClient;
  @override
  final ValueNotifier<ApiDebugSnapshot?> debugSnapshot = ValueNotifier(null);
  @override
  final ValueNotifier<List<ApiDebugSnapshot>> debugHistory =
      ValueNotifier(const []);
  @override
  void Function(DebugLogLevel, String, String)? get logger => null;
  @override
  String get httpLogTagPrefix => 'Test';

  Future<http.Response> get(Uri uri) =>
      send('GET', uri, () => httpClient.get(uri));
}

Widget _localized(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

class _Thrower extends StatelessWidget {
  const _Thrower();

  @override
  Widget build(BuildContext context) => throw StateError('render boom');
}

void main() {
  group('StartupRequestBudget', () {
    testWidgets('times out a hanging request, then fails the rest fast',
        (tester) async {
      final budget = StartupRequestBudget(source: 'Test.Startup/bootstrap');
      Object? first;
      unawaited(budget
          .run('GET /api/v1/front-page/', () => Completer<int>().future)
          .then<void>((_) {}, onError: (Object error) => first = error));
      await tester.pump(const Duration(seconds: 9));
      expect(first, isNull, reason: 'still within the 10s bound');
      await tester.pump(const Duration(seconds: 2));
      expect(first, isA<BackendStartupTimeout>());
      expect(first.toString(), contains('Test.Startup/bootstrap'));
      expect(first.toString(), contains('within 10s'));
      expect(budget.timedOut, isTrue);

      // A later request in the same pass is skipped without waiting.
      var called = false;
      Object? second;
      await budget.run('GET /api/v1/courses/', () async {
        called = true;
        return 1;
      }).then<void>((_) {}, onError: (Object error) => second = error);
      expect(called, isFalse);
      expect((second as BackendStartupTimeout).skipped, isTrue);
    });

    test('runWithStartupBudget scopes the budget to its zone', () async {
      final budget = StartupRequestBudget(source: 'Test.Startup/retry');
      expect(currentStartupBudget, isNull);
      final seen = await runWithStartupBudget(budget, () async {
        await Future<void>.delayed(Duration.zero);
        return currentStartupBudget;
      });
      expect(seen, same(budget));
      expect(currentStartupBudget, isNull);
    });
  });

  group('HttpClientInternalsMixin.send', () {
    final uri = Uri.parse('https://backend.test/api/v1/front-page/');

    testWidgets('inside a startup pass a hanging backend times out',
        (tester) async {
      final probe =
          _Probe(MockClient((_) => Completer<http.Response>().future));
      Object? caught;
      unawaited(runWithStartupBudget(
        StartupRequestBudget(source: 'Test.Startup/bootstrap'),
        () => probe.get(uri),
      ).then<void>((_) {}, onError: (Object error) => caught = error));
      await tester.pump(const Duration(seconds: 11));
      expect(caught, isA<BackendStartupTimeout>());
      expect(caught.toString(), contains('GET /api/v1/front-page/'));
      expect(probe.debugSnapshot.value?.statusCode, 0);
    });

    test('a refused connection is a shaped network failure', () async {
      final probe = _Probe(MockClient(
          (_) async => throw http.ClientException('Failed to fetch', uri)));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      Object? caught;
      try {
        await probe.get(uri);
      } catch (error) {
        caught = error;
      }
      expect(caught.toString(), contains('Server request failed: '));
      expect(caught.toString(), contains('Test.HTTP/request'));
      expect(friendlyError(en, caught), en.errorNetwork('Test.HTTP/request'));
    });
  });

  group('LoadErrorBanner', () {
    testWidgets('renders the backend-unavailable state with its actions',
        (tester) async {
      var retries = 0;
      var offline = 0;
      const timeout = BackendStartupTimeout(
        source: 'Test.Startup/bootstrap',
        request: 'GET /api/v1/front-page/',
        timeout: Duration(seconds: 10),
      );
      await tester.pumpWidget(_localized(Scaffold(
        body: LoadErrorBanner(
          message: timeout.toString(),
          source: 'Test.Startup/initial_data',
          onRetry: () => retries++,
          onWorkOffline: () => offline++,
          onDismiss: () {},
        ),
      )));
      expect(
          find.text('Cloud data not loaded: Test.Startup/bootstrap — the '
              'server did not respond within 10s. Showing data saved on this '
              'device; retry or work offline.'),
          findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Work offline'));
      expect(retries, 1);
      expect(offline, 1);
    });

    testWidgets('hides Work offline when already offline', (tester) async {
      await tester.pumpWidget(_localized(Scaffold(
        body: LoadErrorBanner(
          message: 'Title is required.',
          source: 'Test.Startup/initial_data',
          onRetry: () {},
          onDismiss: () {},
        ),
      )));
      expect(find.text('Title is required.'), findsOneWidget);
      expect(find.text('Work offline'), findsNothing);
    });
  });

  group('startup failure fallbacks', () {
    testWidgets('StartupFailureView shows the cause, Retry, and Continue',
        (tester) async {
      var retries = 0;
      var continued = 0;
      await tester.pumpWidget(_localized(StartupFailureView(
        source: 'Test.Startup/bootstrap',
        cause: 'local cache is corrupt',
        onRetry: () => retries++,
        onContinue: () => continued++,
      )));
      expect(find.text('The app could not finish starting'), findsOneWidget);
      expect(
          find.text('The app could not finish starting: '
              'Test.Startup/bootstrap — local cache is corrupt. Retry, or '
              'continue with the data saved on this device.'),
          findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Continue anyway'));
      expect(retries, 1);
      expect(continued, 1);
    });

    testWidgets('an uncaught error before the first frame shows the fallback',
        (tester) async {
      final guard = StartupGuard(
        appModule: 'Test',
        appTitle: 'Test App',
        buildApp: () =>
            const Text('real app', textDirection: TextDirection.ltr),
      );
      guard.handleUncaughtError(StateError('boot boom'), StackTrace.current);
      await tester.pump();
      expect(find.textContaining('Test.Startup/zone'), findsOneWidget);
      expect(find.textContaining('boot boom'), findsOneWidget);
      expect(guard.firstFrameShown, isTrue);

      // Retry relaunches the real app.
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(find.text('real app'), findsOneWidget);

      // Once a frame is on screen, later uncaught errors are logged only.
      guard.handleUncaughtError(StateError('late boom'), StackTrace.current);
      await tester.pump();
      expect(find.text('real app'), findsOneWidget);
    });

    testWidgets('a widget that throws during build is not rendered blank',
        (tester) async {
      final previous = ErrorWidget.builder;
      ErrorWidget.builder =
          (details) => StartupErrorWidget(appModule: 'Test', details: details);
      try {
        await tester.pumpWidget(const _Thrower());
        expect(tester.takeException(), isA<StateError>());
        expect(
            find.textContaining('This part of the screen cannot be shown: '
                'Test.UI/render'),
            findsOneWidget);
        expect(find.textContaining('render boom'), findsOneWidget);
      } finally {
        ErrorWidget.builder = previous;
      }
    });

    testWidgets('installErrorHandlers chains the previous handlers',
        (tester) async {
      final previousBuilder = ErrorWidget.builder;
      final previousOnError = FlutterError.onError;
      final previousPlatform = PlatformDispatcher.instance.onError;
      FlutterErrorDetails? forwarded;
      FlutterError.onError = (details) => forwarded = details;
      try {
        StartupGuard(
          appModule: 'Test',
          appTitle: 'Test App',
          buildApp: () => const SizedBox.shrink(),
        ).installErrorHandlers();
        expect(
            ErrorWidget.builder(FlutterErrorDetails(exception: StateError('x'))),
            isA<StartupErrorWidget>());
        FlutterError.onError!(FlutterErrorDetails(exception: StateError('y')));
        expect(forwarded?.exception, isA<StateError>());
        expect(PlatformDispatcher.instance.onError, isNotNull);
      } finally {
        ErrorWidget.builder = previousBuilder;
        FlutterError.onError = previousOnError;
        PlatformDispatcher.instance.onError = previousPlatform;
      }
    });
  });
}
