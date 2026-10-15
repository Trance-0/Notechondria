part of notechondria_frontend;

/// Portal Settings page. Apple-style two-level navigation: a short
/// top-level page with grouped nav rows, each row pushing a dedicated
/// `_SettingsXxxPage` (see `settings_pages.dart`). The grouped-card
/// primitives live in `settings_build.dart`. Mirrors the editor's
/// structure (see `frontend/editor_app/lib/modules/settings.dart`)
/// while keeping every existing portal callback wired to its
/// existing widget — this is a structural reorganization, not a
/// behavior change.
class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.profile,
    required this.settings,
    required this.localSettings,
    required this.localStats,
    required this.deletedNotes,
    required this.onSave,
    required this.onLogout,
    required this.onLogin,
    this.onCasdoorLogin,
    this.casdoorOrgLoginUrl,
    this.onBindCasdoor,
    this.onUnlinkCasdoor,
    required this.onRestoreDeletedNote,
    required this.onEmptyDeletedNotes,
    required this.onCopyLogs,
    required this.onUploadAvatar,
    required this.onSyncLocalData,
    required this.onPullCloudData,
    required this.onClearLocalCache,
    required this.onClearLocalData,
    required this.onRestoreTemplateCourses,
    required this.localDraftCount,
    required this.localCourseCount,
    required this.uiLogs,
    this.onOpenLocalRecycleBin,
    this.localTrashedDraftCount = 0,
    this.localTrashedCourseCount = 0,
    this.onOfflineModeChanged,
    this.onApplyLocalSettings,
    this.apiBaseUrl,
    this.debugSnapshotListenable,
    this.debugHistoryListenable,
    this.debugLogController,
    this.onRotateApiKey,
    this.onSaveMcpSkill,
    this.githubSyncCardBuilder,
    this.onExportLocalData,
    this.onRestoreFromLocalImport,
    this.onReplayTour,
    this.currentLocale,
    this.onSetLocale,
    this.onProbeStorageArch,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic> localSettings;
  final Map<String, dynamic> localStats;
  final List<Map<String, dynamic>> deletedNotes;
  final Future<ActionFeedback> Function(
    String username,
    String email,
    String motto,
    String socialLink,
    String editorMode,
    String themePreset,
    String themeMode,
    String apiBaseUrl,
  ) onSave;
  final Future<void> Function() onLogout;
  final Future<ActionFeedback> Function(String email, String password) onLogin;

  /// Replays the first-run onboarding tour from the settings menu.
  /// Null hides the row.
  final VoidCallback? onReplayTour;

  /// Persisted Language value ('system' | 'en' | 'zh') and the
  /// apply-immediately callback. When both are non-null the Portal
  /// preferences subpage renders a Language row; picking a value fires
  /// `onSetLocale`, which persists `locale` and rebuilds the
  /// `MaterialApp` with the new locale (mirrors the editor).
  final String? currentLocale;
  final Future<void> Function(String locale)? onSetLocale;

  /// Probes the backend handshake for its media-storage architecture
  /// label, shown on the shared `StorageUsageCard`. Null hides the line.
  final Future<String?> Function()? onProbeStorageArch;

  /// Triggers Casdoor SSO. Null in shadow mode (no `CASDOOR_*` env
  /// vars). See `docs/integrations/casdoor-migration.md`.
  final VoidCallback? onCasdoorLogin;

  /// Casdoor org-login page URL, e.g.
  /// `https://auth.trance-0.com/login/notechondria`. Built in
  /// `_AppShellState` from the `endpoint` + `organization` fields
  /// returned by `/api/v1/auth/casdoor/config/`. Threaded into
  /// `AuthHub` so the "Login via third party" + "Sign up via
  /// Casdoor" CTAs can redirect the browser there. Null when the
  /// backend has no Casdoor config.
  final String? casdoorOrgLoginUrl;

  /// Triggers Casdoor account binding. Null in shadow mode.
  final VoidCallback? onBindCasdoor;
  final Future<void> Function()? onUnlinkCasdoor;
  final Future<void> Function(Map<String, dynamic> note) onRestoreDeletedNote;
  final Future<void> Function() onEmptyDeletedNotes;
  final Future<void> Function() onCopyLogs;
  final Future<ActionFeedback> Function() onUploadAvatar;
  final Future<ActionFeedback> Function({bool announce}) onSyncLocalData;
  final Future<ActionFeedback> Function() onPullCloudData;
  final Future<ActionFeedback> Function() onClearLocalCache;
  final Future<ActionFeedback> Function() onClearLocalData;
  final Future<ActionFeedback> Function() onRestoreTemplateCourses;

  /// Called when the user flips the offline-mode switch. The host
  /// app_shell is expected to persist the flag via
  /// `_applyLocalAppSettings({'offline_mode': bool})` and re-run
  /// `_loadInitialData` so the new mode takes effect immediately.
  final Future<void> Function(bool offlineMode)? onOfflineModeChanged;

  /// Persists a patch of local app settings (e.g. the startup-image
  /// preference) through the shell's normal settings pipeline.
  final Future<void> Function(Map<String, dynamic> patch)?
      onApplyLocalSettings;

  /// Opens the local recycle-bin browser.
  final Future<void> Function()? onOpenLocalRecycleBin;
  final int localTrashedDraftCount;
  final int localTrashedCourseCount;

  final int localDraftCount;
  final int localCourseCount;
  final List<String> uiLogs;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;
  final ValueListenable<List<ApiDebugSnapshot>>? debugHistoryListenable;
  final DebugLogController? debugLogController;
  final Future<Map<String, dynamic>> Function()? onRotateApiKey;

  /// Persists the user's MCP `skill.md` body to the backend Creator
  /// row. Returns an `ActionFeedback` so the section widget can show a
  /// snackbar reflecting success / failure. Null when the user is
  /// signed out or the field has not been wired yet.
  final Future<ActionFeedback> Function(String skillMd)? onSaveMcpSkill;

  /// Builder for the experimental GitHub-Sync card. Constructed in
  /// `app_shell` so the network callbacks bind to the authenticated
  /// client + token. Null when the user is signed out.
  final Widget Function()? githubSyncCardBuilder;
  final Future<void> Function()? onExportLocalData;
  final Future<void> Function()? onRestoreFromLocalImport;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _mottoController;
  late final TextEditingController _socialController;
  late final TextEditingController _apiBaseController;
  String _editorMode = 'P';
  String _themePreset = 'teal';
  String _themeMode = 'S';

  /// Feedback bus shared across the top-level Settings page and
  /// every pushed sub-page. Each long-running action
  /// (`_runMaintenanceAction`, `_submitSettings`,
  /// `_handleAvatarUpload`, ...) writes the `ActionFeedback` here, and
  /// every page that wants to surface it listens via
  /// `ValueListenableBuilder` (see `_FeedbackBanner` in
  /// `settings_build.dart`). Replaces the old `setState` field that
  /// only re-rendered the top page — sub-pages couldn't see errors
  /// from controls they hosted.
  final ValueNotifier<ActionFeedback?> _feedback = ValueNotifier(null);
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _socialLinkError;

  bool get _isAuthenticated =>
      widget.profile != null && widget.settings != null;

  bool get _isAdmin =>
      widget.profile?['is_superuser'] == true ||
      widget.settings?['is_superuser'] == true;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.settings?['username']?.toString() ??
          widget.profile?['username']?.toString() ??
          '',
    );
    _emailController = TextEditingController(
      text: widget.settings?['email']?.toString() ??
          widget.profile?['email']?.toString() ??
          '',
    );
    _mottoController = TextEditingController(
        text: widget.settings?['motto']?.toString() ?? '');
    _socialController = TextEditingController(
      text: widget.settings?['social_link']?.toString() ?? '',
    );
    _apiBaseController = TextEditingController(
      text: widget.localSettings['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          _defaultApiBaseUrl(),
    );
    _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
    _themePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
    _themeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
  }

  @override
  void didUpdateWidget(covariant _SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings ||
        oldWidget.profile != widget.profile) {
      _usernameController.text = widget.settings?['username']?.toString() ??
          widget.profile?['username']?.toString() ??
          '';
      _emailController.text = widget.settings?['email']?.toString() ??
          widget.profile?['email']?.toString() ??
          '';
      _mottoController.text = widget.settings?['motto']?.toString() ?? '';
      _socialController.text =
          widget.settings?['social_link']?.toString() ?? '';
      _editorMode = widget.settings?['editor_mode']?.toString() ?? _editorMode;
    }
    if (oldWidget.localSettings != widget.localSettings) {
      _apiBaseController.text =
          widget.localSettings['api_base_url']?.toString() ??
              widget.apiBaseUrl ??
              _defaultApiBaseUrl();
      _themePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
      _themeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _mottoController.dispose();
    _socialController.dispose();
    _apiBaseController.dispose();
    _feedback.dispose();
    super.dispose();
  }

  /// Shared `setState` wrapper for extensions — `setState` is
  /// `@protected` and invisible to extensions, so build helpers
  /// mutate state fields directly and then call this to trigger a
  /// rebuild. Same pattern used on `_AppShellState`.
  void refreshState() {
    if (mounted) setState(() {});
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _submitSettings() async {
    if (_saving) return;
    final social = _socialController.text.trim();
    if (social.isNotEmpty && !_isValidUrl(social)) {
      setState(() {
        _socialLinkError =
            AppLocalizations.of(context).settingsSocialLinkInvalid;
      });
      return;
    }
    setState(() {
      _saving = true;
      _socialLinkError = null;
    });
    _feedback.value = null;
    final feedback = await widget.onSave(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _mottoController.text.trim(),
      _socialController.text.trim(),
      _editorMode,
      _themePreset,
      _themeMode,
      _apiBaseController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
    });
    _feedback.value = feedback;
  }

  Future<void> _handleAvatarUpload() async {
    setState(() {
      _uploadingAvatar = true;
    });
    _feedback.value = null;
    final feedback = await widget.onUploadAvatar();
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadingAvatar = false;
    });
    _feedback.value = feedback;
  }

  Future<void> _runMaintenanceAction(
    Future<ActionFeedback> Function() action,
  ) async {
    _feedback.value = null;
    final feedback = await action();
    if (!mounted) {
      return;
    }
    _feedback.value = feedback;
  }

  Future<void> _openRecycleBinDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.settingsRecycleBinTitle),
          content: SizedBox(
            width: 560,
            child: widget.deletedNotes.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(l10n.settingsRecycleBinEmpty),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            await widget.onEmptyDeletedNotes();
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                          child: Text(l10n.settingsEmptyRecycleBin),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 320,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final note in widget.deletedNotes)
                              Card(
                                child: ListTile(
                                  title: Text(
                                    note['title']?.toString() ??
                                        l10n.noteUntitled,
                                  ),
                                  subtitle: Text(
                                    note['description']?.toString() ??
                                        note['excerpt']?.toString() ??
                                        '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: TextButton(
                                    onPressed: () async {
                                      await widget.onRestoreDeletedNote(note);
                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                                    child: Text(l10n.commonRestore),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonClose),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          AppLocalizations.of(context).settingsTitle,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _isAuthenticated
              ? AppLocalizations.of(context).settingsManageAccountPreferences
              : AppLocalizations.of(context).settingsLocalOnlyPreferences,
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<ActionFeedback?>(
          valueListenable: _feedback,
          builder: (context, feedback, _) {
            if (feedback == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FeedbackText(feedback: feedback),
            );
          },
        ),
        _buildOnlineAccountSection(context),
        const SizedBox(height: 16),
        _buildSettingsMenu(context),
        // 0.1.101: render the Debug log inline on the main Settings
        // scroll, matching the editor app's `_buildDebugSection`.
        // The "Debug" ListTile in `_buildSettingsMenu` still pushes
        // the focused subpage (`_DebugPage`); this card is the
        // at-a-glance surface so common ops ("copy logs", "ping
        // backend", scan recent UI events) don't require a nav
        // hop. See docs/versions/0.1.101.md.
        const SizedBox(height: 16),
        _buildInlineDebugCard(context),
        if (_isAuthenticated) ...[
          const SizedBox(height: 16),
          _buildLogoutCard(context),
        ],
      ],
    );
  }

  /// Inline Debug log card mirroring `editor_app`'s
  /// `_buildDebugSection`. When the host wired a `DebugLogController`
  /// (the modern path), render the shared `DebugLogCard` directly so
  /// users get the same level filter + terminal as on the focused
  /// `_DebugPage`. Otherwise fall back to a minimal frontend-log
  /// card so the surface degrades gracefully.
  Widget _buildInlineDebugCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = widget.debugLogController;
    final summary = l10n.settingsLocalDataCounts(
      widget.localDraftCount,
      widget.localCourseCount,
    );
    if (controller != null) {
      return DebugLogCard(
        controller: controller,
        title: l10n.debugLogTitle,
        summary: summary,
        onCopyLogs: widget.onCopyLogs,
        onPing: () => pingBackend(widget.apiBaseUrl),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.debugLogTitle,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onCopyLogs,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(l10n.debugCopyLogs),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(summary),
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: widget.uiLogs.isEmpty
                  ? Center(
                      child: Text(l10n.debugNoLogs),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: widget.uiLogs.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SelectableText(
                          widget.uiLogs[index],
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Apple-style settings menu card with rows for portal preferences,
  /// backend, local data, recycle bin, and debug. Each row pushes a
  /// dedicated sub-page (see `settings_pages.dart`).
  Widget _buildSettingsMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recoverableCount =
        widget.localTrashedDraftCount + widget.localTrashedCourseCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: Text(l10n.settingsPortalPreferences),
            subtitle: Text(l10n.settingsPortalPreferencesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _PortalPreferencesPage(parent: this),
                ),
              );
            },
          ),
          if (widget.onReplayTour != null) ...[
            const Divider(height: 0, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(l10n.settingsViewTutorial),
              subtitle: Text(l10n.settingsViewTutorialSubtitle),
              onTap: widget.onReplayTour,
            ),
          ],
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(l10n.settingsBackendTitle),
            subtitle: Text(
              widget.localSettings['offline_mode'] == true
                  ? l10n.settingsBackendOfflineSummary(
                      widget.apiBaseUrl ?? '—',
                    )
                  : l10n.settingsBackendOnlineSummary(
                      widget.apiBaseUrl ?? '—',
                    ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _BackendSettingsPage(parent: this),
                ),
              );
            },
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.settingsLocalDataTitle),
            subtitle: Text(
              l10n.settingsLocalDataSummary(
                widget.localDraftCount,
                widget.localCourseCount,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _LocalDataPage(parent: this),
                ),
              );
            },
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(l10n.settingsRecycleBinTitle),
            subtitle: Text(
              l10n.settingsRecycleBinSummary(
                recoverableCount,
                widget.deletedNotes.length,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _RecycleBinPage(parent: this),
                ),
              );
            },
          ),
          // 0.1.116: removed the duplicate "Debug" ListTile + its
          // _DebugPage push. The inline Debug log card on the main
          // Settings scroll (added in 0.1.105 via
          // `_buildInlineDebugCard`) now owns the only debug surface,
          // matching the editor app's pattern. The focused
          // `_DebugPage` and its subroute are still defined further
          // down the file in case a future surface re-introduces a
          // dedicated entry, but no settings menu row points at them.
        ],
      ),
    );
  }

  /// Destructive-styled Logout card — sits in its own card, full
  /// width, red text. Matches the iOS Settings convention of a
  /// destructive bottom action separated from the menu rows above.
  Widget _buildLogoutCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.logout, color: scheme.error),
        title: Text(
          l10n.settingsSignOut,
          style: TextStyle(
            color: scheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: () {
          widget.onLogout();
        },
      ),
    );
  }
}

