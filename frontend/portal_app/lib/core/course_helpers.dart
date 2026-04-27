part of notechondria_frontend;

/// App-specific course helpers. The byte-identical `_isLocalCourse`,
/// `_decorateRemoteCourse`, and `_frontPageFallbackPayload` methods
/// moved into the shared `AppShellCourseHelpersMixin`
/// (notechondria_shared 0.1.79). Call sites use the public
/// `isLocalCourse()` / `decorateRemoteCourse()` /
/// `frontPageFallbackPayload()` names.
///
/// `_chooseDefaultCourse` stays here because portal's signature
/// matches editor's (with the `frontPage` parameter) but planner's
/// doesn't — sharing across all three would require a signature
/// divergence that the dedup doesn't justify.
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
}
