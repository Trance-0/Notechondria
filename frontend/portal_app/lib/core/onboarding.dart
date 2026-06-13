part of notechondria_frontend;

/// First-run onboarding tour steps for this app. Layout-agnostic
/// (concept cards, not anchored coach marks) so the same content
/// renders identically on the mobile drawer layout and the desktop
/// sidebar layout. See `showOnboardingTour`.
const _kOnboardingSteps = <TourStep>[
  TourStep(
    icon: Icons.dashboard_customize_outlined,
    title: 'Welcome to Notechondria',
    body: 'Your hub for notes, planning, and public courses.',
  ),
  TourStep(
    icon: Icons.explore_outlined,
    title: 'Explore public notes',
    body: 'Browse public courses and notes right from the front page.',
  ),
  TourStep(
    icon: Icons.open_in_new,
    title: 'Open the apps',
    body:
        'Jump into the Editor or Planner anytime. Sign in to sync your own work.',
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
      appTitle: 'Notechondria Portal',
      steps: _kOnboardingSteps,
    );
    if (stampSeen && mounted) {
      _localStats = {..._localStats, 'onboarding_seen': true};
      await persistLocalStats();
    }
  }
}
