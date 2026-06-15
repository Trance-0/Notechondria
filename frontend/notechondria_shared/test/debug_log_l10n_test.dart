import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

Widget _host(Locale locale) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: DebugLogCard(
          controller: DebugLogController(),
          title: 'ignored',
          summary: 'summary',
        ),
      ),
    );

void main() {
  testWidgets('debug log chrome is English under en', (tester) async {
    await tester.pumpWidget(_host(const Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Copy logs'), findsOneWidget);
    expect(find.text('No frontend logs captured yet.'), findsOneWidget);
  });

  testWidgets('debug log chrome switches to Chinese under zh', (tester) async {
    await tester.pumpWidget(_host(const Locale('zh')));
    await tester.pumpAndSettle();
    // The menu chrome is localized; the actual log lines (none here)
    // would stay English.
    expect(find.text('复制日志'), findsOneWidget); // Copy logs
    expect(find.text('尚未捕获前端日志。'), findsOneWidget); // empty state
    expect(find.text('Copy logs'), findsNothing);
  });

  test('zh AppLocalizations resolves translated keys', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(zh.settingsLanguage, '语言');
    expect(zh.settingsEditorTitle, '编辑器设置');
    expect(zh.debugCopyLogs, '复制日志');
  });
}
