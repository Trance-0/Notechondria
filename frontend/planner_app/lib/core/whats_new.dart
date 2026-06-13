part of notechondria_frontend;

/// App id key used in `Creator.last_seen_versions` on the backend and
/// in the local stats map. Stable — changing it would re-show old
/// updates to every user.
const _kWhatsNewAppId = 'planner';

/// Per-version feature registry rendered by the shared What's-New
/// overlay. Append an entry whenever a round ships a user-visible
/// planner feature; keep descriptions to one or two sentences. Entries
/// older than the user's last seen version are filtered out by
/// `selectMissedUpdates`, so this list only ever grows.
const _kFeatureUpdates = <FeatureUpdate>[
  FeatureUpdate(
    version: '0.1.125',
    title: 'Faster boot diagnostics',
    description: 'The debug log now records how long each planner '
        'bootstrap step took, making slow connections easier to spot.',
    icon: Icons.speed_outlined,
  ),
  FeatureUpdate(
    version: '0.1.127',
    title: 'Password fallback stays in sync',
    description: 'Signing in with email/password now verifies against '
        'your Casdoor password and keeps a local copy so login works '
        'even when the auth server is down.',
    icon: Icons.key_outlined,
  ),
  FeatureUpdate(
    version: '0.1.127',
    title: 'Feature update cards',
    description: 'After an app update, missed features show up in this '
        'overlay once. Skipping marks them as seen.',
    icon: Icons.new_releases_outlined,
  ),
  FeatureUpdate(
    version: '0.1.129',
    title: 'Add to your Home Screen',
    description: 'Each app now has its own icon and, on phones, suggests '
        'adding it to your Home Screen — an app-like window plus storage '
        'the browser won’t evict.',
    icon: Icons.add_to_home_screen,
  ),
];

extension _AppShellWhatsNewX on _AppShellState {
  /// Show the What's-New overlay when the running build is newer than
  /// the user's recorded `last_seen_version` (local stats for everyone,
  /// `Creator.last_seen_versions[appId]` for signed-in users — the
  /// higher of the two wins so a second device doesn't replay updates
  /// already seen elsewhere). Fresh installs stamp silently.
  Future<void> _maybeShowWhatsNew() async {
    if (_whatsNewPromptShown || !mounted) return;
    const current = _kAppVersion;
    final localSeen = _localStats['last_seen_version']?.toString() ?? '';
    final profileMap = Map<String, dynamic>.from(
      _profile?['last_seen_versions'] as Map? ?? const {},
    );
    final profileSeen = profileMap[_kWhatsNewAppId]?.toString() ?? '';
    var lastSeen = localSeen;
    if (compareAppVersions(profileSeen, lastSeen) > 0) lastSeen = profileSeen;
    if (lastSeen.isEmpty) {
      await _stampWhatsNewVersion(current);
      return;
    }
    if (compareAppVersions(lastSeen, current) >= 0) return;
    final missed = selectMissedUpdates(
      registry: _kFeatureUpdates,
      lastSeenVersion: lastSeen,
      currentVersion: current,
    );
    if (missed.isEmpty) {
      await _stampWhatsNewVersion(current);
      return;
    }
    _whatsNewPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        final acknowledged = await showWhatsNewOverlay(
          context,
          appTitle: 'Notechondria Planner',
          currentVersion: current,
          updates: missed,
        );
        await _stampWhatsNewVersion(current);
        log(
          level: DebugLogLevel.info,
          source: 'Planner.UI',
          message:
              'Feature updates ${acknowledged ? 'acknowledged' : 'skipped'}: '
              'Planner.UI/whats_new — ${missed.length} update(s) since '
              '$lastSeen marked seen at $current.',
        );
      }());
    });
  }

  /// Stamp [version] as seen: always in local stats, and best-effort
  /// onto the signed-in profile (`PATCH /settings/` merges per-app
  /// keys server-side, so editor cannot clobber planner's entry).
  Future<void> _stampWhatsNewVersion(String version) async {
    _localStats = {..._localStats, 'last_seen_version': version};
    await persistLocalStats();
    final token = _token;
    if (token == null || token.isEmpty) return;
    try {
      await widget.client.updateSettings(token, {
        'last_seen_versions': {_kWhatsNewAppId: version},
      });
      if (_profile != null) {
        final merged = Map<String, dynamic>.from(
          _profile?['last_seen_versions'] as Map? ?? const {},
        );
        merged[_kWhatsNewAppId] = version;
        _profile = {..._profile!, 'last_seen_versions': merged};
      }
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.warning,
        source: 'Planner.Sync.Settings',
        message: 'Seen-version not saved to profile: '
            'Planner.Sync.Settings/save — $cause. The overlay will not '
            're-show on this device (local stamp succeeded).',
      );
    }
  }

  /// Post-boot Add-to-Home-Screen / data-durability nudge for
  /// mobile-web visitors. No-op on native builds, installed PWAs,
  /// desktop, and after one dismissal. See `maybeShowInstallBanner`.
  void _maybeShowInstallBanner() {
    if (!mounted || _localStats['install_hint_dismissed'] == true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowInstallBanner(
        context,
        dismissed: _localStats['install_hint_dismissed'] == true,
        isSignedIn: (_token ?? '').isNotEmpty,
        hasLocalDrafts: _localDrafts.isNotEmpty,
        onDismiss: () async {
          _localStats = {..._localStats, 'install_hint_dismissed': true};
          await persistLocalStats();
        },
      );
    });
  }
}
