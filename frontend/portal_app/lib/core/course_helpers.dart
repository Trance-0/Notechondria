part of notechondria_frontend;

/// Course helpers.
extension _AppShellCourseHelpersX on _AppShellState {
  bool _isLocalCourse(Map<String, dynamic>? course) {
    if (course == null) {
      return false;
    }
    return course['is_local_course'] == true ||
        ((course['id'] as num?)?.toInt() ?? 0) < 0;
  }

  Map<String, dynamic> _decorateRemoteCourse(Map<String, dynamic> course) {
    final owner = Map<String, dynamic>.from(course['owner'] as Map? ?? const {});
    final username = _profile?['username']?.toString() ?? '';
    final isOwned = username.isNotEmpty &&
        owner['username']?.toString().toLowerCase() == username.toLowerCase();
    return {
      ...course,
      'is_local_course': false,
      'is_owned': course['is_owned'] == true || isOwned,
    };
  }

  Map<String, dynamic> _frontPageFallbackPayload(
    List<Map<String, dynamic>> remoteCourses,
  ) {
    final fallbackCourses =
        remoteCourses.isNotEmpty ? remoteCourses.take(3).toList() : _localCourses.take(3).toList();
    return {
      'default_course': fallbackCourses.isNotEmpty ? fallbackCourses.first : null,
      'carousel_courses': fallbackCourses,
      'collections': fallbackCourses,
      'recent_notes': const <Map<String, dynamic>>[],
      'recommended_notes': const <Map<String, dynamic>>[],
    };
  }

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
