part of notechondria_frontend;

extension _AppShellInboxMigrationX on _AppShellState {
  /// Auto-merge any legacy owned "Inbox" category into the synthetic
  /// uncategorized bucket. Pre-0.1.120 builds created a real "Inbox"
  /// `Course`; 0.1.120 made the uncategorized bucket a client-only
  /// render of `course_id == null` notes, so a leftover "Inbox"
  /// category renders as a confusing duplicate next to it.
  ///
  /// 0.1.131: this used to pop a dismissable prompt offering
  /// remove-vs-rename. Users dismissed it and lived with the duplicate
  /// indefinitely (the reported bug), so we now migrate silently —
  /// reparent the category's notes to uncategorized and delete the
  /// category — and surface the result as a SnackBar. The backend
  /// `cleanup_inbox_courses` management command does the same sweep
  /// server-side for existing databases. Runs once per session; after
  /// a successful pass there are no candidates left, and a failed pass
  /// (offline) retries next boot.
  Future<void> _autoMigrateLegacyInbox() async {
    if (_inboxMigrationPromptShown || !mounted) return;
    final token = _token;
    if (token == null || token.isEmpty) return;
    final candidates = _ownedInboxMigrationCandidates();
    if (candidates.isEmpty) return;
    _inboxMigrationPromptShown = true;
    await _mergeInboxIntoUncategorized(candidates);
  }

  List<Map<String, dynamic>> _ownedInboxMigrationCandidates() {
    final username = currentUsername?.trim().toLowerCase() ?? '';
    return [..._localCourses, ..._courses]
        .where((course) {
          final title = course['title']?.toString().trim().toLowerCase() ?? '';
          if (title != 'inbox') return false;
          if (isLocalCourse(course)) return true;
          if (username.isEmpty) return false;
          final owner = Map<String, dynamic>.from(
            course['owner'] as Map? ?? const {},
          );
          final ownerUsername =
              owner['username']?.toString().trim().toLowerCase() ?? '';
          return ownerUsername == username;
        })
        .map((course) => Map<String, dynamic>.from(course))
        .toList();
  }

  /// Reparent every note under the given legacy "Inbox" categories to
  /// the uncategorized bucket (`course_id == null`) and delete the
  /// categories. Cloud categories are removed via `deleteCourse`; the
  /// backend's `Note.course_id = SET_NULL` reparents their notes, so
  /// the client only has to delete the category and re-fetch.
  Future<void> _mergeInboxIntoUncategorized(
    List<Map<String, dynamic>> candidates,
  ) async {
    const source = 'Editor.DataMigration/inbox';
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      log(
        level: DebugLogLevel.info,
        source: source,
        message:
            'Inbox migration started: $source - ${candidates.length} legacy '
            'Inbox categor${candidates.length == 1 ? 'y' : 'ies'} found.',
      );
      final localIds = candidates
          .where(isLocalCourse)
          .map((course) => (course['id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      final cloudIds = candidates
          .where((course) => !isLocalCourse(course))
          .map((course) => (course['id'] as num?)?.toInt())
          .whereType<int>()
          .toList(growable: false);

      if (localIds.isNotEmpty) {
        _localDrafts = _localDrafts.map((draft) {
          final courseId = _draftCourseId(draft);
          if (courseId == null || !localIds.contains(courseId)) return draft;
          final metadata =
              _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
          metadata.remove('course_id');
          return {
            ...draft,
            'course_id': null,
            'metadata_json': jsonEncode(metadata),
          };
        }).toList(growable: false);
        _localCourses = _localCourses
            .where(
                (course) => !localIds.contains((course['id'] as num?)?.toInt()))
            .toList(growable: false);
        await persistLocalDrafts();
        await persistLocalCourses();
      }

      for (final courseId in cloudIds) {
        // Deleting the cloud category triggers Note.course_id=SET_NULL
        // server-side, dropping its notes into the uncategorized bucket.
        await timed(
          '$source.deleteCourse.$courseId',
          () => widget.client.deleteCourse(token, courseId),
        );
      }

      _courses = _courses
          .where(
              (course) => !cloudIds.contains((course['id'] as num?)?.toInt()))
          .toList(growable: false);
      _selectedCourse = null;
      _selectedCategoryId = null;
      await _persistLocalCache();
      await _loadInitialData();
      const message = 'Legacy Inbox merged: old Inbox categories were '
          'removed; their notes now live in the uncategorized bucket.';
      log(level: DebugLogLevel.info, source: source, message: message);
      showMessage(message);
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      final message = 'Inbox migration failed: $source - $cause.';
      log(level: DebugLogLevel.error, source: source, message: message);
      showMessage(message);
    }
  }
}
