part of notechondria_frontend;

/// First-run onboarding tour steps for this app. Layout-agnostic
/// (concept cards, not anchored coach marks) so the same content
/// renders identically on the mobile drawer layout and the desktop
/// sidebar layout. Built from `AppLocalizations` so the tour follows
/// the app's Language setting. See `showOnboardingTour`.
List<TourStep> _onboardingSteps(AppLocalizations l10n) => <TourStep>[
      TourStep(
        icon: Icons.edit_note,
        title: l10n.tourEditorWelcomeTitle,
        body: l10n.tourEditorWelcomeBody,
      ),
      TourStep(
        icon: Icons.folder_outlined,
        title: l10n.tourEditorCategoriesTitle,
        body: l10n.tourEditorCategoriesBody,
      ),
      TourStep(
        icon: Icons.cloud_sync_outlined,
        title: l10n.tourEditorSyncTitle,
        body: l10n.tourEditorSyncBody,
      ),
      TourStep(
        icon: Icons.tune,
        title: l10n.tourEditorToolsTitle,
        body: l10n.tourEditorToolsBody,
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
      appTitle: 'Notechondria Editor',
      steps: _onboardingSteps(AppLocalizations.of(context)),
    );
    if (stampSeen && mounted) {
      _localStats = {..._localStats, 'onboarding_seen': true};
      await persistLocalStats();
    }
  }
}
