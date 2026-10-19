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

/// The substrings the editor's deep-link handler reads as "private note,
/// sign in" when no token is set (editor `core/auth_flows.dart`, design
/// review 3 T2). The router's 501 and 404 details avoid them.
const List<String> kDeepLinkPrivateNoteMarkers = <String>[
  'permission',
  'forbidden',
  'not authenticated',
  ' 403 ',
  '403:',
];

bool containsDeepLinkPrivateNoteMarker(String text) {
  final lower = text.toLowerCase();
  return kDeepLinkPrivateNoteMarkers.any(lower.contains);
}

/// Length of the marker that starts at [start] in [text], comparing each
/// character as `toLowerCase` maps it (the detectors' folding), or 0.
int _markerLengthAt(String text, int start, List<String> markers) {
  for (final marker in markers) {
    var i = start;
    var matched = 0;
    while (matched < marker.length && i < text.length) {
      final lowered = text[i].toLowerCase();
      if (!marker.startsWith(lowered, matched)) break;
      matched += lowered.length;
      i++;
    }
    if (matched == marker.length) return i - start;
  }
  return 0;
}

/// Writes a word joiner after the first character of every marker match.
/// The scan resumes at the next character, not after the match, so a marker
/// that overlaps another ("invalid token_not_valid") is broken too.
String _breakMarkers(String text, List<String> markers) {
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    out.write(text[i]);
    if (_markerLengthAt(text, i, markers) > 0) out.write('\u2060');
  }
  return out.toString();
}

/// Breaks every session-rejection sentinel in [text], in any letter case,
/// with a word joiner (U+2060, zero width) after its first letter. The
/// message builders contain no sentinel, but the folder names and browser
/// error texts they interpolate might (a folder named "Invalid token"),
/// so every assembled detail goes through this (2.5). The text looks the
/// same. Characters are folded with `toLowerCase`, as the detectors fold
/// them, so a non-ASCII capital that lowers to an ASCII letter (U+212A
/// KELVIN SIGN lowers to `k`) is caught too.
String scrubSessionSentinels(String text) =>
    _breakMarkers(text, kSessionRejectionSentinels);

