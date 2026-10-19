import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notechondria_shared/local_folder_testing.dart';
import 'package:notechondria_shared/src/app_shell/app_shell_session_mixin.dart';
import 'package:notechondria_shared/src/app_shell/auth_client.dart';
import 'package:notechondria_shared/src/components/debug_log.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_boot.dart';
import 'package:notechondria_shared/src/local_folder/local_folder_controller.dart';
import 'package:notechondria_shared/src/models/action_feedback.dart';
import 'package:notechondria_shared/src/startup/startup_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_harness.dart';
import 'folder_fixtures.dart';

// The folder branches of the session mixin and the `prepare` hook of
// runGuardedApp (phase 1b review P1B-5). They are inert until an app's
// wiring phase returns a controller from `localFolder`, so these tests
// drive them through a minimal shell.

/// Records the calls the mixin makes; any call not listed here is recorded
/// by name and fails.
class _AuthClient implements AuthClient {
  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> getSettings(String token) async {
    calls.add('getSettings');
    return {'username': 'local-folder', 'editor_mode': 'P'};
  }

  @override
  Future<Map<String, dynamic>> updateSettings(
      String token, Map<String, dynamic> payload) async {
    calls.add('updateSettings');
    return {};
  }

  @override
  Future<void> logout(String token) async => calls.add('logout');

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _Shell extends StatefulWidget {
  const _Shell({super.key, required this.folder, required this.auth});
  final LocalFolderController? folder;
  final _AuthClient auth;
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with AppShellSessionMixin<_Shell> {
  String? _token;
  LocalFolderState? folderStateWhenCleared;
  final List<String> events = [];
  final List<String> messages = [];
  final List<Map<String, dynamic>> applied = [];

  @override
  String? get token => _token;
  @override
  set token(String? value) {
    if (value == null) folderStateWhenCleared = widget.folder?.state;
    _token = value;
  }

  @override
  Map<String, dynamic>? profile;
  @override
  Map<String, dynamic>? settings;
  @override
  final Map<String, dynamic> localSettings = {};
  @override
  List<Map<String, dynamic>> deletedNotes = [];
  @override
  String get logAppTag => 'Editor';
  @override
  AuthClient get authClient => widget.auth;
  @override
  LocalFolderController? get localFolder => widget.folder;

  @override
  Map<String, dynamic> currentAppSettingsPayload(
          {String? themePreset, String? themeMode, String? apiBaseUrl}) =>
      {};
  @override
  Future<void> applyLocalAppSettings(Map<String, dynamic> settings,
      {bool persist = true}) async {
    applied.add(settings);
    localSettings.addAll(settings);
  }

  @override
  Future<void> loadInitialData() async => events.add('loadInitialData');
  @override
  Future<void> syncAllLocalCourses() async {}
  @override
  Future<void> syncAllLocalDrafts() async {}
  @override
  Future<void> persistSession(String token, Map<String, dynamic> user) async =>
      events.add('persistSession');
  @override
  Future<void> clearPersistedSession() async =>
      events.add('clearPersistedSession');
  @override
  void refreshState() {}
  @override
  void log({
    required String message,
    DebugLogLevel level = DebugLogLevel.info,
    String source = '',
    int? durationMs,
  }) {}
  @override
  void showMessage(String message) => messages.add(message);
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Future<_ShellState> _pumpShell(
    WidgetTester tester, LocalFolderController? folder, _AuthClient auth) async {
  // A new key per pump, so every shell gets a fresh State.
  await tester.pumpWidget(_Shell(key: UniqueKey(), folder: folder, auth: auth));
  return tester.state<_ShellState>(find.byType(_Shell));
}

bool _stampsOwner(List<Map<String, dynamic>> applied) =>
    applied.any((s) => s.containsKey('local_data_owner'));

void main() {
  group('session mixin folder branches (2.7, 2.10)', () {
    testWidgets('a folder payload persists no session and stamps no owner',
        (tester) async {
      final (folder, _) = (await tester.runAsync(() => folderApp()))!;
      final auth = _AuthClient();
      final shell = await _pumpShell(tester, folder, auth);
      await tester.runAsync(() => shell.applyAuthPayload({
            'token': 'local-folder',
            'user': {'username': 'local-folder', 'is_local_folder': true},
          }));
      expect(shell.token, 'local-folder');
      expect(shell.events, isNot(contains('persistSession')));
      expect(_stampsOwner(shell.applied), isFalse);
      expect(shell.messages.last, LocalFolderMessages.folderSessionStarted('Notes'));

      // The same flow for a cloud account does both, so the branch matters.
      final cloud = await _pumpShell(tester, null, _AuthClient());
      await tester.runAsync(() => cloud.applyAuthPayload({
            'token': 'abc',
            'user': {'username': 'alice'},
          }));
      expect(cloud.events, contains('persistSession'));
      expect(_stampsOwner(cloud.applied), isTrue);
    });

    testWidgets('logout of a folder session disconnects, never the cloud',
        (tester) async {
      final platform = MemoryFolderPlatform();
      final (folder, _) =
          (await tester.runAsync(() => folderApp(platform: platform)))!;
      final auth = _AuthClient();
      final shell = await _pumpShell(tester, folder, auth)
        ..token = 'local-folder'
        ..profile = {'username': 'local-folder', 'is_local_folder': true};
      await tester.runAsync(shell.logout);
      expect(auth.calls, isEmpty);
      expect(shell.events, ['loadInitialData']);
      expect(shell.token, isNull);
      expect(shell.profile, isNull);
      // 2.10 rule 4: the folder state changes before the session is cleared.
      expect(shell.folderStateWhenCleared, LocalFolderState.disconnected);
      expect(folder.storageMode, StorageMode.browserOrCloud);
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      expect(prefs.containsKey(kSharedStorageModeKey), isFalse);
      expect(platform.handleStore.records.containsKey(kTestFolderId), isFalse);
      expect(shell.messages.last, LocalFolderMessages.folderDisconnected('Notes'));
    });

    testWidgets('cloudOnly and cloudOnlyAction gate only folder mode',
        (tester) async {
      final (folder, _) = (await tester.runAsync(() => folderApp()))!;
      final recorder = RecordingClient();
      var runs = 0;
      Future<ActionFeedback> restore() async {
        runs++;
        await http.Client().post(Uri.parse('$kApiBase/admin/template-courses/restore/'));
        return const ActionFeedback(message: 'restored');
      }

      final shell = await _pumpShell(tester, folder, _AuthClient());
      expect(shell.cloudOnly('GitHub card'), isNull);
      final gated = (await tester.runAsync(() => http.runWithClient(
          shell.cloudOnlyAction(restore, LocalFolderMessages.templateCoursesNotRestored),
          () => recorder)))!;
      expect(gated.message, LocalFolderMessages.templateCoursesNotRestored);
      expect(gated.isError, isTrue);
      expect(runs, 0);
      expect(recorder.requests, isEmpty);

      final cloud = await _pumpShell(tester, null, _AuthClient());
      expect(cloud.cloudOnly('GitHub card'), 'GitHub card');
      final sent = (await tester.runAsync(() => http.runWithClient(
          cloud.cloudOnlyAction(restore, LocalFolderMessages.templateCoursesNotRestored),
          () => recorder)))!;
      expect(sent.message, 'restored');
      expect(runs, 1);
      expect(recorder.requests, hasLength(1));
    });
  });

  testWidgets('a throwing prepare shows the startup fallback (2.8)',
      (tester) async {
    final previousBuilder = ErrorWidget.builder;
    final previousOnError = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    var built = 0;
    try {
      runGuardedApp(
        appModule: 'Test',
        appTitle: 'Test App',
        buildApp: () {
          built++;
          return const Text('real app', textDirection: TextDirection.ltr);
        },
        prepare: () async => throw StateError('preload boom'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Test.Startup/zone'), findsOneWidget);
      expect(find.textContaining('preload boom'), findsOneWidget);
      expect(built, 0);
    } finally {
      ErrorWidget.builder = previousBuilder;
      FlutterError.onError = previousOnError;
      PlatformDispatcher.instance.onError = previousPlatform;
    }
  });
}
