part of notechondria_frontend;

/// Note-session tracking on the cloud side. Both methods just call
/// `widget.client` and log — no `setState`, no state mutation. Used by
/// the Editor dialog open/close paths so the server knows how long
/// someone spent on a given note. Extracted from `app_shell.dart` so
/// that file stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellNoteSessionsX on _AppShellState {
  Future<int?> _startNoteSession(
      int noteId, String title, String summary) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) return null;
    try {
      final session = await widget.client.startNoteSession(token, {
        'note_id': noteId,
        'title': title,
        'summary': summary,
        'started_at': DateTime.now().toIso8601String(),
      });
      log(
        level: DebugLogLevel.info,
        source: 'Editor.UI/note_session.start',
        message:
            'Note session started: '
            'Editor.UI/note_session.start \u2014 '
            'tracking edits to "$title".',
      );
      return session['id'] as int?;
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.UI/note_session.start',
        message:
            'Note session not started: '
            'Editor.UI/note_session.start \u2014 $cause.',
      );
      return null;
    }
  }

  Future<void> _finishNoteSession(int? sessionId,
      {String? title, String? summary}) async {
    final token = _token;
    if (token == null || token.isEmpty || sessionId == null) return;
    try {
      await widget.client.updateNoteSession(token, sessionId, {
        if (title != null) 'title': title,
        if (summary != null) 'summary': summary,
        'ended_at': DateTime.now().toIso8601String(),
      });
      log(
        level: DebugLogLevel.info,
        source: 'Editor.UI/note_session.finish',
        message:
            'Note session finished: '
            'Editor.UI/note_session.finish \u2014 '
            'session $sessionId closed on server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.warning,
        source: 'Editor.UI/note_session.finish',
        message:
            'Note session not closed: '
            'Editor.UI/note_session.finish \u2014 $cause.',
      );
    }
  }
}
