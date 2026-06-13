part of notechondria_frontend;

/// First-run onboarding tour steps for this app. Layout-agnostic
/// (concept cards, not anchored coach marks) so the same content
/// renders identically on the mobile drawer layout and the desktop
/// sidebar layout. See `showOnboardingTour`.
const _kOnboardingSteps = <TourStep>[
  TourStep(
    icon: Icons.event_note,
    title: 'Welcome to Notechondria Planner',
    body: 'Track courses, deadlines, and your study activity in one place.',
  ),
  TourStep(
    icon: Icons.calendar_month,
    title: 'Courses & deadlines',
    body:
        'Add courses and planner events; upcoming deadlines surface on your dashboard.',
  ),
  TourStep(
    icon: Icons.cloud_sync_outlined,
    title: 'Plan anywhere',
    body: 'Works offline. Sign in to sync your plan across devices.',
  ),
  TourStep(
    icon: Icons.tune,
    title: 'Settings & tools',
    body:
        'Themes, sync, and tools live in Settings. On phones, open the menu from the top-left.',
  ),
];

extension _AppShellOnboardingX on _AppShellState {
  /// Show the first-run tour once, tracked by the `onboarding_seen`
  /// local-stats flag. Returns true when the tour is being shown this
  /// boot so the caller can suppress the What's-New / install nudges
  /// (a brand-new user should meet the tour first, not three overlays
  /// at once).
  bool _maybeShowOnboarding() {
    if (!mounted || _localStats['onboarding_seen'] == true) return false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runOnboarding(stampSeen: true));
    });
    return true;
  }

  /// Replay the tour from the Settings entry point. Leaves the
  /// `onboarding_seen` flag set (the user has, by definition, seen it).
  void _replayOnboarding() {
    if (!mounted) return;
    unawaited(_runOnboarding(stampSeen: false));
  }

  Future<void> _runOnboarding({required bool stampSeen}) async {
    await showOnboardingTour(
      context,
      appTitle: 'Notechondria Planner',
      steps: _kOnboardingSteps,
    );
    if (stampSeen && mounted) {
      _localStats = {..._localStats, 'onboarding_seen': true};
      await persistLocalStats();
    }
  }
}
