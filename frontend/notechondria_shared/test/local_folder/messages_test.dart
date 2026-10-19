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
  LocalFolderMessages.journalIncomplete('op', 'editor', 'NotAllowedError'),
  LocalFolderMessages.journalUnreadable('op', 'bad JSON'),
  LocalFolderMessages.externalEditSaved('notes/a.md', 3),
  LocalFolderMessages.folderBusy('journal', 'Emptying the trash', 2, 5),
  LocalFolderMessages.bootNotChecked('Editor', 'SecurityError'),
  for (final gap in LocalFolderGap.values) localFolderGapMessage(gap),
];

void main() {
  test('every message has the 1.8 shape', () {
    final shape = RegExp(r'^[^:]+: (Shared\.LocalFolder(\.\w+)?|\w+\.Startup)/[a-z_]+ — .+');
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
