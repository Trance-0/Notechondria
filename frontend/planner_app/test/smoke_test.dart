import 'dart:async';
import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notechondria_shared/notechondria_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:planner_app/main.dart' as app;

import 'local_folder_smoke.dart';

/// Fake backend for the startup-fallback tests: never answers (an
/// unresponsive server), refuses every connection, or answers every
/// request with empty data plus a valid handshake. Signed-in calendar
/// tests also use its login answer, its 7-day activity week, and the
/// recorded calendar-feed POSTs ([failCalendarUpload] refuses those;
/// [failCalendarRefresh] refuses the feed-list GET).
class _Backend {
  bool hang = true;
  bool refuse = false;
  bool failCalendarUpload = false;
  bool failCalendarRefresh = false;
  int requests = 0;
  int handshakes = 0;
  final calendarPosts = <Map<String, dynamic>>[];

  static Future<http.Response> _json(Object body, [int status = 200]) =>
      Future.value(http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'}));

  Future<http.Response> handle(http.Request request) {
    requests++;
    if (refuse) {
      return Future.error(
          http.ClientException('Connection refused', request.url));
    }
    if (hang) return Completer<http.Response>().future;
    final path = request.url.path;
    final isGet = request.method == 'GET';
    if (path.endsWith('/auth/login/')) {
      return _json({
        'token': _testToken,
        'user': {'username': 'phase1'},
      });
    }
    if (path.endsWith('/calendar-feeds/') && !isGet) {
      calendarPosts
          .add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
      if (failCalendarUpload) {
        return Future.error(
            http.ClientException('Connection refused', request.url));
      }
      return _json({'id': 7, 'title': 'Phase1 Test Calendar'}, 201);
    }
    if (path.endsWith('/calendar-feeds/') && failCalendarRefresh) {
      return Future.error(
          http.ClientException('Connection refused', request.url));
    }
    if (path.endsWith('/activity/week/')) {
      final today = DateTime.now();
      return _json({
        'days': [
          for (var i = 0; i < 7; i++)
            {
              'date': today
                  .add(Duration(days: i))
                  .toIso8601String()
                  .split('T')
                  .first,
              'events': <Object>[],
            },
        ],
        'deadlines': <Object>[],
      });
    }
    if (path.endsWith('/handshake/')) {
      handshakes++;
      // 0.1.21 = the test build's APP_VERSION, so no update banner.
      return Future.value(http.Response(
          jsonEncode({
            'service': 'notechondria-backend',
            'api_version': 'v1',
            'version': '0.1.21',
            'min_frontend_version': '',
          }),
          200,
          headers: {'content-type': 'application/json'}));
    }
    final isList = isGet &&
        (path.endsWith('/courses/') ||
            path.endsWith('/activity/') ||
            path.endsWith('/planner-events/') ||
            path.endsWith('/calendar-feeds/') ||
            path.endsWith('/notes/deleted/'));
    return Future.value(http.Response(isList ? '[]' : '{}', 200,
        headers: {'content-type': 'application/json'}));
  }
}

/// A 40-character DRF-shaped token for the signed-in tests.
const _testToken = '0123456789abcdef0123456789abcdef01234567';

/// File picker stand-in for the iCal import (the real one opens a native
/// dialog). On the VM an `XFile.fromData` takes its name from `path`.
class _FakeFileSelector extends FileSelectorPlatform {
  XFile? next;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      next;
}

_FakeFileSelector _installFakeFileSelector() {
  final original = FileSelectorPlatform.instance;
  final fake = _FakeFileSelector();
  FileSelectorPlatform.instance = fake;
  addTearDown(() => FileSelectorPlatform.instance = original);
  return fake;
}

/// Captures `Clipboard.setData`; reset after the test.
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

/// First-run overlays (tour, what's new) would cover the shell.
Map<String, Object> _seenFirstRun([Map<String, Object> extra = const {}]) => {
      'notechondria.planner.local_stats':
          jsonEncode({'onboarding_seen': true, 'install_hint_dismissed': true}),
      ...extra,
    };

Future<void> _pumpPlanner(WidgetTester tester, _Backend backend,
    {int initialIndex = 1}) {
  return tester.pumpWidget(app.NotechondriaApp(
    client: app.HttpNotechondriaClient(httpClient: MockClient(backend.handle)),
    initialIndex: initialIndex,
    title: 'Notechondria Planner',
    visibleIndices: const <int>[0, 1, 2, 3],
  ));
}

Future<void> _pumpSeconds(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _pumpShort(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

/// A one-event calendar for tomorrow 10:00-11:00 device-local time (always
/// inside the offline week, which starts today), or an empty calendar.
String _ics({bool withEvent = true}) {
  final day = DateTime.now().add(const Duration(days: 1));
  final date = '${day.year}${_two(day.month)}${_two(day.day)}';
  return 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//phase1//EN\r\n'
      'X-WR-CALNAME:Phase1 Test Calendar\r\n'
      '${withEvent ? 'BEGIN:VEVENT\r\nUID:phase1-1\r\nSUMMARY:Phase1 Lecture\r\n'
          'DTSTART:${date}T100000\r\nDTEND:${date}T110000\r\nEND:VEVENT\r\n' : ''}'
      'END:VCALENDAR\r\n';
}

/// Opens the activity FAB's secondary menu: right-click first, long press
/// as the fallback.
Future<void> _openFabMenu(WidgetTester tester) async {
  final fab = find.byType(FloatingActionButton);
  expect(fab, findsOneWidget);
  await tester.tapAt(tester.getCenter(fab),
      buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
  await _pumpShort(tester);
  if (find.text('Import iCal').evaluate().isEmpty) {
    await tester.longPress(fab);
    await _pumpShort(tester);
  }
  expect(find.text('Import iCal'), findsOneWidget);
}

/// Signs in through Settings > "Use email / password instead" > Login,
/// then opens the Activity tab. The planner keeps its session in memory
/// only, so a test cannot seed one in storage.
Future<void> _signInThenOpenActivity(WidgetTester tester) async {
  expect(find.byType(SplashScreen), findsNothing);
  final expander = find.text('Use email / password instead');
  await tester.ensureVisible(expander);
  await tester.pump();
  await tester.tap(expander);
  await _pumpShort(tester);
  final open = find.widgetWithText(OutlinedButton, 'Login');
  await tester.ensureVisible(open);
  await tester.pump();
  await tester.tap(open);
  await _pumpShort(tester);
  final dialog = find.byType(AlertDialog);
  await tester.enterText(
      find.descendant(
          of: dialog,
          matching: find.widgetWithText(TextField, 'Email or username')),
      'phase1');
  await tester.enterText(
      find.descendant(
          of: dialog, matching: find.widgetWithText(TextField, 'Password')),
      'phase1-password');
  await tester.tap(find.descendant(
      of: dialog, matching: find.widgetWithText(FilledButton, 'Login')));
  await _pumpSeconds(tester, 2);
  expect(find.byType(AlertDialog), findsNothing);
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text('Activity')));
  await _pumpSeconds(tester, 1);
}

/// Bounded wait for [finder]: a SnackBar queues behind earlier ones (the
/// "Signed in as ..." message).
Future<bool> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  return finder.evaluate().isNotEmpty;
}

