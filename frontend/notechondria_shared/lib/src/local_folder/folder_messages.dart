/// User-facing and log messages of the local folder module, in the
/// docs/AGENTS.md 1.8 shape "<consequence>: <module>/<process> — <cause>".
/// Every detail a folder request can answer with contains "—", so
/// `shapedErrorMessage` passes it through verbatim (main 2.5), and none may
/// contain a session-rejection sentinel ([kSessionRejectionSentinels]).
library;

/// The substrings the three apps' session-rejection detectors count
/// (main 2.5, docs/AGENTS.md preserved sentinels). Two hits in one load
/// clear the session, so no folder message may contain any of them.
const List<String> kSessionRejectionSentinels = <String>[
  'invalid token',
  'authentication credentials were not provided',
  'token_not_valid',
  'session rejected:',
];

bool containsSessionRejectionSentinel(String text) {
  final lower = text.toLowerCase();
  return kSessionRejectionSentinels.any(lower.contains);
}

final List<RegExp> _sentinelPatterns = [
  for (final s in kSessionRejectionSentinels)
    RegExp(RegExp.escape(s), caseSensitive: false),
];

/// Breaks every session-rejection sentinel in [text], in any letter case,
/// with a word joiner (U+2060, zero width) after its first letter. The
/// message builders contain no sentinel, but the folder names and browser
/// error texts they interpolate might (a folder named "Invalid token"),
/// so every assembled 503 detail goes through this (2.5). The text looks
/// the same.
String scrubSessionSentinels(String text) {
  var out = text;
  for (final pattern in _sentinelPatterns) {
    out = out.replaceAllMapped(
        pattern, (m) => '${m[0]!.substring(0, 1)}\u2060${m[0]!.substring(1)}');
  }
  return out;
}

enum LocalFolderLogLevel { info, warning, error }

/// Where folder code reports log lines; [message] is a full 1.8 string.
/// The app forwards them to its debug log (`<App>` shells, Phase 2 and 3).
typedef LocalFolderLogSink = void Function(
    LocalFolderLogLevel level, String message);

void _discardLog(LocalFolderLogLevel level, String message) {}

/// The default sink: drops every line.
const LocalFolderLogSink discardLocalFolderLog = _discardLog;

/// Read deadline for a GET, measured from request start (2.9 "Bounds").
const Duration kFolderReadDeadline = Duration(seconds: 8);

/// Deadline for a write to start (journal record or writable open, 2.9).
const Duration kFolderWriteDeadline = Duration(seconds: 7);

/// Causes named by the 2.9 deadline messages.
const String kDeadlineCauseOpening = 'folder still opening';
const String kDeadlineCauseLockWait = 'waiting for the folder lock';
const String kDeadlineCauseStalled = 'folder reads stalled';

String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

