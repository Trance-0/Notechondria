import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/src/local_folder/folder_messages.dart';
import 'package:notechondria_shared/src/local_folder/qualification.dart';

/// Every message the Phase 1a module can produce, with sample arguments.
final List<String> _allMessages = [
  LocalFolderMessages.needsPickSessionOnly('Notes'),
  LocalFolderMessages.needsPickMissingRecord('Notes'),
  LocalFolderMessages.needsPermission('Notes'),
  LocalFolderMessages.scanning('Notes', 1200, 5000),
  LocalFolderMessages.unavailable('scan', 'manifest.json is unreadable'),
  LocalFolderMessages.disconnectedElsewhere('Notes'),
  LocalFolderMessages.switchedElsewhere('Notes', 'Other'),
  LocalFolderMessages.disconnectedHereWrite('Notes'),
  LocalFolderMessages.disconnectedHereRead('Notes'),
  LocalFolderMessages.readDeadline('/api/v1/notes/', kDeadlineCauseOpening),
  LocalFolderMessages.writeDeadline('PATCH', '/api/v1/notes/1/', kDeadlineCauseLockWait),
  LocalFolderMessages.lockTimeoutRead,
  LocalFolderMessages.lockTimeoutWrite,
  LocalFolderMessages.layoutTooNew(2, 1),
  LocalFolderMessages.manifestInvalid('format is "x"'),
  LocalFolderMessages.manifestMissing('Notes', importPending: true),
  LocalFolderMessages.manifestMissing('Notes', importPending: false),
  LocalFolderMessages.permissionDenied('Notes'),
  LocalFolderMessages.folderNotFound('Notes'),
  LocalFolderMessages.folderIdChanged('Notes', 'abcdef0123', '0123abcdef'),
  LocalFolderMessages.pickCancelled,
  LocalFolderMessages.pickFailed('SecurityError'),
  LocalFolderMessages.pickNoManifest('Empty', 'Notes'),
  LocalFolderMessages.pickDifferentFolder('Other', 'abcdef0123', 'Notes', '0123abcdef'),
  LocalFolderMessages.looksLikeCopy('Notes copy', 'Notes'),
  LocalFolderMessages.mayBeCopy('Notes copy', 'Notes'),
  LocalFolderMessages.connectedElsewhere('Notes'),
  LocalFolderMessages.identityReassigned('notes/a.md', 'u1', 'notes/b.md', 'u2'),
  LocalFolderMessages.recordIdReassigned('courses/c.json', 'course', 3, 'courses/b.json', 4),
  LocalFolderMessages.noteAdopted('notes/a.md', 1, 'u1'),
  LocalFolderMessages.noteDropped('notes/a.md'),
  LocalFolderMessages.countersRaised('note 0 -> 4'),
  LocalFolderMessages.indexNotSaved('NotAllowedError'),
  LocalFolderMessages.journalIncomplete('op', 'editor', 'NotAllowedError'),
  LocalFolderMessages.journalIncomplete(
      'op', 'editor', LocalFolderMessages.journalTooNewCause(2, 1)),
  LocalFolderMessages.journalUnreadable('op', 'bad JSON'),
  LocalFolderMessages.externalEditSaved('notes/a.md', 3),
  LocalFolderMessages.folderBusy('journal', 'Emptying the trash', 2, 5),
  LocalFolderMessages.bootNotChecked('Editor', 'SecurityError'),
  for (final gap in LocalFolderGap.values) localFolderGapMessage(gap),
  // Phase 1b: sessions, connect, the passthrough, and the backend.
  LocalFolderMessages.cloudSessionWins('Editor', 'alice', 'Notes'),
  LocalFolderMessages.folderSessionStarted('Notes'),
  LocalFolderMessages.folderSessionRestored('Notes'),
  LocalFolderMessages.folderDisconnected('Notes'),
  LocalFolderMessages.sharedOriginNotice('https://trance-0.github.io'),
  LocalFolderMessages.connectNonEmpty('Documents', 1200),
  LocalFolderMessages.versionChecked('https://host', '0.1.200'),
  LocalFolderMessages.versionCheckFailed('https://host', 'HTTP 502'),
  LocalFolderMessages.versionCheckAnsweredLocally('http://192.168.1.10:8000'),
  ..._backendDetails,
];