/// Casdoor-only "Connected accounts" card. Per-provider Google /
/// GitHub bindings were retired in favor of letting Casdoor itself
/// proxy those identities via its application Providers tab.
class _ConnectedAccountsSection extends StatefulWidget {
  const _ConnectedAccountsSection({
    this.onBindCasdoor,
    this.onUnlinkCasdoor,
    this.casdoorLinked = false,
    this.casdoorOrgLoginUrl,
  });

  final VoidCallback? onBindCasdoor;
  final Future<void> Function()? onUnlinkCasdoor;
  final bool casdoorLinked;

  /// Org-themed Casdoor login page URL (e.g.
  /// `https://auth.trance-0.com/login/trance-0`). Built backend-
  /// side from `CASDOOR_ENDPOINT` + `CASDOOR_ORG_NAME` and threaded
  /// through the boot probe so the SPA never hard-codes it. Empty
  /// / null when the backend is in shadow mode.
  final String? casdoorOrgLoginUrl;

  @override
  State<_ConnectedAccountsSection> createState() =>
      _ConnectedAccountsSectionState();
}

class _ConnectedAccountsSectionState extends State<_ConnectedAccountsSection> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shadowMode = widget.onBindCasdoor == null;
    final manageUrl = widget.casdoorOrgLoginUrl ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.connectedAccountsTitle,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (shadowMode)
          Text(l10n.connectedAccountsShadow)
        else
          _buildCasdoorRow(context),
        if (manageUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => url_strategy.browserRedirect(manageUrl),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(l10n.connectedAccountsManageCasdoor),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          l10n.connectedAccountsUnavailableHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCasdoorRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final linked = widget.casdoorLinked;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.shield_outlined),
      title: Text(l10n.connectedAccountsCasdoorSso),
      subtitle: Text(
        linked ? l10n.connectedAccountsLinked : l10n.connectedAccountsNotLinked,
      ),
      dense: true,
      trailing: linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onBindCasdoor != null)
                  TextButton(
                    onPressed: widget.onBindCasdoor,
                    child: Text(l10n.connectedAccountsSwitch),
                  ),
                TextButton(
                  onPressed: widget.onUnlinkCasdoor == null
                      ? null
                      : () async {
                          try {
                            await widget.onUnlinkCasdoor!();
                          } catch (_) {}
                          if (mounted) setState(() {});
                        },
                  child: Text(
                    l10n.connectedAccountsUnlink,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            )
          : TextButton(
              onPressed: widget.onBindCasdoor,
              child: Text(l10n.connectedAccountsLinkCasdoor),
            ),
    );
  }
}
