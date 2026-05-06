part of notechondria_frontend;

/// Editor-focused settings page with login/sync, profile, app preferences,
/// config file download, and a simplified debug log.
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
    required this.onRestoreDeletedNote,
    required this.onEmptyDeletedNotes,
    required this.onCopyLogs,
    required this.onUploadAvatar,
    required this.onSyncLocalData,
    required this.onPullCloudData,
    required this.onClearLocalData,
    required this.onRestoreTemplateCourses,
    required this.onRestoreLocalStarterTemplate,
    required this.localDraftCount,
    required this.localCourseCount,
    required this.uiLogs,
    this.onCasdoorLogin,
    this.casdoorOrgLoginUrl,
    this.onBindCasdoor,
    this.onUnlinkCasdoor,
    this.onRotateApiKey,
    this.onSaveMcpSkill,
    this.githubSyncCardBuilder,
    this.onExportLocalData,
    this.onRestoreFromLocalImport,
    this.onOpenLocalRecycleBin,
    this.localTrashedDraftCount = 0,
    this.localTrashedCourseCount = 0,
    this.onOfflineModeChanged,
    this.apiBaseUrl,
    this.debugSnapshotListenable,
    this.debugHistoryListenable,
    this.debugLogController,
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
    String apiBaseUrl, {
    String firstName,
    String lastName,
    // 0.1.120: per-account label for the synthetic uncategorized
    // bucket. Optional — empty value passes "no change" through to
    // the backend so legacy callers compile unchanged.
    String uncategorizedFolderName,
  }) onSave;
  final Future<void> Function() onLogout;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  /// Triggers the Casdoor SSO flow. Null when the backend reports
  /// `configured: false` from `/auth/casdoor/config/` (shadow mode).
  /// See `docs/integrations/casdoor-migration.md`.
  final VoidCallback? onCasdoorLogin;

  /// Casdoor org-login page URL, e.g.
  /// `https://auth.trance-0.com/login/notechondria`. Built in
  /// `_AppShellState` from the `endpoint` + `organization` fields
  /// returned by `/api/v1/auth/casdoor/config/`. Backs the "Login via
  /// third party" button and the "Sign up via Casdoor" link in the
  /// signed-out account card. Empty / null when the backend hasn't
  /// reported a Casdoor config — both CTAs collapse in that state.
  final String? casdoorOrgLoginUrl;

  /// Triggers `launchOAuth('casdoor', intent: 'bind')`. Null in
  /// shadow mode. See `docs/integrations/casdoor-migration.md`.
  final VoidCallback? onBindCasdoor;

  /// Calls the unlink endpoint. Null in shadow mode.
  final Future<void> Function()? onUnlinkCasdoor;
  final Future<void> Function(Map<String, dynamic> note) onRestoreDeletedNote;
  final Future<void> Function() onEmptyDeletedNotes;
  final Future<void> Function() onCopyLogs;
  final Future<ActionFeedback> Function() onUploadAvatar;
  final Future<ActionFeedback> Function({bool announce}) onSyncLocalData;
  final Future<ActionFeedback> Function() onPullCloudData;
  final Future<ActionFeedback> Function() onClearLocalData;
  final Future<ActionFeedback> Function() onRestoreTemplateCourses;

  /// Re-seeds the local-only starter Inbox + welcome note. Always
  /// available regardless of online state — distinct from the admin-
  /// only `onRestoreTemplateCourses` which seeds the remote 3-course
  /// template catalog.
  final Future<ActionFeedback> Function() onRestoreLocalStarterTemplate;
  final Future<Map<String, dynamic>> Function()? onRotateApiKey;

  /// Persists the user's MCP `skill.md` body to the backend Creator
  /// row. Returns an `ActionFeedback` so the section widget can show a
  /// snackbar reflecting success / failure. Null when the user is
  /// signed out or the field has not been wired yet.
  final Future<ActionFeedback> Function(String skillMd)? onSaveMcpSkill;

  /// Builder for the experimental GitHub-Sync card. Constructed in
  /// the host `app_shell` so the network callbacks bind to the
  /// authenticated client + token. Null when the user is signed out;
  /// the API-settings page renders a passive disabled card in that
  /// case.
  final Widget Function()? githubSyncCardBuilder;
  /// Exports every persisted local bucket as a versioned `.nchron`
  /// zip package (v1, see `docs/export_format_v1.md`). Replaces the
  /// minimal `.env` config download.
  final Future<void> Function()? onExportLocalData;

  /// Imports a `.nchron` package selected by the user via the
  /// platform file picker. Shows a preview + delay-confirm dialog
  /// before replacing local state.
  final Future<void> Function()? onRestoreFromLocalImport;

  /// Opens the local recycle-bin browser where the user can restore
  /// drafts / categories that were moved to the client-side trash
  /// after a successful cloud sync. Populated by
  /// `_moveDraftToLocalTrash` / `_moveCourseToLocalTrash` in
  /// app_shell; entries auto-prune after 30 days.
  final Future<void> Function()? onOpenLocalRecycleBin;

  /// Recycle-bin counts so the Settings UI can render a badge
  /// ("Local recycle bin (3)") without re-reading SharedPreferences.
  final int localTrashedDraftCount;
  final int localTrashedCourseCount;

  /// Called when the user flips the offline-mode switch. The host
  /// app_shell is expected to persist the flag via
  /// `_applyLocalAppSettings({'offline_mode': bool})` and re-run
  /// `_loadInitialData` so the new mode takes effect immediately.
  final Future<void> Function(bool offlineMode)? onOfflineModeChanged;

  final int localDraftCount;
  final int localCourseCount;
  final List<String> uiLogs;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;
  final ValueListenable<List<ApiDebugSnapshot>>? debugHistoryListenable;

  /// Structured debug-log controller. When supplied the debug section
  /// renders the shared `DebugLogCard` (level filter + terminal); otherwise
  /// it falls back to the legacy string-list view.
  final DebugLogController? debugLogController;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _usernameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _mottoController;
  late final TextEditingController _socialController;
  late final TextEditingController _apiBaseController;
  // 0.1.120: per-account label for the synthetic uncategorized
  // folder rendered at the top of the sidebar. Changes go through
  // `widget.onSave` like other profile fields.
  late final TextEditingController _uncategorizedFolderNameController;
  String _editorMode = 'P';
  String _themePreset = 'teal';
  String _themeMode = 'S';

  // 0.1.120: `_showLegacyAuthFallback` + `toggleLegacyAuthFallback`
  // dropped along with the in-line auth surface. The shared `AuthHub`
  // owns the email/password expander state internally now.

  /// Feedback bus shared across the top-level Settings page and every
  /// pushed sub-page. Each long-running action (`_runMaintenanceAction`,
  /// `_submitSettings`, `_handleAvatarUpload`, ...) writes the
  /// `ActionFeedback` here, and every page that wants to surface it
  /// listens via `ValueListenableBuilder`. Replaces the old `setState`
  /// field that only re-rendered the top page — sub-pages couldn't see
  /// errors from controls they hosted.
  final ValueNotifier<ActionFeedback?> _feedback = ValueNotifier(null);
  bool _saving = false;
  String? _socialLinkError;
  bool _uploadingAvatar = false;
  bool get _isAuthenticated => widget.profile != null && widget.settings != null;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.settings?['username']?.toString() ??
          widget.profile?['username']?.toString() ??
          '',
    );
    _firstNameController = TextEditingController(
      text: widget.settings?['first_name']?.toString() ??
          widget.profile?['first_name']?.toString() ??
          '',
    );
    _lastNameController = TextEditingController(
      text: widget.settings?['last_name']?.toString() ??
          widget.profile?['last_name']?.toString() ??
          '',
    );
    _mottoController =
        TextEditingController(text: widget.settings?['motto']?.toString() ?? '');
    _socialController = TextEditingController(
      text: widget.settings?['social_link']?.toString() ?? '',
    );
    _apiBaseController = TextEditingController(
      text: widget.localSettings['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          _defaultApiBaseUrl(),
    );
    _uncategorizedFolderNameController = TextEditingController(
      text:
          widget.settings?['uncategorized_folder_name']?.toString() ?? 'Inbox',
    );
    _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
    if (_editorMode == 'B') _editorMode = 'G'; // block editor removed
    _themePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
    _themeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
  }

  @override
  void didUpdateWidget(covariant _SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings || oldWidget.profile != widget.profile) {
      _usernameController.text = widget.settings?['username']?.toString() ??
          widget.profile?['username']?.toString() ??
          '';
      _firstNameController.text = widget.settings?['first_name']?.toString() ??
          widget.profile?['first_name']?.toString() ??
          '';
      _lastNameController.text = widget.settings?['last_name']?.toString() ??
          widget.profile?['last_name']?.toString() ??
          '';
      _mottoController.text = widget.settings?['motto']?.toString() ?? '';
      _socialController.text = widget.settings?['social_link']?.toString() ?? '';
      _uncategorizedFolderNameController.text =
          widget.settings?['uncategorized_folder_name']?.toString() ??
              _uncategorizedFolderNameController.text;
      _editorMode = widget.settings?['editor_mode']?.toString() ?? _editorMode;
    }
    if (oldWidget.localSettings != widget.localSettings) {
      _apiBaseController.text = widget.localSettings['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          _defaultApiBaseUrl();
      _themePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
      _themeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _mottoController.dispose();
    _socialController.dispose();
    _apiBaseController.dispose();
    _uncategorizedFolderNameController.dispose();
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

  /// Whether any profile (online account) field has been edited.
  bool get _hasProfileChanges {
    final s = widget.settings ?? const {};
    final p = widget.profile ?? const {};
    final serverFirstName = s['first_name']?.toString() ?? p['first_name']?.toString() ?? '';
    final serverLastName = s['last_name']?.toString() ?? p['last_name']?.toString() ?? '';
    final serverMotto = s['motto']?.toString() ?? '';
    final serverSocial = s['social_link']?.toString() ?? '';
    final serverUncategorized =
        s['uncategorized_folder_name']?.toString() ?? 'Inbox';
    return _firstNameController.text.trim() != serverFirstName ||
        _lastNameController.text.trim() != serverLastName ||
        _mottoController.text.trim() != serverMotto ||
        _socialController.text.trim() != serverSocial ||
        _uncategorizedFolderNameController.text.trim() != serverUncategorized;
  }

  /// Restores profile fields to server values.
  void _cancelProfileChanges() {
    final s = widget.settings ?? const {};
    final p = widget.profile ?? const {};
    setState(() {
      _firstNameController.text = s['first_name']?.toString() ?? p['first_name']?.toString() ?? '';
      _lastNameController.text = s['last_name']?.toString() ?? p['last_name']?.toString() ?? '';
      _mottoController.text = s['motto']?.toString() ?? '';
      _socialController.text = s['social_link']?.toString() ?? '';
      _uncategorizedFolderNameController.text =
          s['uncategorized_folder_name']?.toString() ?? 'Inbox';
    });
  }

  /// Collects pending changes between the current form state and the server
  /// profile so the Save confirmation can list what will be written.
  Map<String, String> _pendingChanges() {
    final changes = <String, String>{};
    final s = widget.settings ?? const {};
    final p = widget.profile ?? const {};
    final serverFirstName = s['first_name']?.toString() ?? p['first_name']?.toString() ?? '';
    final serverLastName = s['last_name']?.toString() ?? p['last_name']?.toString() ?? '';
    final serverMotto = s['motto']?.toString() ?? '';
    final serverSocial = s['social_link']?.toString() ?? '';
    final serverEditorMode = s['editor_mode']?.toString() ?? 'P';
    final localThemePreset =
        widget.localSettings['theme_preset']?.toString() ?? 'teal';
    final localThemeMode =
        widget.localSettings['theme_mode']?.toString() ?? 'S';
    final localApiBase = widget.localSettings['api_base_url']?.toString() ??
        widget.apiBaseUrl ??
        _defaultApiBaseUrl();

    if (_firstNameController.text.trim() != serverFirstName) {
      changes['First name'] =
          '"${serverFirstName.isEmpty ? "(empty)" : serverFirstName}" \u2192 "${_firstNameController.text.trim()}"';
    }
    if (_lastNameController.text.trim() != serverLastName) {
      changes['Last name'] =
          '"${serverLastName.isEmpty ? "(empty)" : serverLastName}" \u2192 "${_lastNameController.text.trim()}"';
    }
    if (_mottoController.text.trim() != serverMotto) {
      changes['Motto'] =
          '"${serverMotto.isEmpty ? "(empty)" : serverMotto}" \u2192 "${_mottoController.text.trim()}"';
    }
    if (_socialController.text.trim() != serverSocial) {
      changes['Social link'] =
          '"${serverSocial.isEmpty ? "(empty)" : serverSocial}" \u2192 "${_socialController.text.trim()}"';
    }
    final serverUncategorized =
        s['uncategorized_folder_name']?.toString() ?? 'Inbox';
    if (_uncategorizedFolderNameController.text.trim() != serverUncategorized) {
      changes['Uncategorized folder name'] =
          '"$serverUncategorized" \u2192 "${_uncategorizedFolderNameController.text.trim()}"';
    }
    if (_editorMode != serverEditorMode) {
      changes['Default editor'] = '$serverEditorMode \u2192 $_editorMode';
    }
    if (_themePreset != localThemePreset) {
      changes['Theme preset'] = '$localThemePreset \u2192 $_themePreset';
    }
    if (_themeMode != localThemeMode) {
      changes['Theme mode'] = '$localThemeMode \u2192 $_themeMode';
    }
    if (_apiBaseController.text.trim() != localApiBase) {
      changes['API base URL'] = localApiBase.isEmpty
          ? '\u2192 "${_apiBaseController.text.trim()}"'
          : '"$localApiBase" \u2192 "${_apiBaseController.text.trim()}"';
    }
    return changes;
  }

  /// Builds a save/cancel button row for a settings section.
  Widget _buildSectionButtons({
    required bool hasChanges,
    required VoidCallback onCancel,
  }) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _confirmAndSave,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: hasChanges ? onCancel : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: hasChanges ? null : Theme.of(context).colorScheme.outline,
            ),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  /// Prompts the user with a summary of what changed, then saves if confirmed.
  Future<void> _confirmAndSave() async {
    final changes = _pendingChanges();
    if (changes.isEmpty) {
      _feedback.value = const ActionFeedback(message: 'No changes to save.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save settings?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('The following changes will be saved:'),
            const SizedBox(height: 12),
            for (final entry in changes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '\u2022 ${entry.key}: ${entry.value}',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _submitSettings();
    }
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Auto-save hook used by the Apple-style sub-pages — every theme /
  /// editor-mode pick on a sub-page calls this so the change persists
  /// across restarts without forcing the user back to a Save button.
  /// Delegates to `_submitSettings` which already pushes every field
  /// (profile + preferences + apiBase) to the host. The host figures
  /// out which buckets actually changed; sending unchanged values is
  /// idempotent and cheap.
  Future<void> _autoSavePreferences() async {
    await _submitSettings();
  }

  Future<void> _submitSettings() async {
    if (_saving) return;
    final social = _socialController.text.trim();
    if (social.isNotEmpty && !_isValidUrl(social)) {
      setState(() => _socialLinkError = 'Must be a valid URL (https://...)');
      return;
    }
    setState(() {
      _saving = true;
      _socialLinkError = null;
    });
    _feedback.value = null;
    final feedback = await widget.onSave(
      _usernameController.text.trim(),
      widget.profile?['email']?.toString() ?? '',
      _mottoController.text.trim(),
      _socialController.text.trim(),
      _editorMode,
      _themePreset,
      _themeMode,
      _apiBaseController.text.trim(),
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      uncategorizedFolderName: _uncategorizedFolderNameController.text.trim(),
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

  /// Destructive confirmation for "Clear all local data" — blocks the confirm
  /// button for 3 seconds so the user cannot tap through reflexively.
  Future<void> _confirmClearAllLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const ConfirmWithDelayDialog(
        title: 'Clear all local data?',
        message:
            'This removes every local draft and local category from this device. Notes already synced to the cloud are not affected.',
        confirmLabel: 'Clear all',
        delaySeconds: 3,
      ),
    );
    if (confirmed == true) {
      await _runMaintenanceAction(widget.onClearLocalData);
    }
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
      builder: (context) => AlertDialog(
        title: const Text('Recycle bin'),
        content: SizedBox(
          width: 560,
          child: widget.deletedNotes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Recycle bin is empty.'),
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
                        child: const Text('Empty recycle bin'),
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
                                  note['title']?.toString() ?? 'Untitled note',
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
                                  child: const Text('Restore'),
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
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Settings',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Manage your account, preferences, and local data. Online '
          'account settings require an active login; local '
          'preferences work offline.',
        ),
        ValueListenableBuilder<ActionFeedback?>(
          valueListenable: _feedback,
          builder: (context, feedback, _) {
            if (feedback == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FeedbackText(feedback: feedback),
            );
          },
        ),
        const SizedBox(height: 20),
        _buildOnlineAccountSection(context),
        const SizedBox(height: 16),
        _buildSettingsMenu(context),
        const SizedBox(height: 16),
        _buildDebugSection(context),
      ],
    );
  }

  /// Apple-style two-level settings menu. The five rows below each
  /// open a dedicated sub-page (`_EditorSettingsPage`,
  /// `_BackendSettingsPage`, `_LocalDataPage`, `_RecycleBinPage`)
  /// except for the last red row, which triggers
  /// `_confirmClearAllLocalData` directly because the action is
  /// destructive and shouldn't sit one extra tap away.
  Widget _buildSettingsMenu(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final recoverableCount =
        widget.localTrashedDraftCount + widget.localTrashedCourseCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editor settings'),
            subtitle: const Text(
              'Default editor mode, theme preset, theme mode.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _EditorSettingsPage(parent: this),
                ),
              );
            },
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Backend settings'),
            subtitle: Text(
              widget.localSettings['offline_mode'] == true
                  ? 'Offline mode is on. API URL: '
                      '${widget.apiBaseUrl ?? "—"}'
                  : 'Online. API URL: ${widget.apiBaseUrl ?? "—"}',
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
            title: const Text('Local data'),
            subtitle: const Text(
              'Download or restore the local archive, reset the '
              'starter categories.',
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
            title: const Text('Recycle bin'),
            subtitle: Text(
              '$recoverableCount synced draft(s) recoverable, '
              '${widget.deletedNotes.length} cloud note(s) trashed.',
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
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(
              Icons.science_outlined,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            title: const Text('Developer'),
            subtitle: const Text(
              'Admin-only actions: restore the remote three-course '
              'template catalog.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _DeveloperSettingsPage(parent: this),
                ),
              );
            },
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: Icon(Icons.warning_amber_outlined, color: scheme.error),
            title: Text(
              'Clear all local data',
              style: TextStyle(color: scheme.error),
            ),
            subtitle: Text(
              'Wipes drafts, categories, settings, and logs from this '
              'device. Cloud copies are not touched.',
              style: TextStyle(color: scheme.error.withValues(alpha: 0.8)),
            ),
            onTap: _confirmClearAllLocalData,
          ),
        ],
      ),
    );
  }

}