/// [scrubSessionSentinels] plus the deep-link markers, for the router's
/// 501 and 404 details, which interpolate the request path.
String scrubRouteDetail(String text) => _breakMarkers(
    text, [...kSessionRejectionSentinels, ...kDeepLinkPrivateNoteMarkers]);

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

  /// 2.10 rule 2: a saved cloud session wins over the connected folder.
  static String cloudSessionWins(String appModule, String user, String name) =>
      'Local folder not used: $appModule.Startup/local_folder — this app is '
      "signed in to the Notechondria cloud as '$user', which takes precedence "
      "over the folder '$name' connected on this browser. Sign out here to "
      'use the folder.';

  // --- Sessions, connect, and disconnect (2.7, 2.10, 6.1) ---

  static String folderSessionStarted(String name) =>
      "Folder session started: Shared.LocalFolder/pick — using '$name'; no "
      'account is used and no data is sent to the Notechondria server.';

  static String folderSessionRestored(String name) =>
      'Folder session started: Shared.LocalFolder/restore_handle — reopened '
      "'$name' from this browser.";

  static String folderDisconnected(String name) =>
      "Folder disconnected: Shared.LocalFolder/disconnect — '$name' is no "
      'longer used in this tab; the app shows its browser-local data again.';

  /// 6.1 mitigation 2, shown before the first connect on a shared origin.
  static String sharedOriginNotice(String origin) =>
      'Folder access is shared with this web address: Shared.LocalFolder/pick '
      '— $origin also hosts other projects, and any page there could use a '
      'folder you grant. Pick a dedicated, empty folder, or use the local '
      'preview or desktop build.';

  /// 6.1 mitigation 3: a non-empty folder without a manifest.
  static String connectNonEmpty(String name, int entries) =>
      "Folder not empty: Shared.LocalFolder/connect — '$name' has "
      '${formatEntryCount(entries)} entries and no manifest.json. Connect it '
      'only if it is a folder you set aside for Notechondria.';

  // --- Check for updates, the one passthrough (2.8 rule 3, Q9) ---

  static String versionChecked(String host, String version) =>
      'Cloud version checked: Shared.LocalFolder/version_check — GET '
      '$host/api/v1/handshake/ answered $version; no account data was sent.';

  static String versionCheckFailed(String host, String cause) =>
      'Cloud version not checked: Shared.LocalFolder/version_check — GET '
      '$host/api/v1/handshake/ failed ($cause); no account data was sent.';

  /// P1B-2: the saved URL failed the passthrough rules, so this page
  /// answered the handshake itself; its version is not the cloud's.
  static String versionCheckAnsweredLocally(String host) =>
      'Cloud version not checked: Shared.LocalFolder/version_check — folder '
      'mode sends the update check only to an https URL or a loopback http '
      'URL, so GET $host/api/v1/handshake/ was answered in this page and '
      'nothing was sent.';

  // --- In-page backend: routes and fallbacks (2.8 rule 2, 4.1) ---

  static String notApiRoute(String method, String path) =>
      'Request not answered: Shared.LocalFolder.Backend/route — $method '
      '$path is not an /api/v1 route, and folder mode sends nothing to the '
      'network.';

  /// The 501 fallback for an /api/v1 route without a folder handler.
  static String routeUnsupported(String method, String path) =>
      'Request not answered: Shared.LocalFolder.Backend/unsupported — '
      '$method $path has no folder handler in this release, and folder mode '
      'sends nothing to the network.';

  /// 501 for a route whose folder handler lands in a later phase (9.1).
  static String laterRelease(String feature, String method, String path) =>
      'Feature not available yet: Shared.LocalFolder.Backend/unsupported — '
      '$feature in folder mode arrives in a later release ($method $path); '
      'nothing was sent to the network.';

  static String requestFailed(String method, String path, String cause) =>
      'Request not answered: Shared.LocalFolder.Backend/route — $method '
      '$path failed in the folder backend ($cause).';

  /// A write after a failed roll-forward that touches a pending path.
  static const String writeBlockedByJournal =
      'Change not saved: Shared.LocalFolder/journal — an earlier change to '
      'these files is not finished; Reconnect or Rescan finishes it first.';

  // Class (c) features (4.2): the route answers 501 with these details.

  static const String casdoorSignIn = 'Cloud sign-in unavailable in folder '
      'mode: Shared.LocalFolder.Backend/unsupported — Casdoor sign-in needs '
      'the Notechondria server, which holds the OAuth client secret. '
      'Disconnect the folder to sign in.';

  static const String emailSignIn = 'Cloud sign-in unavailable in folder '
      'mode: Shared.LocalFolder.Backend/unsupported — email/password sign-in '
      'needs the Notechondria server, which holds the accounts. Disconnect '
      'the folder to sign in.';

  static const String accountLinking = 'Cloud sign-in unavailable in folder '
      'mode: Shared.LocalFolder.Backend/unsupported — account linking needs '
      'the Notechondria server, which holds the accounts. Disconnect the '
      'folder to link accounts.';

  static const String accountNotCreated = 'Account not created: '
      'Shared.LocalFolder.Backend/unsupported — registration, verification, '
      'and password reset are Casdoor flows for Notechondria cloud accounts, '
      'and a local folder needs no account. Disconnect the folder to register '
      'or reset a password.';

  static const String courseNotSubscribed = 'Course not subscribed: '
      'Shared.LocalFolder.Backend/unsupported — subscribing reads another '
      "user's course from the Notechondria server; a local folder holds only "
      'your data.';

  static const String courseNotTransferred = 'Course not transferred: '
      "Shared.LocalFolder.Backend/unsupported — the recipient's account lives "
      'on the Notechondria server.';

  static const String githubAppUnavailable = 'GitHub App connection '
      'unavailable in folder mode: Shared.LocalFolder.GitHub/token — '
      "installing the Notechondria GitHub App needs the server's App private "
      'key. Paste a fine-grained personal access token instead.';

  static const String mcpUnavailable = 'MCP access unavailable in folder '
      'mode: Shared.LocalFolder.Backend/unsupported — agents connect to an MCP '
      'server URL, and a web page cannot accept incoming connections. Your '
      'skill.md is still saved in the folder.';

  /// T7(f): F18's server template catalog.
  static const String templateCoursesNotRestored = 'Template courses not '
      'restored: Shared.LocalFolder.Backend/unsupported — the template catalog '
      'is installed by the Notechondria server; a local folder starts with '
      'only your own courses.';

  static const String publicNotesNotSearched = 'Public notes not searched: '
      "Shared.LocalFolder.Backend/search — other users' public notes live on "
      "the Notechondria server; showing this folder's notes only.";

  // --- Handler answers (4.1) ---

  /// F28: an unknown UUID, which may be another user's shared note.
  static String noteUuidNotFound(String uuid) =>
      'Note not found in folder: Shared.LocalFolder.Backend/notes — $uuid is '
      'not in this folder; shared links of other users open from the '
      'Notechondria server.';

  static String noteNotFound(int id) =>
      'Note not found in folder: Shared.LocalFolder.Backend/notes — note $id '
      'is not in this folder.';

  static String trashedNoteNotFound(int id) =>
      'Note not restored: Shared.LocalFolder.Backend/notes — note $id is not '
      "in this folder's trash.";

  static String courseNotFound(int id) =>
      'Category not found in folder: Shared.LocalFolder.Backend/courses — '
      'category $id is not in this folder.';

  static String courseTitleTaken(String title) =>
      'Category not saved: Shared.LocalFolder.Backend/courses — a category '
      "named '$title' already exists in this folder.";

  /// A request body field that fails validation (400).
  static String invalidField(
          String consequence, String process, String cause) =>
      '$consequence: Shared.LocalFolder.Backend/$process — $cause.';
}
