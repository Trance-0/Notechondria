import 'package:flutter/widgets.dart';

/// Course/category read-side helpers shared across `_AppShellState` in
/// editor / planner / portal. All three methods are pure projections
/// over course Maps + a couple of in-memory state fields — none call
/// `setState` or mutate fields, so they sit cleanly behind a mixin.
///
/// What this mixin owns (3 methods, byte-identical across apps that
/// use them):
///   - `isLocalCourse(course)` — is this course a locally-created
///     offline category? Negative-id rows AND `is_local_course == true`
///     rows both qualify.
///   - `decorateRemoteCourse(course)` — annotates a freshly-decoded
///     remote course with `is_local_course: false` and a computed
///     `is_owned` based on whether `course['owner']['username']`
///     matches the current user. Idempotent: re-decorating a row
///     that already has `is_owned: true` keeps it.
///   - `frontPageFallbackPayload(remoteCourses)` — synthesises a
///     plausible front-page payload from the first 3 remote (or
///     local, when remote is empty) courses. Used during initial
///     boot before the server has responded with a real
///     `/front-page/` payload.
///
/// What stays per-app:
///   - `chooseDefaultCourse(...)` — planner's signature lacks the
///     `frontPage` parameter (planner has no front-page concept), so
///     it diverges from editor/portal. Stays in each app's
///     `core/course_helpers.dart`.
///   - `localNotesForCourse(course)` — editor-only; uses
///     `_decodeNoteMetadata` which is private to editor.
///
/// Usage in `_AppShellState`:
/// ```dart
/// class _AppShellState extends State<AppShell>
///     with AppShellCourseHelpersMixin<AppShell> {
///   @override
///   String? get currentUsername => _profile?['username']?.toString();
///   @override
///   List<Map<String, dynamic>> get localCourses => _localCourses;
/// }
/// ```
mixin AppShellCourseHelpersMixin<W extends StatefulWidget> on State<W> {
  /// Username of the currently-signed-in user, or null/empty when
  /// signed out. Read once per `decorateRemoteCourse` call to compute
  /// the `is_owned` flag — case-insensitive match against the
  /// course's `owner.username`.
  String? get currentUsername;

  /// In-memory list of locally-created (offline) categories. The
  /// `frontPageFallbackPayload` method falls back to these when the
  /// remote course list is empty. Same getter shape as
  /// `AppShellLocalPersistMixin.localCourses`; if both mixins are in
  /// the `with` clause, a single override satisfies both.
  List<Map<String, dynamic>> get localCourses;

  /// True iff the course is a locally-created offline category.
  /// Two qualifying conditions, either is sufficient:
  ///   1. The Map carries `is_local_course: true` (set by
  ///      `_buildLocalCourse` and friends).
  ///   2. The course id is negative (offline ids are seeded from a
  ///      negative counter so they never collide with server ids).
  ///
  /// Returns false for null courses so callers can pass
  /// `_selectedCourse` without an explicit null check.
  bool isLocalCourse(Map<String, dynamic>? course) {
    if (course == null) return false;
    return course['is_local_course'] == true ||
        ((course['id'] as num?)?.toInt() ?? 0) < 0;
  }

  /// Annotates a freshly-decoded remote course Map with two derived
  /// flags:
  ///   - `is_local_course: false` — overrides any stale local flag
  ///     so a course that was promoted from local to cloud reads as
  ///     remote going forward.
  ///   - `is_owned` — true when the course's `owner.username`
  ///     (case-insensitive) matches `currentUsername`. Preserved if
  ///     already true, so re-decorating doesn't downgrade.
  ///
  /// Returns a new Map; the input is not mutated.
  Map<String, dynamic> decorateRemoteCourse(Map<String, dynamic> course) {
    final owner =
        Map<String, dynamic>.from(course['owner'] as Map? ?? const {});
    final username = currentUsername ?? '';
    final isOwned = username.isNotEmpty &&
        owner['username']?.toString().toLowerCase() == username.toLowerCase();
    return {
      ...course,
      'is_local_course': false,
      'is_owned': course['is_owned'] == true || isOwned,
    };
  }

  /// Synthesises a plausible front-page payload from the first 3
  /// remote courses (or local courses when remote is empty). Used
  /// during initial boot before the server has responded with a real
  /// `/front-page/` payload — keeps the front-page UI from rendering
  /// blank during the first few hundred milliseconds.
  ///
  /// Editor and portal both call this; planner doesn't have a
  /// front-page surface and never invokes it.
  Map<String, dynamic> frontPageFallbackPayload(
    List<Map<String, dynamic>> remoteCourses,
  ) {
    final fallbackCourses = remoteCourses.isNotEmpty
        ? remoteCourses.take(3).toList()
        : localCourses.take(3).toList();
    return {
      'default_course':
          fallbackCourses.isNotEmpty ? fallbackCourses.first : null,
      'carousel_courses': fallbackCourses,
      'collections': fallbackCourses,
      'recent_notes': const <Map<String, dynamic>>[],
      'recommended_notes': const <Map<String, dynamic>>[],
    };
  }
}
