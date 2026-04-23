part of notechondria_frontend;

/// Cloud note-session tracking.
extension _AppShellNoteSessionsX on _AppShellState {
  Future<int?> _startNoteSession(
      int noteId, String title, String summary) async {
    final token = _token;
    if (token == null || token.isEmpty || noteId < 0) {
      return null;
    }
    try {
      final session = await widget.client.startNoteSession(token, {
        'note_id': noteId,
        'title': title,
        'summary': summary,
        'started_at': DateTime.now().toIso8601String(),
      });
      log(
        level: DebugLogLevel.info,
        source: 'Planner.UI/note_session.start',
        message:
            'Note session started: '
            'Planner.UI/note_session.start \u2014 '
            'tracking edits to "$title".',
      );
      return session['id'] as int?;
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Planner.UI/note_session.start',
        message:
            'Note session not started: '
            'Planner.UI/note_session.start \u2014 $cause.',
      );
      return null;
    }
  }

  Future<void> _finishNoteSession(int? sessionId,
      {String? title, String? summary}) async {
    final token = _token;
    if (token == null || token.isEmpty || sessionId == null) {
      return;
    }
    try {
      await widget.client.updateNoteSession(token, sessionId, {
        if (title != null) 'title': title,
        if (summary != null) 'summary': summary,
        'ended_at': DateTime.now().toIso8601String(),
      });
      await _loadActivityWeek(startDate: _activityWeekStart);
      log(
        level: DebugLogLevel.info,
        source: 'Planner.UI/note_session.finish',
        message:
            'Note session finished: '
            'Planner.UI/note_session.finish \u2014 '
            'session $sessionId closed on server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.UI/note_session.finish',
        message:
            'Note session not closed: '
            'Planner.UI/note_session.finish \u2014 $cause.',
      );
    }
  }
}
