import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../components/startup_failure_view.dart';
import '../l10n/app_localizations.dart';

/// Runs an app's root widget behind the shared startup guards so a Dart
/// failure never leaves the page blank:
///
/// * `runZonedGuarded` + `PlatformDispatcher.instance.onError` catch
///   uncaught async errors. Before the first frame they replace the tree
///   with [StartupFailureApp]; after it they are logged only, because the
///   app shell is on screen and owns its own fallbacks (the
///   backend-unavailable banner, its bootstrap failure view).
/// * `FlutterError.onError` logs framework errors in the AGENTS.md §1.8
///   shape and forwards them to the previous handler.
/// * `ErrorWidget.builder` renders [StartupErrorWidget] instead of the
///   release-mode grey box when a widget throws during build.
///
/// [appModule] is the module prefix used in messages (`Editor`, `Planner`,
/// `Portal`); [buildApp] creates the root widget and is called again by
/// the fallback's Retry.
void runGuardedApp({
  required String appModule,
  required String appTitle,
  required Widget Function() buildApp,
}) {
  final guard = StartupGuard(
    appModule: appModule,
    appTitle: appTitle,
    buildApp: buildApp,
  );
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    guard.installErrorHandlers();
    guard.launch();
  }, guard.handleUncaughtError);
}

/// State behind [runGuardedApp]. Public so the handlers can be exercised
/// directly in widget tests.
class StartupGuard {
  StartupGuard({
    required this.appModule,
    required this.appTitle,
    required this.buildApp,
  });

  final String appModule;
  final String appTitle;
  final Widget Function() buildApp;
  bool _firstFrameShown = false;

  /// Whether any frame has been produced since the last [launch] or
  /// fallback, i.e. whether something other than a blank page is visible.
  bool get firstFrameShown => _firstFrameShown;

  /// Mounts the app and starts watching for its first frame.
  void launch() {
    _firstFrameShown = false;
    runApp(buildApp());
    _watchFirstFrame();
  }

  void installErrorHandlers() {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint(
        'Screen element not rendered: $appModule.UI/render \u2014 '
        '${_firstLine(details.exceptionAsString())} '
        '(library: ${details.library ?? 'unknown'}).',
      );
      (previousFlutterError ?? FlutterError.presentError)(details);
    };
    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      handleUncaughtError(error, stack);
      previousPlatformError?.call(error, stack);
      return true;
    };
    ErrorWidget.builder = (details) =>
        StartupErrorWidget(appModule: appModule, details: details);
  }

  /// Logs an uncaught error; before the first frame also swaps in the
  /// startup fallback so the user sees the cause and a Retry instead of a
  /// blank page.
  void handleUncaughtError(Object error, StackTrace stack) {
    if (_firstFrameShown) {
      debugPrint(
        'Background task failed: $appModule.Startup/uncaught_error \u2014 '
        '${_firstLine(error.toString())}.\n$stack',
      );
      return;
    }
    debugPrint(
      '$appTitle cannot start: $appModule.Startup/zone \u2014 '
      '${_firstLine(error.toString())}. Showing the startup fallback '
      'screen.\n$stack',
    );
    runApp(StartupFailureApp(
      title: appTitle,
      source: '$appModule.Startup/zone',
      cause: _firstLine(error.toString()),
      onRetry: launch,
    ));
    _watchFirstFrame();
  }

  void _watchFirstFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrameShown = true;
    });
  }
}

/// Minimal root used when the real app could not get a frame on screen.
/// Carries its own localizations so [StartupFailureView] can render
/// without anything from the failed app.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.title,
    required this.source,
    required this.cause,
    required this.onRetry,
  });

  final String title;
  final String source;
  final String cause;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(useMaterial3: true),
      home: StartupFailureView(
        source: source,
        cause: cause,
        onRetry: onRetry,
      ),
    );
  }
}

/// Non-blank replacement for the framework's error widget. It may be built
/// anywhere in the tree, including above `MaterialApp`, so it depends on
/// nothing but [Directionality] it provides itself.
class StartupErrorWidget extends StatelessWidget {
  const StartupErrorWidget({
    super.key,
    required this.appModule,
    required this.details,
  });

  final String appModule;
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final message = 'This part of the screen cannot be shown: '
        '$appModule.UI/render \u2014 '
        '${_firstLine(details.exceptionAsString())}. '
        'Reload the page to recover.';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFFDECEA),
        child: ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                message,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF7F1D1D),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _firstLine(String text) {
  final line = text.trim().split('\n').first.trim();
  return line.length <= 240 ? line : '${line.substring(0, 240)}...';
}
