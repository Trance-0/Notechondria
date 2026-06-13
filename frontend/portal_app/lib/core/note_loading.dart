part of notechondria_frontend;

/// Note/course loading + front page refresh.
extension _AppShellNoteLoadingX on _AppShellState {
  Future<void> _refreshFrontPageData() async {
    try {
      final frontPage = await widget.client.getFrontPage(token: _token);
      List<Map<String, dynamic>> plannerEvents = _plannerEvents;
      if (_token != null && _token!.isNotEmpty) {
        plannerEvents = await widget.client.getPlannerEvents(_token!);
      }
      _frontPage = frontPage;
      _plannerEvents = plannerEvents;
      refreshState();
      await _persistLocalCache();
      log(
        level: DebugLogLevel.debug,
        source: 'Portal.Sync.FrontPage/pull',
        message: 'Front page refreshed: '
            'Portal.Sync.FrontPage/pull \u2014 '
            'carousel + planner events re-pulled from server.',
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _errorMessage = cause;
      refreshState();
      log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.FrontPage/pull',
        message: 'Front page not refreshed: '
            'Portal.Sync.FrontPage/pull \u2014 $cause.',
      );
    }
  }

  Future<void> _loadLearnerNotes({bool reset = false, String? query}) async {
    if (_token == null || _token!.isEmpty) {
      _learnerSearchQuery = query ?? _learnerSearchQuery;
      refreshState();
      return;
    }
    if (_isLoadingMoreNotes) {
      return;
    }
    final effectiveQuery = query ?? _learnerSearchQuery;
    final nextOffset = reset ? 0 : _learnerNotesOffset;
    _isLoadingMoreNotes = true;
    if (reset) {
      _learnerSearchQuery = effectiveQuery;
    }
    refreshState();
    try {
      final page = await widget.client.listNotes(
        token: _token,
        query: effectiveQuery,
        offset: nextOffset,
        limit: 20,
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
        source: 'Portal.Sync.Notes/list',
        message: 'Notes list load failed: '
            'Portal.Sync.Notes/list \u2014 $cause.',
      );
    }
  }

  Future<void> _selectCourse(Map<String, dynamic> course) async {
    _selectedCourse = course;
    _isLoading = true;
    refreshState();
    if (isLocalCourse(course)) {
      _courseNotes = _localNotesForCourse(course);
      _selectedNote = null;
      _selectedIndex = 2;
      _isLoading = false;
      refreshState();
      log(
        level: DebugLogLevel.debug,
        source: 'Portal.UI/open_course',
        message: "Opened local course: Portal.UI/open_course \u2014 "
            "'${course['title']}' selected in portal view.",
      );
      return;
    }
    try {
      var effectiveCourse = Map<String, dynamic>.from(course);
      if ((_token?.isNotEmpty ?? false) && course['is_subscribed'] == true) {
        effectiveCourse =
            await widget.client.openCourse(_token!, course['id'] as int);
      }
      final refreshedCourses = (await widget.client.getCourses(token: _token))
          .map(decorateRemoteCourse)
          .toList();
      final refreshedSelected = refreshedCourses.firstWhere(
        (item) => item['id'] == effectiveCourse['id'],
        orElse: () => effectiveCourse,
      );
      final notes = await widget.client.getCourseNotes(
        refreshedSelected['id'] as int,
        token: _token,
      );
      _courses = refreshedCourses;
      _selectedCourse = refreshedSelected;
      _courseNotes = notes;
      _selectedNote = null;
      _selectedIndex = 2;
      _isLoading = false;
      refreshState();
      await _persistLocalCache();
      log(
        level: DebugLogLevel.debug,
        source: 'Portal.UI/open_course',
        message: "Opened course: Portal.UI/open_course \u2014 "
            "'${refreshedSelected['title']}' loaded from cloud.",
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _selectedCourse = course;
      _courseNotes = const [];
      _errorMessage = cause;
      _isLoading = false;
      refreshState();
      log(
        level: DebugLogLevel.error,
        source: 'Portal.Sync.Courses/load',
        message: 'Course not loaded: '
            'Portal.Sync.Courses/load \u2014 $cause.',
      );
    }
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
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _errorMessage = cause;
      _isLoading = false;
      refreshState();
      log(
        level: DebugLogLevel.error,
        source: 'Portal.UI/open_note',
        message: 'Note not opened: Portal.UI/open_note \u2014 $cause.',
      );
    }
  }

  Future<void> _openNoteViewer(Map<String, dynamic> noteSummary) async {
    Map<String, dynamic> detail;
    try {
      detail = await _fetchNoteDetail(noteSummary['id'] as int);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      showMessage(
        'Note not opened: Portal.UI/open_note_viewer \u2014 $cause.',
      );
      log(
        level: DebugLogLevel.error,
        source: 'Portal.UI/open_note_viewer',
        message: 'Note not opened: Portal.UI/open_note_viewer \u2014 $cause.',
      );
      return;
    }
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => _NoteViewerDialog(note: detail),
    );
  }

  Future<Map<String, dynamic>> _fetchNoteDetail(int noteId) async {
    if (noteId < 0) {
      final draft = _localDrafts.firstWhere(
        (item) => item['id'] == noteId,
        orElse: () => <String, dynamic>{},
      );
      if (draft.isEmpty) {
        throw Exception(
          'Local draft not found: '
          'Portal.Sync.Notes/save_local \u2014 '
          'no local draft matches the requested id.',
        );
      }
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
