import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/notechondria_shared.dart';
import 'package:notechondria_shared/src/components/local_folder_sign_in_option.dart';
import 'package:notechondria_shared/src/local_folder/qualification.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_harness.dart';
import 'folder_fixtures.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

LocalFolderController _browserLocal(MemoryFolderPlatform p) {
  final c = LocalFolderController.forTest(app: 'editor', platform: p);
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('AuthHub renders the option slot only when given (1.3)',
      (tester) async {
    Future<ActionFeedback> login(String e, String p) async =>
        const ActionFeedback(message: 'x');
    await tester.pumpWidget(_host(AuthHub(onLogin: login)));
    expect(find.text(kLocalFolderOptionLabel), findsNothing);
    final c = _browserLocal(MemoryFolderPlatform());
    await tester.pumpWidget(_host(AuthHub(
        onLogin: login, localFolderOption: LocalFolderSignInOption(controller: c))));
    expect(find.text(kLocalFolderOptionLabel), findsOneWidget);
  });

  testWidgets('an unqualified browser sees the option disabled with the gap',
      (tester) async {
    final c = _browserLocal(MemoryFolderPlatform());
    final q = evaluateLocalFolderSupport(const LocalFolderProbeInputs(
        hasDirectoryPicker: false,
        isSecureContext: true,
        hasPermissionApi: false,
        hasDirectoryIteration: true,
        hasWebLocks: true,
        userAgent: 'Mozilla/5.0 Firefox/130.0'));
    await tester.pumpWidget(
        _host(LocalFolderSignInOption(controller: c, qualification: q)));
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    expect(button.onPressed, isNull);
    expect(find.text(localFolderGapMessage(LocalFolderGap.noDirectoryPicker)),
        findsOneWidget);
    expect(find.text(kLocalFolderFallbackLine), findsOneWidget);
  });

  testWidgets('the notice opens first; Choose folder connects an empty folder',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final p = MemoryFolderPlatform();
    final picked = MemoryFolderFs(name: 'Fresh');
    p.picker.willReturn(picked);
    final c = _browserLocal(p);
    var connected = 0;
    await tester.pumpWidget(_host(LocalFolderSignInOption(
        controller: c, onConnected: () async => connected++)));
    await tester.tap(find.text(kLocalFolderOptionLabel));
    await tester.pumpAndSettle();
    expect(p.picker.calls, 0, reason: 'the first click only opens the notice');
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();
    expect(p.picker.calls, 1);
    await tester.tap(find.text('Start empty'));
    await tester.pumpAndSettle();
    expect(c.state, LocalFolderState.active);
    expect(c.storageMode, StorageMode.folder);
    expect(picked.exists('manifest.json'), isTrue);
    expect(connected, 1);
  });

  testWidgets('the status card shows the folder counts (F48)', (tester) async {
    late LocalFolderController c;
    await tester.runAsync(() async {
      (c, _) = await folderApp();
      await createNote(c);
      await c.rescan();
    });
    await tester.pumpWidget(_host(LocalFolderStatusCard(
        controller: c, onDisconnect: () async {}, cloudApiBaseUrl: kApiBase)));
    expect(find.textContaining('1 notes, 0 in the trash'), findsOneWidget);
    expect(find.text('Rescan folder'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    expect(find.text('Disconnect folder'), findsOneWidget);
  });

  testWidgets('the reconnect view offers the action of each pending state',
      (tester) async {
    late LocalFolderController c;
    await tester.runAsync(() async {
      final fs = await newNotechondriaFolder()..revoke();
      (c, _) = await folderApp(fs: fs);
    });
    await tester.pumpWidget(_host(LocalFolderReconnectView(
        controller: c, onUseBrowserLocal: () async {})));
    expect(c.state, LocalFolderState.needsPermission);
    expect(find.text("Reconnect 'Notes'"), findsOneWidget);
    expect(find.text('Use browser-local mode instead'), findsOneWidget);
    expect(find.text(LocalFolderMessages.needsPermission('Notes')), findsOneWidget);
  });
}
