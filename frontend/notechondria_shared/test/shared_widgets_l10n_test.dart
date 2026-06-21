import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

/// Phase-4 shared-widget i18n: the StorageUsageCard and ErrorStateView
/// chrome localize with the app locale. Verifies en vs zh rendering so a
/// future refactor can't silently re-hardcode the strings.
Widget _host(Locale locale, Widget child) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('StorageUsageCard renders English chrome under en',
      (tester) async {
    await tester.pumpWidget(_host(
      const Locale('en'),
      const StorageUsageCard(
        backendHost: 'example.com',
        bucketSizes: {'Settings': 1024},
        attachmentBytes: 0,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Storage usage'), findsOneWidget);
    expect(find.text('Breakdown'), findsOneWidget);
  });

  testWidgets('StorageUsageCard renders Chinese chrome under zh',
      (tester) async {
    await tester.pumpWidget(_host(
      const Locale('zh'),
      const StorageUsageCard(
        backendHost: 'example.com',
        bucketSizes: {'Settings': 1024},
        attachmentBytes: 0,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('存储用量'), findsOneWidget); // Storage usage
    expect(find.text('明细'), findsOneWidget); // Breakdown
    expect(find.text('Storage usage'), findsNothing);
  });

  testWidgets('ErrorStateView retry button localizes to zh', (tester) async {
    await tester.pumpWidget(_host(
      const Locale('zh'),
      ErrorStateView(message: '错误', onRetry: () async {}),
    ));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget); // Retry
    expect(find.text('Retry'), findsNothing);
  });
}