/// Thousands separators for splash progress ("1,200 of 5,000 entries").
String formatEntryCount(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

abstract final class LocalFolderMessages {
  // --- 503 details for folder states outside `active` (2.8 rule 4) ---

  static String needsPickSessionOnly(String name) =>
      "Folder not open: Shared.LocalFolder/restore_handle — this browser "
      "keeps access to '$name' for one page load only (session-only mode), "
      "so it has to be chosen again. Click Choose '$name' again.";

  /// T3: "Remember this folder" is on but the IndexedDB record is gone.
  static String needsPickMissingRecord(String name) =>
      "Folder not open: Shared.LocalFolder/restore_handle — this browser "
      "was set to remember '$name', but its saved folder handle is missing "
      "(browser site data was cleared, or the handle was never stored), so "
      "it has to be chosen again. Click Choose '$name' again.";

  static String needsPermission(String name) =>
      "Folder access lost: Shared.LocalFolder/permission — the browser no "
      "longer grants read and write access to '$name' (NotAllowedError, or "
      "access revoked while the tab was in the background). Click Reconnect.";

  static String scanning(String name, int done, int total) =>
      "Folder not ready: Shared.LocalFolder/scan — '$name' is still being "
      "indexed (${formatEntryCount(done)} of ${formatEntryCount(total)} "
      "entries). Try again in a moment.";

  static String unavailable(String process, String cause) =>
      'Folder unavailable: Shared.LocalFolder/$process — $cause.';

  static String disconnectedElsewhere(String name) =>
      "Folder disconnected: Shared.LocalFolder/disconnect — '$name' was "
      'disconnected in another tab. Reload to continue in browser-local '
      'mode.';

  static String switchedElsewhere(String name, String picked) =>
      'Folder switched in another tab: Shared.LocalFolder/connect — this '
      "browser now uses '$picked' instead of '$name'. Reload to open it.";

  /// 2.10 rule 4 step 1, for a write.
  static String disconnectedHereWrite(String name) =>
      "Change not saved: Shared.LocalFolder/disconnect — '$name' was "
      'disconnected in this tab; the change stays in this browser.';

  /// T7(i): the read form of the same state.
  static String disconnectedHereRead(String name) =>
      "Folder data not loaded: Shared.LocalFolder/disconnect — '$name' was "
      'disconnected in this tab; the app reloads its browser-local data '
      'instead.';

  // --- Deadlines (2.9) and lock waits (6.2 R5, T7(h)) ---

  static String readDeadline(String path, String cause) =>
      'Folder data not loaded: Shared.LocalFolder.Backend/route — GET $path '
      'took more than ${kFolderReadDeadline.inSeconds} s ($cause).';

  static String writeDeadline(String method, String path, String cause) =>
      'Change not saved: Shared.LocalFolder.Backend/route — $method $path '
      'could not start within ${kFolderWriteDeadline.inSeconds} s ($cause).';

  static const String lockTimeoutRead =
      'Folder data not loaded: Shared.LocalFolder/lock — another tab held '
      'the folder lock for more than 5 s.';

  static const String lockTimeoutWrite =
      'Change not saved: Shared.LocalFolder/lock — another tab held the '
      'folder lock for more than 5 s.';

  /// T7(h): a lock wait cut short by the request deadline did not wait the
  /// full 5 s, so it gets the 2.9 deadline message instead of R5's.
  static String lockWaitFailed({
    required String method,
    required String path,
    required bool cutByDeadline,
  }) {
    final isRead = method.toUpperCase() == 'GET';
    if (cutByDeadline) {
      return isRead
          ? readDeadline(path, kDeadlineCauseLockWait)
          : writeDeadline(method.toUpperCase(), path, kDeadlineCauseLockWait);
    }
    return isRead ? lockTimeoutRead : lockTimeoutWrite;
  }

  // --- Opening a folder (2.9, 3.2, 6.3, T7(g)) ---

  static String layoutTooNew(int found, int supported) =>
      'Folder not opened: Shared.LocalFolder/scan — manifest.json '
      'layout_version $found is newer than this build supports ($supported). '
      'Update the app.';

  static String manifestInvalid(String cause) =>
      'Folder not opened: Shared.LocalFolder/scan — manifest.json is not a '
      'Notechondria folder manifest ($cause).';

  /// T7(g): a granted handle whose manifest.json is missing.
  static String manifestMissing(String name, {required bool importPending}) {
    final cause = importPending
        ? 'an archive import into it did not finish; '
            '.notechondria/import.json is still there'
        : 'it was deleted or moved out of the folder';
    return "Folder not opened: Shared.LocalFolder/scan — '$name' has no "
        'manifest.json ($cause). Disconnect, then connect '
        "'$name' again to rebuild it; its notes stay on disk and are indexed "
        'again.';
  }

  static String permissionDenied(String name) =>
      'Folder not opened: Shared.LocalFolder/permission — the browser denies '
      "access to '$name'. Choose the folder again or switch to browser-local "
      'mode.';

  static String folderNotFound(String name) =>
      "Folder not found: Shared.LocalFolder/restore_handle — '$name' was "
      'moved, renamed, or deleted (NotFoundError). Choose the folder again '
      'or switch to browser-local mode.';

  static String folderIdChanged(String name, String found, String expected) =>
      "Folder not opened: Shared.LocalFolder/restore_handle — '$name' now "
      'holds another Notechondria folder (folder_id ${_short(found)}) than '
      'the one this browser uses (${_short(expected)}). Choose the folder '
      'again.';

  // --- Pick flow (2.9 "Choose again", 3.7 copy check) ---

  static const String pickCancelled =
      'Folder not chosen: Shared.LocalFolder/pick — the picker closed without '
      'a folder (AbortError).';

  static String pickFailed(String cause) =>
      'Folder not chosen: Shared.LocalFolder/pick — the browser could not '
      'open the folder picker ($cause).';

  static String pickNoManifest(String picked, String name) =>
      "Folder not opened: Shared.LocalFolder/pick — '$picked' has no "
      "manifest.json, so it is not '$name'. Choose '$name', or use "
      'browser-local mode and connect a new folder from the sign-in screen.';

  static String pickDifferentFolder(
          String picked, String pickedId, String name, String id) =>
      "Folder not opened: Shared.LocalFolder/pick — '$picked' is a different "
      'Notechondria folder (folder_id ${_short(pickedId)}) from '
      "'$name' (${_short(id)}), which this browser uses. Choose '$name', or "
      "switch this browser to '$picked'.";

  static String looksLikeCopy(String name, String other) =>
      "Folder looks like a copy: Shared.LocalFolder/pick — '$name' has the "
      "same folder_id as '$other'. Give it its own identity?";

  static String mayBeCopy(String name, String other) =>
      "Folder may be a copy: Shared.LocalFolder/pick — '$name' has the same "
      "folder_id as '$other', which this browser remembers, and checking "
      "'$other' needs access to it.";

  static String connectedElsewhere(String name) =>
      "Folder connected in another tab: Shared.LocalFolder/connect — '$name' "
      "is now this browser's storage. Reload to use it; this tab's "
      'browser-local data will be copied in.';

  // --- Scan, journal, and identity logs (3.4.1, 3.7, 3.8, 6.2 R4) ---

  static String scanProgress(String name, int done, int total) =>
      "Reading folder '$name': ${formatEntryCount(done)} of "
      '${formatEntryCount(total)} entries';

  static String identityReassigned(
          String file, String old, String keeper, String fresh) =>
      "Note identity reassigned: Shared.LocalFolder/scan — '$file' claimed "
      "uuid $old, which '$keeper' already uses; it now has uuid $fresh.";

  static String recordIdReassigned(
          String file, String kind, int old, String keeper, int fresh) =>
      "Folder record id reassigned: Shared.LocalFolder/scan — '$file' "
      "claimed $kind id $old, which '$keeper' already uses; it now has id "
      '$fresh.';

  static String noteAdopted(String file, int id, String uuid) =>
      "Note adopted: Shared.LocalFolder/scan — '$file' had no sidecar; it "
      'now has id $id and uuid $uuid.';

  static String noteDropped(String file) =>
      "Note dropped from index: Shared.LocalFolder/scan — '$file' no longer "
      'exists on disk.';

  static String countersRaised(String kinds) =>
      'Folder ID counters raised: Shared.LocalFolder/scan — manifest.json '
      'counters were below IDs found on disk ($kinds).';

  static String journalIncomplete(String opId, String app, String cause) =>
      'Folder change not finished: Shared.LocalFolder/journal — $opId from '
      '$app is incomplete ($cause); the notes it touches are hidden until '
      'Reconnect or Rescan finishes it.';

  static String journalUnreadable(String opId, String cause) =>
      'Folder change discarded: Shared.LocalFolder/journal — record $opId '
      'could not be read ($cause), so it was deleted without being '
      'replayed; the files it names keep their current contents.';

  /// The cause [journalIncomplete] names for a newer build's record.
  static String journalTooNewCause(int found, int supported) =>
      'record schema_version $found is above $supported, the newest this '
      'build reads; update the app to finish it';

  static String externalEditSaved(String file, int versionId) =>
      "External edit kept: Shared.LocalFolder/journal — '$file' changed on "
      'disk after an interrupted change; the edited text is saved as '
      'history version $versionId before the change is finished.';

  static String folderBusy(String process, String operation, int k, int n) =>
      'Folder busy: Shared.LocalFolder/$process — $operation ($k of $n).';

  /// 2.8: `LocalFolderBoot.preload` could not read browser storage.
  static String bootNotChecked(String appModule, String cause) =>
      'Local folder not checked: $appModule.Startup/local_folder — browser '
      'storage could not be read ($cause); starting in browser-local or '
      'cloud mode.';
}
