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
    required this.onRegister,
    required this.onValidateInvitation,
    required this.onVerify,
    required this.onResendVerification,
    required this.onLogin,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
    required this.onRestoreDeletedNote,
    required this.onEmptyDeletedNotes,
    required this.onCopyLogs,
    required this.onUploadAvatar,
    required this.onSyncLocalData,
    required this.onPullCloudData,
    required this.onClearLocalData,
    required this.onRestoreTemplateCourses,
    required this.localDraftCount,
    required this.localCourseCount,
    required this.uiLogs,
    this.onGoogleLogin,
    this.onGithubLogin,
    this.onGoogleLoginOnly,
    this.onGithubLoginOnly,
    this.onBindGoogle,
    this.onBindGithub,
    this.onListSocialAccounts,
    this.onUnlinkSocialAccount,
    this.onSendIdentityCode,
    this.onRotateApiKey,
    this.onChangePassword,
    this.onChangeEmailRequest,
    this.onChangeEmailConfirm,
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
  }) onSave;
  final Future<void> Function() onLogout;
  final Future<ActionFeedback> Function(
    String username,
    String email,
    String password, {
    String invitationCode,
  }) onRegister;
  final Future<Map<String, dynamic>> Function(String code) onValidateInvitation;
  final Future<ActionFeedback> Function(String email, String code) onVerify;
  final Future<ActionFeedback> Function(String email) onResendVerification;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(
    String email,
    String code,
    String password,
  ) onConfirmPasswordReset;
  final void Function(String invitationCode)? onGoogleLogin;
  final void Function(String invitationCode)? onGithubLogin;
  final VoidCallback? onGoogleLoginOnly;
  final VoidCallback? onGithubLoginOnly;
  final VoidCallback? onBindGoogle;
  final VoidCallback? onBindGithub;
  final Future<List<Map<String, dynamic>>> Function()? onListSocialAccounts;
  final Future<void> Function(String provider)? onUnlinkSocialAccount;
  final Future<void> Function(Map<String, dynamic> note) onRestoreDeletedNote;
  final Future<void> Function() onEmptyDeletedNotes;
  final Future<void> Function() onCopyLogs;
  final Future<ActionFeedback> Function() onUploadAvatar;
  final Future<ActionFeedback> Function({bool showMessage}) onSyncLocalData;
  final Future<ActionFeedback> Function() onPullCloudData;
  final Future<ActionFeedback> Function() onClearLocalData;
  final Future<ActionFeedback> Function() onRestoreTemplateCourses;
  final Future<Map<String, dynamic>> Function()? onSendIdentityCode;
  final Future<Map<String, dynamic>> Function()? onRotateApiKey;
  final Future<Map<String, dynamic>> Function(String currentPassword, String newPassword, String identityCode)? onChangePassword;
  final Future<Map<String, dynamic>> Function(String newEmail, String identityCode)? onChangeEmailRequest;
  final Future<Map<String, dynamic>> Function(String newEmail, String code)? onChangeEmailConfirm;
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
  String _editorMode = 'P';
  String _themePreset = 'teal';
  String _themeMode = 'S';
  ActionFeedback? _saveFeedback;
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
    super.dispose();
  }

  /// Shared `setState` wrapper for extensions — `setState` is
  /// `@protected` and invisible to extensions, so build helpers
  /// mutate state fields directly and then call this to trigger a
  /// rebuild. Same pattern used on `_AppShellState`.
  void _refresh() {
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
    return _firstNameController.text.trim() != serverFirstName ||
        _lastNameController.text.trim() != serverLastName ||
        _mottoController.text.trim() != serverMotto ||
        _socialController.text.trim() != serverSocial;
  }

  /// Whether any editor-preference field has been edited.
  bool get _hasPreferenceChanges {
    final serverEditorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
    final localThemePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
    final localThemeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
    final localApiBase = widget.localSettings['api_base_url']?.toString() ??
        widget.apiBaseUrl ?? _defaultApiBaseUrl();
    return _editorMode != serverEditorMode ||
        _themePreset != localThemePreset ||
        _themeMode != localThemeMode ||
        _apiBaseController.text.trim() != localApiBase;
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
    });
  }

  /// Restores editor preference fields to server/local values.
  void _cancelPreferenceChanges() {
    setState(() {
      _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
      if (_editorMode == 'B') _editorMode = 'G';
      _themePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
      _themeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
      _apiBaseController.text = widget.localSettings['api_base_url']?.toString() ??
          widget.apiBaseUrl ?? _defaultApiBaseUrl();
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
      setState(() {
        _saveFeedback = const ActionFeedback(message: 'No changes to save.');
      });
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

  Future<void> _submitSettings() async {
    if (_saving) return;
    final social = _socialController.text.trim();
    if (social.isNotEmpty && !_isValidUrl(social)) {
      setState(() => _socialLinkError = 'Must be a valid URL (https://...)');
      return;
    }
    setState(() {
      _saving = true;
      _saveFeedback = null;
      _socialLinkError = null;
    });
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
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _saveFeedback = feedback;
    });
  }

  Future<void> _handleAvatarUpload() async {
    setState(() {
      _uploadingAvatar = true;
      _saveFeedback = null;
    });
    final feedback = await widget.onUploadAvatar();
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadingAvatar = false;
      _saveFeedback = feedback;
    });
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
    setState(() {
      _saveFeedback = null;
    });
    final feedback = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _saveFeedback = feedback;
    });
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
          'Editor settings',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Edit your settings below and press Save to apply. Online account settings require an active login; local preferences work offline.',
        ),
        if (_saveFeedback != null) ...[
          const SizedBox(height: 12),
          FeedbackText(feedback: _saveFeedback!),
        ],
        const SizedBox(height: 20),
        _buildOnlineAccountSection(context),
        const SizedBox(height: 16),
        _buildOfflinePreferencesSection(context),
        const SizedBox(height: 16),
        _buildDebugSection(context),
      ],
    );
  }

}