/// Imports the one-event calendar through the activity FAB menu.
Future<void> _importPhase1Calendar(WidgetTester tester) async {
  await _openFabMenu(tester);
  await tester.tap(find.text('Import iCal'));
  await _pumpShort(tester);
  expect(find.text('1 event parsed'), findsOneWidget);
  await tester.tap(find.text('Confirm import'));
  await _pumpShort(tester);
  expect(find.text('Review calendar import'), findsNothing);
}

void main() {
  testWidgets('planner app boots with starter offline content', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // main() installs the startup ErrorWidget.builder; flutter_test
    // requires it restored before the test body ends.
    final errorWidgetBuilder = ErrorWidget.builder;
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Starter planning course'), findsWidgets);
    ErrorWidget.builder = errorWidgetBuilder;
  });

  group('startup fallbacks (0.1.198)', () {
    testWidgets(
        'unresponsive backend shows the backend-unavailable banner over '
        'local planner data, and Retry recovers', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend();
      await _pumpPlanner(tester, backend);
      await _pumpSeconds(tester, 12);
      // Not blank: the local starter course still renders.
      expect(find.text('Starter planning course'), findsWidgets);
      final banner = find.byType(LoadErrorBanner);
      expect(banner, findsOneWidget);
      expect(
          find.descendant(
              of: banner,
              matching: find.textContaining(
                  'Planner.Startup/bootstrap — the server did not respond '
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
        'notechondria.planner.local_cache':
            jsonEncode({'courses': 'corrupt'}),
      }));
      final backend = _Backend()..hang = false;
      await _pumpPlanner(tester, backend);
      await _pumpSeconds(tester, 1);
      expect(find.text('The app could not finish starting'), findsOneWidget);
      expect(find.textContaining('Planner.Startup/bootstrap'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Continue anyway'));
      await _pumpSeconds(tester, 1);
      expect(find.text('The app could not finish starting'), findsNothing);
    });
  });

  group('offline calendar import (0.1.199)', () {
    test('the shared iCal reader parses what the planner imports', () {
      final parsed = parseIcalEvents(_ics());
      expect(parsed.calendarName, 'Phase1 Test Calendar');
      expect(parsed.events, hasLength(1));
      expect(parsed.events.single.summary, 'Phase1 Lecture');
      expect(parsed.events.single.start.hour, 10);
      expect(parsed.events.single.end.hour, 11);
      expect(parseIcalEvents(_ics(withEvent: false)).events, isEmpty);
      final folded = parseIcalEvents('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\n'
          'SUMMARY:Split\r\n  title\r\nDTSTART;VALUE=DATE:20261101\r\n'
          'BEGIN:VALARM\r\nDESCRIPTION:alarm\r\nEND:VALARM\r\n'
          'END:VEVENT\r\nBEGIN:VEVENT\r\nSUMMARY:No start\r\nEND:VEVENT\r\n'
          'END:VCALENDAR\r\n');
      expect(folded.events.single.summary, 'Split title');
      expect(folded.events.single.allDay, isTrue);
      expect(folded.events.single.description, isEmpty);
      expect(folded.skipped, 1);
    });

    testWidgets(
        'signed out with the backend refusing connections, an .ics import '
        'succeeds on the device and survives a reload', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend()
        ..hang = false
        ..refuse = true;
      final picker = _installFakeFileSelector()
        ..next = XFile.fromData(utf8.encode(_ics()),
            name: 'phase1.ics', path: 'phase1.ics');
      await _pumpPlanner(tester, backend, initialIndex: 2);
      await _pumpSeconds(tester, 2);

      await _openFabMenu(tester);
      await tester.tap(find.text('Import iCal'));
      await _pumpShort(tester);
      expect(find.text('Review calendar import'), findsOneWidget);
      expect(find.text('1 event parsed'), findsOneWidget);
      await tester.tap(find.text('Confirm import'));
      await _pumpShort(tester);

      expect(find.text('Review calendar import'), findsNothing);
      expect(find.textContaining('no cloud session'), findsNothing);
      expect(find.textContaining('Import failed'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(SnackBar),
              matching: find.textContaining('Calendar saved on this device: '
                  'Planner.Sync.Calendar/import')),
          findsOneWidget);
      expect(find.text('Phase1 Lecture'), findsOneWidget);
      expect(find.textContaining('Calendar this week (1)'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(
              prefs.getString('notechondria.planner.local_calendar_feeds')!)
          as List<dynamic>;
      expect(stored, hasLength(1));
      final feed = stored.single as Map<String, dynamic>;
      expect(feed['is_local_feed'], isTrue);
      expect(feed['title'], 'Phase1 Test Calendar');
      expect(feed['source_file'], 'phase1.ics');
      expect(feed['events'] as List<dynamic>, hasLength(1));
      picker.next = null;

      // Reload: a fresh app on the same (in-memory) browser storage.
      await _pumpSeconds(tester, 7);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPlanner(tester, backend, initialIndex: 2);
      await _pumpSeconds(tester, 2);
      expect(find.text('Phase1 Lecture'), findsOneWidget);
      await _pumpSeconds(tester, 10);
    });

    testWidgets(
        'an unreadable calendar keeps the dialog open with a selectable, '
        'copyable 1.8 message', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final clipboard = _mockClipboard(tester);
      final backend = _Backend()
        ..hang = false
        ..refuse = true;
      _installFakeFileSelector().next = XFile.fromData(
          utf8.encode(_ics(withEvent: false)),
          name: 'empty.ics',
          path: 'empty.ics');
      await _pumpPlanner(tester, backend, initialIndex: 2);
      await _pumpSeconds(tester, 2);

      await _openFabMenu(tester);
      await tester.tap(find.text('Import iCal'));
      await _pumpShort(tester);
      expect(find.text('0 events parsed'), findsOneWidget);
      await tester.tap(find.text('Confirm import'));
      await _pumpShort(tester);

      const expected = 'Calendar not imported: Planner.Sync.Calendar/parse — '
          '"empty.ics" has no VEVENT entries with a readable DTSTART.';
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
          find.descendant(
              of: find.descendant(
                  of: dialog, matching: find.byType(SelectableText)),
              matching: find.text(expected)),
          findsOneWidget);
      final copy = find.descendant(
          of: dialog, matching: find.byTooltip('Copy message'));
      expect(copy, findsOneWidget);
      expect(
          tester
              .widget<IconButton>(
                  find.ancestor(of: copy, matching: find.byType(IconButton)))
              .onPressed,
          isNotNull);
      await tester.tap(copy);
      await tester.pump();
      expect(clipboard, [expected]);
      expect(find.text('Import failed'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await _pumpSeconds(tester, 10);
    });

    testWidgets(
        'signed-out subscribe explains the cloud-only URL case inline',
        (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend()
        ..hang = false
        ..refuse = true;
      await _pumpPlanner(tester, backend, initialIndex: 2);
      await _pumpSeconds(tester, 2);

      await _openFabMenu(tester);
      await tester.tap(find.text('Subscribe calendar'));
      await _pumpShort(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'iCal URL or Google share link'),
          'https://calendar.example.test/basic.ics');
      await tester.tap(find.text('Subscribe'));
      await _pumpShort(tester);

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      final inline = find.descendant(
          of: dialog,
          matching: find.textContaining('Calendar not subscribed: '
              'Planner.Sync.Calendar/subscribe'));
      expect(inline, findsOneWidget);
      expect(
          find.descendant(of: dialog, matching: find.textContaining('Import iCal')),
          findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await _pumpSeconds(tester, 10);
    });

    testWidgets(
        'signed in and online, an .ics import is uploaded with its raw '
        'iCal and nothing is stored locally', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend()..hang = false;
      _installFakeFileSelector().next = XFile.fromData(utf8.encode(_ics()),
          name: 'phase1.ics', path: 'phase1.ics');
      await _pumpPlanner(tester, backend, initialIndex: 3);
      await _pumpSeconds(tester, 3);
      await _signInThenOpenActivity(tester);

      await _importPhase1Calendar(tester);
      expect(backend.calendarPosts, hasLength(1));
      final post = backend.calendarPosts.single;
      expect(post['source_kind'], 'I');
      expect(post['title'], 'Phase1 Test Calendar');
      expect(post['raw_ical'], contains('SUMMARY:Phase1 Lecture'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('notechondria.planner.local_calendar_feeds'),
          isNull);
      expect(
          await _pumpUntilFound(
              tester,
              find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.textContaining('Calendar imported: '
                      'Planner.Sync.Calendar/push — "Phase1 Test Calendar" '
                      '(1 event) added to your cloud calendars.'))),
          isTrue);
      await _pumpSeconds(tester, 8);
    });

    testWidgets(
        'signed in with the upload refused, the import is kept on the '
        'device and announced as a warning with the cause', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend()
        ..hang = false
        ..failCalendarUpload = true;
      _installFakeFileSelector().next = XFile.fromData(utf8.encode(_ics()),
          name: 'phase1.ics', path: 'phase1.ics');
      await _pumpPlanner(tester, backend, initialIndex: 3);
      await _pumpSeconds(tester, 3);
      await _signInThenOpenActivity(tester);

      await _importPhase1Calendar(tester);
      expect(backend.calendarPosts, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      final stored = jsonDecode(
              prefs.getString('notechondria.planner.local_calendar_feeds')!)
          as List<dynamic>;
      expect(stored, hasLength(1));
      expect((stored.single as Map)['is_local_feed'], isTrue);
      // The signed-in week shows the local event too.
      expect(find.text('Phase1 Lecture'), findsOneWidget);

      final warning = find.descendant(
          of: find.byType(SnackBar),
          matching: find.textContaining('Calendar saved on this device: '
              'Planner.Sync.Calendar/import — "Phase1 Test Calendar" '
              '(1 event) is stored locally because the cloud upload failed '
              '(connection refused); it is not uploaded to the cloud.'));
      expect(await _pumpUntilFound(tester, warning), isTrue);
      // Shown like an error (10s), not as a 6s success message.
      expect(
          tester
              .widget<SnackBar>(
                  find.ancestor(of: warning, matching: find.byType(SnackBar)))
              .duration,
          const Duration(seconds: 10));

      final logs = (jsonDecode(prefs.getString('notechondria.planner.local_logs')!)
              as List<dynamic>)
          .cast<String>();
      final push = logs.where((l) => l.contains('Planner.Sync.Calendar/push'));
      expect(push, hasLength(1), reason: logs.join('\n'));
      // The redacted cause, not the raw exception text with the URL.
      expect(
          push.single,
          contains('Calendar saved on this device only: '
              'Planner.Sync.Calendar/push — cloud upload failed '
              '(connection refused).'));
      expect(push.single, isNot(contains('Server request failed')));
      await _pumpSeconds(tester, 11);
    });

    testWidgets(
        'signed in, a subscribe whose create succeeds but whose refresh '
        'fails closes as a success after exactly one create call',
        (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend()..hang = false;
      await _pumpPlanner(tester, backend, initialIndex: 3);
      await _pumpSeconds(tester, 3);
      await _signInThenOpenActivity(tester);

      backend.failCalendarRefresh = true;
      const url = 'https://calendar.example.test/basic.ics';
      await _openFabMenu(tester);
      await tester.tap(find.text('Subscribe calendar'));
      await _pumpShort(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'iCal URL or Google share link'),
          url);
      await tester.tap(find.text('Subscribe'));
      await _pumpShort(tester);

      // Closed as a success, so there is no retry that would register a
      // second server-side feed.
      expect(find.text('Subscribe to calendar'), findsNothing);
      expect(find.textContaining('Calendar not subscribed'), findsNothing);
      expect(backend.calendarPosts, hasLength(1));
      expect(backend.calendarPosts.single['source_kind'], 'S');
      expect(backend.calendarPosts.single['source_url'], url);
      expect(
          await _pumpUntilFound(
              tester,
              find.descendant(
                  of: find.byType(SnackBar),
                  matching: find.textContaining('Calendar subscribed: '
                      'Planner.Sync.Calendar/subscribe — "Subscribed '
                      'calendar" feed URL registered.'))),
          isTrue);

      final prefs = await SharedPreferences.getInstance();
      final logs = (jsonDecode(prefs.getString('notechondria.planner.local_logs')!)
              as List<dynamic>)
          .cast<String>();
      final refresh =
          logs.where((l) => l.contains('Calendar list not refreshed'));
      expect(refresh, hasLength(1), reason: logs.join('\n'));
      expect(
          refresh.single,
          contains('Calendar list not refreshed: '
              'Planner.Sync.Calendar/refresh — connection refused; the '
              'subscription itself succeeded.'));
      await _pumpSeconds(tester, 8);
    });
  });
  group('startup logs and loading surface (0.1.199)', () {
    testWidgets(
        'a hanging backend: one loading surface at a time, then startup '
        'records with durations and the timeout cause', (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final clipboard = _mockClipboard(tester);
      final backend = _Backend();
      await _pumpPlanner(tester, backend);
      var sawStepStatus = false;
      for (var i = 0; i < 48; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final surfaces = find.byType(SplashScreen).evaluate().length +
            find.byType(CircularProgressIndicator).evaluate().length +
            find.byType(LinearProgressIndicator).evaluate().length;
        expect(surfaces, lessThanOrEqualTo(1), reason: 'frame $i');
        if (find
            .descendant(
                of: find.byType(SplashScreen),
                matching: find.textContaining('Planner.Startup/'))
            .evaluate()
            .isNotEmpty) {
          sawStepStatus = true;
        }
      }
      expect(sawStepStatus, isTrue);
      expect(find.byType(SplashScreen), findsNothing);
      final banner = find.byType(LoadErrorBanner);
      expect(banner, findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final logs = (jsonDecode(prefs.getString('notechondria.planner.local_logs')!)
              as List<dynamic>)
          .cast<String>();
      bool has(String pattern) => logs.any((l) => l.contains(pattern));
      expect(has('Planner.Startup/local_state'), isTrue);
      expect(has('API base resolved: Planner.Startup/config'), isTrue);
      expect(
          logs.any((l) =>
              l.contains('Backend not reachable: Planner.Startup/handshake') &&
              l.contains('timeout after 10s')),
          isTrue,
          reason: logs.join('\n'));
      expect(has('Planner.Startup/initial_data'), isTrue);
      expect(
          logs.any((l) =>
              l.contains('Planner.HTTP/request_failed') &&
              l.contains('ms: ')),
          isTrue);
      for (final step in [
        'local_state',
        'handshake',
        'oauth_callback',
        'initial_data'
      ]) {
        expect(
            logs.any((l) =>
                l.contains('] Planner.Startup/$step — ') &&
                !l.contains('Startup step started') &&
                l.endsWith('ms)')),
            isTrue,
            reason: 'outcome line with duration for $step');
      }

      await tester.tap(
          find.descendant(of: banner, matching: find.byTooltip('Copy message')));
      await tester.pump();
      expect(clipboard, hasLength(1));
      expect(clipboard.single, contains('Planner.Startup/bootstrap'));
      await _pumpSeconds(tester, 8);
    });

    testWidgets('a responsive backend logs the reachable handshake',
        (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend()..hang = false;
      await _pumpPlanner(tester, backend);
      await _pumpSeconds(tester, 3);
      expect(find.byType(SplashScreen), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final logs = prefs.getString('notechondria.planner.local_logs')!;
      expect(logs, contains('Backend reachable: Planner.Startup/handshake'));
      // The version banner reuses the startup handshake (also after the
      // splash closes and the banner is rebuilt).
      expect(backend.handshakes, 1);
      expect(logs, contains('notechondria-backend v0.1.21'));
      expect(logs, contains('No saved session: Planner.Startup/session_restore'));
      expect(logs, contains('Startup step finished: '
          'Planner.Startup/initial_data — every cloud request answered.'));
      expect(find.byType(VersionUpdateBanner), findsOneWidget);
      expect(find.textContaining('A new version is available'), findsNothing);
    });

    testWidgets(
        'a refused backend: the initial_data outcome reports the fallback',
        (tester) async {
      SharedPreferences.setMockInitialValues(_seenFirstRun());
      final backend = _Backend()
        ..hang = false
        ..refuse = true;
      await _pumpPlanner(tester, backend);
      await _pumpSeconds(tester, 3);
      final prefs = await SharedPreferences.getInstance();
      final logs = (jsonDecode(prefs.getString('notechondria.planner.local_logs')!)
              as List<dynamic>)
          .cast<String>();
      final outcome = logs.where((l) =>
          l.contains('] Planner.Startup/initial_data — ') && l.endsWith('ms)'));
      expect(outcome, hasLength(1), reason: logs.join('\n'));
      expect(
          outcome.single,
          contains('[W] Planner.Startup/initial_data — Startup finished '
              'on local data only: Planner.Startup/initial_data — '));
      expect(logs.any((l) => l.contains('Startup step finished: '
          'Planner.Startup/initial_data — done.')), isFalse);
      await _pumpSeconds(tester, 8);
    });

    testWidgets(
        'a start that fails while loading local data still persists its '
        'log lines next to the earlier history', (tester) async {
      const earlier = '[2026-10-15T10:00:00.000Z] [I] Planner.UI/feedback '
          '— Earlier session line: Planner.UI/feedback — kept.';
      // A corrupt cached value makes _loadLocalState throw right after
      // the store load.
      SharedPreferences.setMockInitialValues(_seenFirstRun({
        'notechondria.planner.local_cache':
            jsonEncode({'planner_events': 'corrupt'}),
        'notechondria.planner.local_logs': jsonEncode([earlier]),
      }));
      final backend = _Backend()..hang = false;
      await _pumpPlanner(tester, backend);
      await _pumpSeconds(tester, 1);
      expect(find.text('The app could not finish starting'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final logs = (jsonDecode(prefs.getString('notechondria.planner.local_logs')!)
              as List<dynamic>)
          .cast<String>();
      expect(logs, contains(earlier));
      expect(
          logs.any((l) => l.contains(
              'Local planner data not loaded: Planner.Startup/local_state')),
          isTrue,
          reason: logs.join('\n'));
      expect(
          logs.any((l) => l.contains(
              'Planner cannot finish starting: Planner.Startup/bootstrap')),
          isTrue);
      await tester.tap(find.text('Continue anyway'));
      await _pumpSeconds(tester, 1);
    });
  });
  // Last: the boot test above draws app.main()'s warm-up frame, which reuses
  // the binding's last frame time, so it must run before these tests pump
  // frames on their own fake clocks.
  registerLocalFolderSmokeTests();
}
