import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

/// Copyable feedback (0.1.199): inline feedback, confirmation dialogs, the
/// load-error banner, and SnackBars render selectable text with a Copy
/// action that writes the full message to the clipboard. Bounded pumps
/// only (SnackBar and dialog timers).
Widget _localized(Widget child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

/// Captures `Clipboard.setData` calls; reset after the test.
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

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 250);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

const _message = 'Calendar not imported: Planner.Sync.Calendar/parse — '
    '"empty.ics" has no VEVENT entries with a readable DTSTART.';

void main() {
  testWidgets('FeedbackText is selectable and its Copy button copies it',
      (tester) async {
    final clipboard = _mockClipboard(tester);
    await tester.pumpWidget(_localized(const Scaffold(
      body: FeedbackText(
        feedback: ActionFeedback(message: _message, isError: true),
      ),
    )));
    expect(
        find.descendant(
            of: find.byType(SelectableText), matching: find.text(_message)),
        findsOneWidget);
    // Readable by assistive tech (a bare SelectableText is an empty text
    // field in web semantics).
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel(_message), findsOneWidget);
    semantics.dispose();
    final copy = find.byTooltip('Copy message');
    expect(copy, findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull);
    await tester.tap(copy);
    await tester.pump();
    expect(clipboard, [_message]);
    expect(find.byTooltip('Message copied to clipboard.'), findsOneWidget);
  });

  testWidgets('ConfirmWithDelayDialog text is selectable and copyable',
      (tester) async {
    final clipboard = _mockClipboard(tester);
    await tester.pumpWidget(_localized(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => const ConfirmWithDelayDialog(
              title: 'Restore local data?',
              message: 'Continuing will REPLACE your local drafts.',
            ),
          ),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SelectableText), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(clipboard, ['Continuing will REPLACE your local drafts.']);
    expect(find.text('Message copied to clipboard.'), findsOneWidget);
    // Let the 3s confirm delay run out, then close the dialog.
    await _pumpFor(tester, const Duration(seconds: 4));
    await tester.tap(find.text('Cancel'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(ConfirmWithDelayDialog), findsNothing);
  });

  testWidgets('LoadErrorBanner copy includes the raw cause', (tester) async {
    final clipboard = _mockClipboard(tester);
    const raw = 'Exception: Server request failed: Test.HTTP/request — client '
        'failed to fetch GET https://backend.test/api/v1/front-page/ before a '
        'response arrived (connection refused).';
    await tester.pumpWidget(_localized(Scaffold(
      body: LoadErrorBanner(
        message: raw,
        source: 'Test.Startup/initial_data',
        onRetry: () {},
        onDismiss: () {},
      ),
    )));
    await tester.tap(find.byTooltip('Copy message'));
    await tester.pump();
    expect(clipboard, hasLength(1));
    expect(clipboard.single, contains('Test.HTTP/request'));
    expect(clipboard.single, contains('(connection refused)'));
    expect(clipboard.single.split('\n'), hasLength(2));
  });

  testWidgets(
      'showCopyableSnackBar shows selectable text with a Copy action and '
      'still auto-dismisses', (tester) async {
    final clipboard = _mockClipboard(tester);
    await tester.pumpWidget(_localized(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCopyableSnackBar(context, _message),
          child: const Text('show'),
        ),
      ),
    )));
    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.descendant(
            of: find.byType(SnackBar), matching: find.byType(SelectableText)),
        findsOneWidget);
    expect(find.text(_message), findsOneWidget);
    final action = find.widgetWithText(SnackBarAction, 'Copy');
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pump();
    expect(clipboard, [_message]);
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Message copied to clipboard.'), findsOneWidget);
    // The confirmation SnackBar (2s) clears on its own as well.
    await _pumpFor(tester, const Duration(seconds: 4));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an untouched copyable SnackBar auto-dismisses after 6s',
      (tester) async {
    await tester.pumpWidget(_localized(Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCopyableSnackBar(context, _message),
          child: const Text('show'),
        ),
      ),
    )));
    await tester.tap(find.text('show'));
    await _pumpFor(tester, const Duration(seconds: 5));
    expect(find.byType(SnackBar), findsOneWidget);
    await _pumpFor(tester, const Duration(seconds: 3));
    expect(find.byType(SnackBar), findsNothing);
  });

  test('zh localizes the copy strings', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(zh.feedbackCopyMessage, '复制消息');
    expect(zh.feedbackMessageCopied, '消息已复制到剪贴板。');
    expect(zh.feedbackCopyFailed('denied'),
        '消息未复制：Shared.Feedback/copy — denied');
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.feedbackCopyFailed('denied'),
        'Message not copied: Shared.Feedback/copy — denied');
  });
}
