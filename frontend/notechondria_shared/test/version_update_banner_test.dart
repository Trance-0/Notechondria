import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

Widget _host(Locale locale, VersionUpdateBanner banner) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: banner),
    );

void main() {
  testWidgets('shows localized update banner when backend is newer',
      (tester) async {
    await tester.pumpWidget(_host(
      const Locale('en'),
      VersionUpdateBanner(
        frontendVersion: '0.1.151',
        probe: () async =>
            const BackendVersionInfo(version: '0.1.200'),
        onRefresh: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('A new version is available. Refresh to update.'),
        findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    // unmount to cancel the banner's periodic timer
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('update banner localizes to zh', (tester) async {
    await tester.pumpWidget(_host(
      const Locale('zh'),
      VersionUpdateBanner(
        frontendVersion: '0.1.151',
        probe: () async =>
            const BackendVersionInfo(version: '0.1.200'),
        onRefresh: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('有新版本可用。刷新以更新。'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('renders nothing when up to date / backend unreachable',
      (tester) async {
    await tester.pumpWidget(_host(
      const Locale('en'),
      VersionUpdateBanner(
        frontendVersion: '0.1.151',
        probe: () async => null, // offline
        onRefresh: () {},
      ),
    ));
    await tester.pumpAndSettle();
    // Banner renders an empty SizedBox — no Refresh action, no message.
    expect(find.text('Refresh'), findsNothing);
    expect(find.byIcon(Icons.system_update_alt_outlined), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unsupported (below floor) shows update-required, no dismiss',
      (tester) async {
    await tester.pumpWidget(_host(
      const Locale('en'),
      VersionUpdateBanner(
        frontendVersion: '0.1.139',
        probe: () async => const BackendVersionInfo(
            version: '0.1.139', minFrontendVersion: '0.1.140'),
        onRefresh: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.text('This app version is no longer supported. Refresh to update.'),
        findsOneWidget);
    // hard banner is not dismissible
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
