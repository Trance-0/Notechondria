part of notechondria_frontend;

/// Learner-list fetch, course selection, note selection, and note-detail
/// fetch. Routes every state mutation through `refreshState()` since extensions
/// cannot call `setState` directly. Extracted from `app_shell.dart` so that
/// file stays closer to the AGENTS.md §1.5 1000-line ceiling.
extension _AppShellNoteLoadingX on _AppShellState {
  Future<void> _loadLearnerNotes({
    bool reset = false,
    String? query,
    String? scope,
  }) async {
    if (_isLoadingMoreNotes) return;
    final isAuthenticated = _token != null && _token!.isNotEmpty;
    final effectiveQuery = query ?? _learnerSearchQuery;
    // Anonymous users always see public notes (scope=all).
    final effectiveScope =
        isAuthenticated ? (scope ?? _learnerSearchScope) : 'all';
    final nextOffset = reset ? 0 : _learnerNotesOffset;
    if (reset) {
      _learnerSearchQuery = effectiveQuery;
      _learnerSearchScope = effectiveScope;
    }

    final activeCourseId = _selectedCategoryId;
    // Local-course view: a category whose backend id is negative was
    // created offline and only contains local drafts. Showing public
    // notes here is misleading because the cloud has no record of the
    // category. Same goes for `scope == 'local'` — the user explicitly
    // asked to see only local drafts. Either way, clear the cloud
    // result list and skip the listNotes call.
    final isLocalCourseSelected =
        activeCourseId != null && activeCourseId < 0;
    if (isLocalCourseSelected || effectiveScope == 'local') {
      _learnerNotes = const [];
      _hasMoreLearnerNotes = false;
      _learnerNotesOffset = 0;
      refreshState();
      return;
    }

    _isLoadingMoreNotes = true;
    refreshState();
    try {
      final page = await widget.client.listNotes(
        token: isAuthenticated ? _token : null,
        query: effectiveQuery,
        offset: nextOffset,
        limit: 20,
        courseId:
            (activeCourseId != null && activeCourseId > 0) ? activeCourseId : null,
        scope: effectiveScope,
      );
      final rows = (page['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      _learnerNotes = reset ? rows : [..._learnerNotes, ...rows];
      _hasMoreLearnerNotes = page['has_more'] == true;
      _learnerNotesOffset = (reset ? 0 : _learnerNotesOffset) + rows.length;
      _isLoadingMoreNotes = false;
      refreshState();
    } catch (error) {
      _isLoadingMoreNotes = false;
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      refreshState();
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.Sync.Notes/list',
        message:
            'Notes list load failed: '
            'Editor.Sync.Notes/list \u2014 $cause.',
      );
    }
  }

  Future<void> _selectCourse(Map<String, dynamic> course) async {
    final courseId = (course['id'] as num?)?.toInt();
    _selectedCourse = course;
    _selectedCategoryId = courseId;
    _selectedIndex = 1;
    _selectedNote = null;
    refreshState();
    _replaceNoteUrl(null);
    log(
      level: DebugLogLevel.debug,
      source: 'Editor.UI/open_course',
      message:
          'Opened category: Editor.UI/open_course \u2014 '
          '${isLocalCourse(course) ? 'local ' : ''}'
          "'${course['title']}' selected in learner view.",
    );
    await _loadLearnerNotes(reset: true, query: _learnerSearchQuery);
  }

  Future<void> _selectNote(Map<String, dynamic> noteSummary) async {
    _isLoading = true;
    refreshState();
    try {
      final detail = await _fetchNoteDetail(noteSummary['id'] as int);
      _selectedNote = detail;
      _selectedIndex = 1;
      _isLoading = false;
      refreshState();
      final uuid = detail['uuid']?.toString();
      if (uuid != null) _pushNoteUrl(uuid);
    } catch (error) {
      _errorMessage = error.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      refreshState();
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: 'Editor.UI/open_note',
        message:
            'Note not opened: Editor.UI/open_note \u2014 $cause.',
      );
    }
  }

  Future<Map<String, dynamic>> _fetchNoteDetail(int noteId) async {
    if (noteId < 0) {
      final draft = _localDrafts.firstWhere(
        (item) => item['id'] == noteId,
        orElse: () => <String, dynamic>{},
      );
      if (draft.isEmpty) throw Exception('Local draft not found.');
      _selectedNote = draft;
      refreshState();
      return draft;
    }
    final detail = await widget.client.getNoteDetail(noteId, token: _token);
    _selectedNote = detail;
    refreshState();
    return detail;
  }
}
