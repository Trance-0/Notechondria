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

  /// Applies a learner-feed filter change (scope / sort / window) and
  /// reloads the public-notes section from the first page.
  Future<void> _setLearnerFilters({
    String? scope,
    String? sort,
    String? window,
  }) async {
    _learnerScope = scope ?? _learnerScope;
    _learnerSort = sort ?? _learnerSort;
    _learnerWindow = window ?? _learnerWindow;
    refreshState();
    await _loadLearnerNotes(reset: true);
  }

  Future<void> _loadLearnerNotes({bool reset = false, String? query}) async {
    if (_isLoadingMoreNotes) {
      return;
    }
    final signedIn = _token != null && _token!.isNotEmpty;
    final effectiveQuery = query ?? _learnerSearchQuery;
    final nextOffset = reset ? 0 : _learnerNotesOffset;
    _isLoadingMoreNotes = true;
    if (reset) {
      _learnerSearchQuery = effectiveQuery;
    }
    refreshState();
    try {
      // Signed-out visitors get the public feed (the backend forces
      // is_public for anonymous requests regardless of scope), so the
      // public note section is never empty for guests.
      final page = await widget.client.listNotes(
        token: _token,
        query: effectiveQuery,
        offset: nextOffset,
        limit: 20,
        scope: signedIn ? _learnerScope : 'public',
        sort: _learnerSort,
        window: _learnerWindow,
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
      url_strategy.replaceBrowserPath('/courses');
      log(
        level: DebugLogLevel.debug,
        source: 'Portal.UI/open_course',
        message: "Opened local course: Portal.UI/open_course \u2014 "
            "'${course['title']}' selected in portal view.",
      );
      return;
    }
    try {
      final courseId = course['id'] as int;
      // 0.1.185 fast path: only the FIRST notes page (and the open-course
      // subscription stamp, in parallel) block the render. The previous
      // flow chained openCourse → FULL course-list refresh → the entire
      // unpaged note set (~16 s on a 193-note imported course).
      _courseNotesLoading = true;
      _courseNotes = const [];
      _courseNotesHasMore = false;
      _courseNotesOffset = 0;
      _selectedNote = null;
      _selectedIndex = 2;
      refreshState();
      final openFuture =
          ((_token?.isNotEmpty ?? false) && course['is_subscribed'] == true)
              ? widget.client.openCourse(_token!, courseId)
              : Future.value(Map<String, dynamic>.from(course));
      final results = await Future.wait<dynamic>([
        openFuture,
        widget.client.getCourseNotesPage(courseId,
            token: _token, limit: 10, offset: 0),
      ]);
      final effectiveCourse = Map<String, dynamic>.from(results[0] as Map);
      final page = Map<String, dynamic>.from(results[1] as Map);
      final rows = (page['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      _selectedCourse = decorateRemoteCourse(effectiveCourse);
      _courseNotes = rows;
      _courseNotesHasMore = page['has_more'] == true;
      _courseNotesOffset = rows.length;
      _courseNotesLoading = false;
      _isLoading = false;
      refreshState();
      // Unique, shareable URL for the opened course.
      final slug = effectiveCourse['slug']?.toString() ?? '';
      url_strategy.replaceBrowserPath(
          slug.isEmpty ? '/courses' : '/courses/$slug');
      // Course-list refresh moves off the critical path.
      unawaited(widget.client.getCourses(token: _token).then((refreshed) {
        if (!mounted) return;
        _courses = refreshed.map(decorateRemoteCourse).toList();
        refreshState();
      }).catchError((_) {}));
      await _persistLocalCache();
      log(
        level: DebugLogLevel.debug,
        source: 'Portal.UI/open_course',
        message: "Opened course: Portal.UI/open_course \u2014 "
            "'${effectiveCourse['title']}' loaded from cloud.",
      );
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      _selectedCourse = course;
      _courseNotes = const [];
      _courseNotesLoading = false;
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
      url_strategy.replaceBrowserPath('/notes');
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
    final uuid = detail['uuid']?.toString() ?? '';
    if (uuid.isEmpty) {
      // Local drafts have no server uuid → no URL identity; keep the
      // in-place dialog for them.
      await showDialog<void>(
        context: context,
        builder: (context) => _NoteViewerDialog(
          note: detail,
          onFollowLink: _followNoteLink,
        ),
      );
      return;
    }
    // Routed note page: pushes `#/note/<uuid>` so the address bar carries
    // a unique, shareable URL and browser Back closes the note.
    await Navigator.of(context).pushNamed(
      '/note/$uuid',
      arguments: <String, dynamic>{'note': detail, 'token': _token},
    );
    // The popped route restored the underlying route's original name;
    // re-sync the address bar with the tab actually on screen.
    _syncTabUrl();
  }

  /// Follows a markdown link tapped in the note viewer. External links open
  /// in the browser; a relative in-course link resolves to a sibling note
  /// (by repo path relative to this note, else by slugified name) and opens
  /// it — the "seamless in-course navigation" of bug 8.
  Future<void> _followNoteLink(
      Map<String, dynamic> fromNote, String href) async {
    final raw = href.trim();
    if (raw.isEmpty) return;
    if (_isExternalLink(raw)) {
      url_strategy.browserRedirect(raw);
      return;
    }
    final courseId = _noteCourseIdOf(fromNote);
    if (courseId == null) {
      showMessage('Link not followed: this note is not part of a course.');
      return;
    }
    List<Map<String, dynamic>> siblings;
    try {
      siblings = await widget.client.getCourseNotes(courseId, token: _token);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      showMessage('Link not followed: Portal.UI/follow_link — $cause.');
      return;
    }
    final target = _matchNoteLinkTarget(fromNote, raw, siblings);
    if (target == null) {
      showMessage('No note in this course matches "$raw".');
      return;
    }
    await _openNoteViewer(target);
  }

  /// Streams the next course-notes page in (infinite scroll — no manual
  /// buttons). No-ops while a fetch is in flight or when exhausted.
  Future<void> _loadMoreCourseNotes() async {
    final course = _selectedCourse;
    final courseId = (course?['id'] as num?)?.toInt();
    if (courseId == null ||
        courseId < 0 ||
        !_courseNotesHasMore ||
        _courseNotesLoadingMore) {
      return;
    }
    _courseNotesLoadingMore = true;
    refreshState();
    try {
      final page = await widget.client.getCourseNotesPage(courseId,
          token: _token, limit: 20, offset: _courseNotesOffset);
      final rows = (page['results'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      _courseNotes = [..._courseNotes, ...rows];
      _courseNotesOffset += rows.length;
      _courseNotesHasMore = page['has_more'] == true && rows.isNotEmpty;
    } catch (_) {
      // Silent: the next scroll retries.
    }
    _courseNotesLoadingMore = false;
    refreshState();
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

/// True for links that should leave the app (browser navigation).
bool _isExternalLink(String href) {
  final lower = href.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('mailto:') ||
      lower.startsWith('tel:');
}

/// Course id a note belongs to, or null (front-page / uncategorized).
int? _noteCourseIdOf(Map<String, dynamic> note) {
  final direct = note['course_id'];
  if (direct is int) return direct;
  if (direct is String) return int.tryParse(direct);
  final course = note['course'];
  if (course is Map && course['id'] is int) return course['id'] as int;
  return null;
}

/// Resolves a relative link to a sibling note: repo-path resolution first
/// (relative to the source note's git_path), then a slugified-name match.
/// Top-level (pure) so both the in-shell viewer and the routed
/// `_NoteRoutePage` share one resolver.
Map<String, dynamic>? _matchNoteLinkTarget(
  Map<String, dynamic> fromNote,
  String href,
  List<Map<String, dynamic>> siblings,
) {
  var path = href.split('#').first.split('?').first.trim();
  if (path.isEmpty) return null;
  try {
    path = Uri.decodeFull(path);
  } catch (_) {
    // keep the raw path on a malformed escape
  }
  // Site builds link to rendered pages: `.html` maps back to the `.md`
  // source.
  if (path.toLowerCase().endsWith('.html')) {
    path = path.substring(0, path.length - 5);
  }

  // 1) Path-based: resolve relative to the source note's repo path.
  final fromPath = fromNote['git_path']?.toString() ?? '';
  if (fromPath.isNotEmpty) {
    String resolved;
    try {
      resolved = Uri(path: fromPath).resolveUri(Uri.parse(path)).path;
    } catch (_) {
      resolved = path;
    }
    resolved = resolved.replaceFirst(RegExp(r'^/+'), '');
    final candidates = <String>{
      resolved,
      '$resolved.md',
      resolved.endsWith('/') ? '${resolved}index.md' : '$resolved/index.md',
    };
    // Site-root-absolute links (`/cv/foundations/filters`) omit the
    // repo's content root (`docs/`); retry with the source note's
    // leading directory prefixed.
    if (path.startsWith('/') && fromPath.contains('/')) {
      final root = fromPath.split('/').first;
      final prefixed = '$root/${path.replaceFirst(RegExp(r'^/+'), '')}';
      candidates.addAll({
        prefixed,
        '$prefixed.md',
        prefixed.endsWith('/') ? '${prefixed}index.md' : '$prefixed/index.md',
      });
    }
    for (final note in siblings) {
      final gp = note['git_path']?.toString() ?? '';
      if (gp.isNotEmpty && candidates.contains(gp)) return note;
    }
  }

  // 2) Name-based: slugify the last path segment and match note['name'].
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty) {
    var last = segments.last;
    if (last.toLowerCase().endsWith('.md')) {
      last = last.substring(0, last.length - 3);
    }
    final wanted = _slugifyLinkText(last);
    if (wanted.isNotEmpty) {
      for (final note in siblings) {
        if ((note['name']?.toString() ?? '') == wanted) return note;
      }
    }
  }
  return null;
}

String _slugifyLinkText(String input) {
  final lower = input.trim().toLowerCase();
  final dashed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return dashed.replaceAll(RegExp(r'^-+|-+$'), '');
}
