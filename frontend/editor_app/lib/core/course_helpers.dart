part of notechondria_frontend;

/// App-specific course/category helpers. The byte-identical
/// `_isLocalCourse` / `_decorateRemoteCourse` / `_frontPageFallbackPayload`
/// methods moved into the shared `AppShellCourseHelpersMixin`
/// (notechondria_shared 0.1.79). Call sites use the public
/// `isLocalCourse()` / `decorateRemoteCourse()` /
/// `frontPageFallbackPayload()` names.
///
/// Two helpers stay here because they're either editor-only or
/// have a different signature on planner:
///   - `_chooseDefaultCourse` — editor + portal take a `frontPage`
///     param; planner doesn't. Lives per-app rather than diverging
///     the shared signature.
///   - `_localNotesForCourse` — editor-only; uses `_decodeNoteMetadata`
///     which is private to editor.
extension _AppShellCourseHelpersX on _AppShellState {
  Map<String, dynamic>? _chooseDefaultCourse({
    required List<Map<String, dynamic>> remoteCourses,
    required List<Map<String, dynamic>> localCourses,
    required Map<String, dynamic>? frontPage,
  }) {
    final retainedCourseId = (_selectedCourse?['id'] as num?)?.toInt();
    if (retainedCourseId != null) {
      for (final course in [...localCourses, ...remoteCourses]) {
        if ((course['id'] as num?)?.toInt() == retainedCourseId) {
          return Map<String, dynamic>.from(course);
        }
      }
    }
    final defaultCourse = frontPage?['default_course'] as Map<String, dynamic>?;
    if (defaultCourse != null && defaultCourse.isNotEmpty) {
      final defaultId = (defaultCourse['id'] as num?)?.toInt();
      for (final course in [...localCourses, ...remoteCourses]) {
        if ((course['id'] as num?)?.toInt() == defaultId) {
          return Map<String, dynamic>.from(course);
        }
      }
      return Map<String, dynamic>.from(defaultCourse);
    }
    if (localCourses.isNotEmpty) {
      return Map<String, dynamic>.from(localCourses.first);
    }
    if (remoteCourses.isNotEmpty) {
      return Map<String, dynamic>.from(remoteCourses.first);
    }
    return null;
  }

  List<Map<String, dynamic>> _localNotesForCourse(Map<String, dynamic> course) {
    final localId = (course['id'] as num?)?.toInt();
    final syncedId = (course['synced_course_id'] as num?)?.toInt();
    return _localDrafts
        .where((draft) {
          final metadata =
              _decodeNoteMetadata(draft['metadata_json']?.toString() ?? '{}');
          final courseId = (metadata['course_id'] as num?)?.toInt() ??
              (draft['course_id'] as num?)?.toInt();
          return courseId == localId ||
              (syncedId != null && courseId == syncedId);
        })
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }
}
