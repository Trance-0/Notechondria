part of notechondria_frontend;

/// First-run starter workspace seed.
extension _AppShellStarterX on _AppShellState {
  Future<void> _ensureStarterWorkspace() async {
    if (_courses.isNotEmpty ||
        _localCourses.isNotEmpty ||
        _localDrafts.isNotEmpty ||
        _plannerEvents.isNotEmpty) {
      return;
    }
    final starterCourse = _buildLocalCourse(
      title: 'Starter planning course',
      description: 'Offline planning workspace with module discussion and calendar items.',
    );
    final draftA = _buildLocalDraft(
      title: 'Module 1: Kickoff discussion',
      description: 'Local module discussion seed note.',
      content: '''# Module 1: Kickoff discussion

Use this as the root discussion note for the first module.

Add leaf notes as comments or follow-ups.''',
      editorMode: 'M',
      metadataJson: jsonEncode({
        'course_id': starterCourse['id'],
        'module_id': 'module-1',
        'module_title': 'Kickoff module',
        'module_description': 'Discussion board and planning seed for the first module.',
        'objectives': ['Define scope', 'Map first milestone'],
        'assignments': ['Review the discussion board', 'Schedule first work block'],
      }),
    );
    final draftB = _buildLocalDraft(
      title: 'Module 2: Scheduling notes',
      description: 'Local planning note for timeline work.',
      content: '''# Module 2: Scheduling notes

Capture deadlines, sequencing, and blockers here.''',
      editorMode: 'M',
      metadataJson: jsonEncode({
        'course_id': starterCourse['id'],
        'module_id': 'module-2',
        'module_title': 'Scheduling module',
        'module_description': 'Planning and scheduling discussion for the second module.',
        'objectives': ['Set deadlines', 'Track blockers'],
        'assignments': ['Draft the weekly calendar', 'Review dependencies'],
      }),
    );
    final now = _dateOnly(DateTime.now());
    _localCourses = [starterCourse];
    _localDrafts = [draftA, draftB];
    _plannerEvents = [
      _buildLocalPlannerEvent(
        title: 'Draft weekly study block',
        eventDate: now.add(const Duration(days: 1)).add(const Duration(hours: 10)),
        difficultyWeight: 2,
        description: 'Turn the module plan into a real calendar slot.',
        courseId: starterCourse['id'] as int,
      ),
      _buildLocalPlannerEvent(
        title: 'Review module discussion',
        eventDate: now.add(const Duration(days: 2)).add(const Duration(hours: 14)),
        difficultyWeight: 1,
        description: 'Summarize the local discussion notes and next actions.',
        courseId: starterCourse['id'] as int,
      ),
    ];
    _activityWeekStart = now;
    _activityWeek = _buildOfflineActivityWeek();
    _selectedCourse = starterCourse;
    _courseNotes = _localNotesForCourse(starterCourse);
    _localStats = {
      ..._localStats,
      'starter_workspace_seeded_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _persistLocalCourses();
    await _persistLocalDrafts();
    await _persistLocalStats();
    await _persistLocalCache();
    log(
      level: DebugLogLevel.info,
      source: 'Planner.LocalStore/seed_starter',
      message:
          'Starter workspace seeded: '
          'Planner.LocalStore/seed_starter \u2014 '
          'first-run offline course + 2 planning drafts + 2 events created.',
    );
  }
}
