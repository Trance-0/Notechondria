part of notechondria_frontend;

/// App-specific course helpers. The byte-identical `_isLocalCourse`
/// and `_decorateRemoteCourse` methods moved into the shared
/// `AppShellCourseHelpersMixin` (notechondria_shared 0.1.79). Call
/// sites use the public `isLocalCourse()` / `decorateRemoteCourse()`
/// names.
///
/// `_chooseDefaultCourse` stays here because planner's signature
/// lacks the `frontPage` parameter that editor and portal share —
/// planner has no front-page surface to consult.
///
/// `_frontPageFallbackPayload` is not used by planner and so isn't
/// declared here at all (the shared mixin still owns it for
/// editor / portal).
extension _AppShellCourseHelpersX on _AppShellState {
  Map<String, dynamic>? _chooseDefaultCourse({
    required List<Map<String, dynamic>> remoteCourses,
    required List<Map<String, dynamic>> localCourses,
  }) {
    final retainedCourseId = (_selectedCourse?['id'] as num?)?.toInt();
    if (retainedCourseId != null) {
      for (final course in [...localCourses, ...remoteCourses]) {
        if ((course['id'] as num?)?.toInt() == retainedCourseId) {
          return Map<String, dynamic>.from(course);
        }
      }
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