/// Details the router and handlers answer with; the editor's deep-link
/// handler must not read any of them as "private note" (T2).
final List<String> _backendDetails = [
  LocalFolderMessages.notApiRoute('GET', '/media/a.png'),
  LocalFolderMessages.routeUnsupported('GET', '/api/v1/blocks/1/'),
  LocalFolderMessages.laterRelease('Note history', 'GET', '/api/v1/notes/1/history/'),
  LocalFolderMessages.requestFailed('GET', '/api/v1/notes/', 'StateError'),
  LocalFolderMessages.writeBlockedByJournal,
  LocalFolderMessages.casdoorSignIn,
  LocalFolderMessages.emailSignIn,
  LocalFolderMessages.accountLinking,
  LocalFolderMessages.accountNotCreated,
  LocalFolderMessages.courseNotSubscribed,
  LocalFolderMessages.courseNotTransferred,
  LocalFolderMessages.githubAppUnavailable,
  LocalFolderMessages.mcpUnavailable,
  LocalFolderMessages.templateCoursesNotRestored,
  LocalFolderMessages.publicNotesNotSearched,
  LocalFolderMessages.noteUuidNotFound('11111111-2222-4333-8444-555555555555'),
  LocalFolderMessages.noteNotFound(3),
  LocalFolderMessages.trashedNoteNotFound(3),
  LocalFolderMessages.courseNotFound(3),
  LocalFolderMessages.courseTitleTaken('Bio'),
  LocalFolderMessages.invalidField('Note not saved', 'notes', 'title is required'),
  // Phase 2 content routes.
  LocalFolderMessages.attachmentNotFound(3, 7),
  LocalFolderMessages.versionNotFound(3, 9),
  LocalFolderMessages.sessionNotFound(4),
  LocalFolderMessages.invalidField(
      'Attachment not saved', 'attachments', 'the request has no `file` part'),
  // F1: answered in the page for a folder-token request after Disconnect.
  LocalFolderMessages.requestNotSentDisconnected,
  // Phase 3 planner routes and calendar downloads (F35-F43).
  LocalFolderMessages.eventNotFound(5),
  LocalFolderMessages.feedNotFound(6),
  LocalFolderMessages.calendarNoCors('calendar.google.com'),
  LocalFolderMessages.calendarNoCors('calendar.google.com', refresh: true),
  LocalFolderMessages.calendarTimeout('cal.example.org', 5),
  LocalFolderMessages.calendarHttpStatus('cal.example.org', 404),
  LocalFolderMessages.calendarNotIcal('calendar.google.com'),
  LocalFolderMessages.calendarTooLarge('cal.example.org', 5 * 1024 * 1024),
  LocalFolderMessages.calendarIsBackend('notechondria.trance-0.com'),
  LocalFolderMessages.calendarNoSourceUrl(6),
  LocalFolderMessages.unreadableFolderFile('Planner event not saved', 'planner', 'planner/events.json'),
  LocalFolderMessages.eventDateUnreadable(4, 'planner:local-1'),
  LocalFolderMessages.heatmapNotUpdated('planner/heatmap.json'),
];

