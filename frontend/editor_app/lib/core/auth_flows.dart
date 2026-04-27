part of notechondria_frontend;

/// URL fragment → note UUID parser used by the editor's deep-link
/// flow. Accepts any of:
///   - `/notes/<uuid>` (leading slash optional)
///   - `/notes/<uuid>/` (trailing slash)
///   - `/notes/<uuid>?ref=share` (trailing query string)
///   - `notes/<uuid>` (no leading slash at all)
/// The earlier `^/?notes/<uuid>$` anchor blocked trailing slashes
/// and any fragment suffix — share links opened cold from a chat
/// app sometimes landed on the home view instead of the note.
/// 0.1.67 fixed the regex; 0.1.83 promoted this to a top-level
/// function so the parser is unit-testable without mounting the
/// full app.
final RegExp _noteUuidFragmentPattern = RegExp(
  r'/?notes/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})',
  caseSensitive: false,
);

/// Pure parser. Returns the UUID string if [fragment] (the part of
/// a URL after `#`) contains `/notes/<uuid>`, or null otherwise.
/// Does NOT touch `Uri.base` — caller passes the fragment in so
/// tests can drive arbitrary URLs.
String? parseNoteUuidFromFragment(String fragment) {
  final match = _noteUuidFragmentPattern.firstMatch(fragment);
  return match?.group(1);
}

/// Deep-link + session-restore helpers that are editor-specific and
/// thus don't live in `AppShellOAuthMixin` (which covers the generic
/// `launchOAuth` / `handleOAuthCallback` flows shared across apps).
/// `_openNoteByUuid` opens the editor's `_NoteEditorDialog` or
/// `_NoteViewerDialog` based on ownership, and `_restoreSession`
/// revives a persisted `_LocalAppStore` session against
/// `/auth/session/`. Extracted from `app_shell.dart` so that file
/// stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellAuthFlowsX on _AppShellState {
  /// Fetch a note by UUID and open it in the viewer/editor.
  Future<void> _openNoteByUuid(String uuid) async {
    _isLoading = true;
    refreshState();
    try {
      final detail = await widget.client.getNoteByUuid(uuid, token: _token);
      _selectedNote = detail;
      _selectedIndex = 1;
      _isLoading = false;
      refreshState();
      _replaceNoteUrl(uuid);
      // Open the note viewer/editor dialog after the frame renders.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showNoteDialogForDeepLink(detail);
        });
      }
    } catch (error) {
      final raw = error.toString().replaceFirst('Exception: ', '');
      final lower = raw.toLowerCase();
      // If the note exists but is private to another user, the backend
      // returns 403. Surface a sign-in prompt instead of the raw
      // "Permission denied" string — a cold open of a shared link
      // should tell the user "you need to sign in to view this",
      // not look like a crash.
      final needsAuth = lower.contains('permission') ||
          lower.contains('forbidden') ||
          lower.contains('not authenticated') ||
          raw.contains(' 403 ') ||
          raw.contains('403:');
      if (needsAuth && (_token == null || _token!.isEmpty)) {
        _errorMessage =
            'This note is private. Sign in to view it — open Settings → '
            'Account to log in, then the link will load.';
      } else {
        _errorMessage = 'Could not load note: $raw';
      }
      _isLoading = false;
      refreshState();
    }
  }

  void _showNoteDialogForDeepLink(Map<String, dynamic> detail) {
    final canEdit = detail['can_edit'] == true;
    if (canEdit) {
      // Owner: open in editor.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _NoteEditorDialog(
          note: detail,
          courses: [..._localCourses, ..._courses],
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          onSave: _saveNote,
          onSnapshot: _snapshotNote,
          onGetHistory: _getNoteHistory,
          onRestoreVersion: _restoreNoteVersion,
          onLogEvent: appendUiLog,
          onUploadAttachment: _uploadNoteAttachment,
          onUploadCover: _token != null
              ? (noteId, file) =>
                  widget.client.uploadNoteCoverImage(_token!, noteId, file)
              : null,
          onDeleteCover: _token != null
              ? (noteId) =>
                  widget.client.deleteNoteCoverImage(_token!, noteId)
              : null,
        ),
      );
    } else {
      // Non-owner: read-only viewer.
      showDialog<void>(
        context: context,
        builder: (context) => _NoteViewerDialog(
          note: detail,
          onEdit: null,
          onExport: () => _exportNote(detail),
          onDelete: null,
        ),
      );
    }
  }

  /// Restores a persisted auth session if one exists. Validates the
  /// token against the backend via `/auth/session/`; if the token is
  /// stale the persisted session is cleared.
  Future<void> _restoreSession() async {
    final session = await _LocalAppStore.loadSession();
    if (session == null) return;
    final token = session['token']?.toString() ?? '';
    if (token.isEmpty) return;
    try {
      final check = await widget.client.checkSession(token);
      if (check['authenticated'] == true) {
        await applyAuthPayload(check);
        return;
      }
    } catch (_) {
      // Token invalid or network down — fall through and clear.
    }
    await _LocalAppStore.clearSession();
  }
}