void main() {
  test('every message has the 1.8 shape', () {
    final shape = RegExp(r'^[^:]+: (Shared\.LocalFolder(\.\w+)?|\w+\.Startup)/[a-z_]+(\.[a-z_]+)? — .+');
    for (final m in _allMessages) {
      expect(shape.hasMatch(m), isTrue, reason: m);
    }
  });

  test('no message contains a session-rejection sentinel (2.5)', () {
    for (final m in _allMessages) {
      expect(containsSessionRejectionSentinel(m), isFalse, reason: m);
    }
    expect(containsSessionRejectionSentinel('Session rejected: x'), isTrue);
    expect(kSessionRejectionSentinels, contains('session rejected:'));
  });

  test('scrubSessionSentinels breaks every sentinel in any case, invisibly',
      () {
    for (final s in kSessionRejectionSentinels) {
      for (final text in ['x $s y', s.toUpperCase(), '$s$s']) {
        final scrubbed = scrubSessionSentinels(text);
        expect(containsSessionRejectionSentinel(scrubbed), isFalse,
            reason: text);
        expect(scrubbed.replaceAll('\u2060', ''), text);
      }
    }
    for (final m in _allMessages) {
      expect(scrubSessionSentinels(m), m, reason: m);
    }
  });

  test('the scrub folds case as the detectors do (U+212A KELVIN SIGN)', () {
    const kelvin = 'Invalid to\u212Aen in TO\u212AEN_NOT_VALID';
    // The detectors lower-case with toLowerCase; whatever it maps U+212A
    // to, the scrubbed text must not count as a hit.
    expect(containsSessionRejectionSentinel(scrubSessionSentinels(kelvin)),
        isFalse);
    if ('\u212A'.toLowerCase() == 'k') {
      expect(containsSessionRejectionSentinel(kelvin), isTrue);
      expect(scrubSessionSentinels(kelvin), isNot(kelvin));
    }
    expect(scrubSessionSentinels(kelvin).replaceAll('\u2060', ''), kelvin);
    // P1A-7: the lower-case form and a mixed-case one, as the review asked.
    for (final text in ['invalid to\u212Aen', 'INVALID TO\u212AEN', 'x Invalid To\u212Aen y']) {
      final scrubbed = scrubSessionSentinels(text);
      expect(containsSessionRejectionSentinel(scrubbed), isFalse, reason: text);
      expect(scrubbed.replaceAll('\u2060', ''), text);
    }
  });

  test('overlapping sentinels are all broken', () {
    // "invalid token" ends inside "token_not_valid"; breaking only the first
    // match would leave the second whole.
    for (final text in [
      'invalid token_not_valid',
      'Invalid Token_Not_Valid',
      'session rejected: invalid token',
    ]) {
      final scrubbed = scrubSessionSentinels(text);
      expect(containsSessionRejectionSentinel(scrubbed), isFalse, reason: text);
      expect(scrubbed.replaceAll('\u2060', ''), text);
      expect(scrubSessionSentinels(scrubbed), scrubbed, reason: 'idempotent');
    }
    final route = scrubRouteDetail('/permissionforbidden/not authenticated 403:/');
    expect(containsDeepLinkPrivateNoteMarker(route), isFalse, reason: route);
  });

  test('router and handler details carry no deep-link marker (T2)', () {
    for (final d in _backendDetails) {
      expect(containsDeepLinkPrivateNoteMarker(d), isFalse, reason: d);
    }
    final path = scrubRouteDetail(LocalFolderMessages.routeUnsupported(
        'GET', '/api/v1/Permission/forbidden/ 403 /403:/invalid token/'));
    expect(containsDeepLinkPrivateNoteMarker(path), isFalse, reason: path);
    expect(containsSessionRejectionSentinel(path), isFalse, reason: path);
  });

  test('no message says "timed out", which friendlyError would rewrite', () {
    for (final m in _allMessages) {
      expect(m.toLowerCase(), isNot(contains('timeout')), reason: m);
      expect(m.toLowerCase(), isNot(contains('timed out')), reason: m);
    }
  });

  group('deadline and lock wordings (2.9, 6.2 R5, T7(h))', () {
    test('read and write deadlines', () {
      expect(LocalFolderMessages.readDeadline('/api/v1/notes/', kDeadlineCauseStalled),
          'Folder data not loaded: Shared.LocalFolder.Backend/route — GET '
          '/api/v1/notes/ took more than 8 s (folder reads stalled).');
      expect(
          LocalFolderMessages.writeDeadline(
              'POST', '/api/v1/notes/', kDeadlineCauseOpening),
          'Change not saved: Shared.LocalFolder.Backend/route — POST '
          '/api/v1/notes/ could not start within 7 s (folder still opening).');
      expect(kFolderReadDeadline, const Duration(seconds: 8));
      expect(kFolderWriteDeadline, const Duration(seconds: 7));
    });

    test('a full 5 s wait names the other tab, read or write', () {
      expect(
          LocalFolderMessages.lockWaitFailed(
              method: 'GET', path: '/api/v1/notes/', cutByDeadline: false),
          'Folder data not loaded: Shared.LocalFolder/lock — another tab held '
          'the folder lock for more than 5 s.');
      expect(
          LocalFolderMessages.lockWaitFailed(
              method: 'patch', path: '/api/v1/notes/1/', cutByDeadline: false),
          'Change not saved: Shared.LocalFolder/lock — another tab held the '
          'folder lock for more than 5 s.');
    });

    test('a wait cut short by the deadline names the deadline instead', () {
      expect(
          LocalFolderMessages.lockWaitFailed(
              method: 'GET', path: '/api/v1/notes/', cutByDeadline: true),
          'Folder data not loaded: Shared.LocalFolder.Backend/route — GET '
          '/api/v1/notes/ took more than 8 s (waiting for the folder lock).');
      expect(
          LocalFolderMessages.lockWaitFailed(
              method: 'delete', path: '/api/v1/notes/1/', cutByDeadline: true),
          'Change not saved: Shared.LocalFolder.Backend/route — DELETE '
          '/api/v1/notes/1/ could not start within 7 s (waiting for the folder '
          'lock).');
    });
  });

  group('state wordings', () {
    test('disconnected in this tab has a write form and a read form (T7(i))',
        () {
      expect(LocalFolderMessages.disconnectedHereWrite('Notes'),
          startsWith('Change not saved: Shared.LocalFolder/disconnect — '));
      expect(LocalFolderMessages.disconnectedHereRead('Notes'),
          startsWith('Folder data not loaded: Shared.LocalFolder/disconnect — '));
    });

    test('needsPick: session-only and missing-record wordings differ (T3)', () {
      expect(LocalFolderMessages.needsPickSessionOnly('Notes'),
          contains('for one page load only (session-only mode)'));
      final missing = LocalFolderMessages.needsPickMissingRecord('Notes');
      expect(missing, contains('was set to remember'));
      expect(missing, isNot(contains('session-only')));
      expect(missing, endsWith("Click Choose 'Notes' again."));
    });

    test('progress counts use thousands separators', () {
      expect(LocalFolderMessages.scanProgress('Notes', 1200, 5000),
          "Reading folder 'Notes': 1,200 of 5,000 entries");
      expect(formatEntryCount(0), '0');
      expect(formatEntryCount(999), '999');
      expect(formatEntryCount(1234567), '1,234,567');
    });

    test('folder ids are shortened to 8 hex in refusals', () {
      expect(
          LocalFolderMessages.pickDifferentFolder(
              'Other', 'abcdef0123456789', 'Notes', '0123456789abcdef'),
          "Folder not opened: Shared.LocalFolder/pick — 'Other' is a different "
          "Notechondria folder (folder_id abcdef01) from 'Notes' (01234567), "
          "which this browser uses. Choose 'Notes', or switch this browser to "
          "'Other'.");
    });
  });
}
