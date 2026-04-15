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
    this.onDownloadConfig,
    this.apiBaseUrl,
    this.debugSnapshotListenable,
    this.debugHistoryListenable,
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
  final Future<void> Function()? onDownloadConfig;
  final int localDraftCount;
  final int localCourseCount;
  final List<String> uiLogs;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;
  final ValueListenable<List<ApiDebugSnapshot>>? debugHistoryListenable;

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
      builder: (ctx) => const _ConfirmWithDelayDialog(
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
          _FeedbackText(feedback: _saveFeedback!),
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

  /// Online account section: login/register when signed out; profile fields,
  /// sync buttons, and logout when signed in. Hosts every control that only
  /// makes sense with an active cloud session.
  Widget _buildOnlineAccountSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Online account',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_saving)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_isAuthenticated) ...[
              const Text(
                'Sign in to sync notes with the cloud. Local notes stay editable even while signed out.',
              ),
              const SizedBox(height: 12),
              _AuthHub(
                onRegister: widget.onRegister,
                onValidateInvitation: widget.onValidateInvitation,
                onVerify: widget.onVerify,
                onResendVerification: widget.onResendVerification,
                onLogin: widget.onLogin,
                onRequestPasswordReset: widget.onRequestPasswordReset,
                onConfirmPasswordReset: widget.onConfirmPasswordReset,
                onGoogleLogin: widget.onGoogleLogin,
                onGithubLogin: widget.onGithubLogin,
                onGoogleLoginOnly: widget.onGoogleLoginOnly,
                onGithubLoginOnly: widget.onGithubLoginOnly,
                apiBaseUrl: widget.apiBaseUrl,
              ),
            ] else ...[
              _buildProfileFields(context),
              const SizedBox(height: 16),
              _buildSectionButtons(
                hasChanges: _hasProfileChanges,
                onCancel: _cancelProfileChanges,
              ),
              const SizedBox(height: 20),
              // ---- API key + MCP endpoint subsection ----
              // Placed directly above Connected accounts per the 0.1.17
              // settings-layout task: the key must be visible to the user
              // and paired with the MCP endpoint helper text.
              _ApiKeySection(
                apiKeyPrefix:
                    widget.settings?['api_key_prefix']?.toString() ?? '',
                apiBaseUrl: widget.apiBaseUrl ?? '',
                onRotate: widget.onRotateApiKey,
              ),
              const SizedBox(height: 20),
              // ---- Connected accounts subsection ----
              _ConnectedAccountsSection(
                onListSocialAccounts: widget.onListSocialAccounts,
                onUnlinkSocialAccount: widget.onUnlinkSocialAccount,
                onBindGoogle: widget.onBindGoogle,
                onBindGithub: widget.onBindGithub,
              ),
              const SizedBox(height: 20),
              // ---- Sync subsection ----
              Text(
                'Sync',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Push local \u2192 cloud'),
                subtitle: const Text(
                    'Upload local drafts and categories to your cloud account.'),
                dense: true,
                onTap: () => _runMaintenanceAction(
                  () => widget.onSyncLocalData(showMessage: false),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Pull cloud \u2192 local'),
                subtitle: const Text(
                    'Download notes and categories from the cloud to this device.'),
                dense: true,
                onTap: () => _runMaintenanceAction(widget.onPullCloudData),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.start,
                children: [
                  if (widget.onChangeEmailRequest != null)
                    OutlinedButton(
                      onPressed: () => _openChangeEmailDialog(context),
                      child: const Text('Change email'),
                    ),
                  if (widget.onChangePassword != null)
                    OutlinedButton(
                      onPressed: () => _openChangePasswordDialog(context),
                      child: const Text('Change password'),
                    ),
                  OutlinedButton(
                    onPressed: widget.onLogout,
                    child: const Text('Logout'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Profile fields shown when authenticated: avatar, name, motto, social link.
  void _openChangePasswordDialog(BuildContext context) {
    final identityCodeCtrl = TextEditingController();
    final currentPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();
    String? error;
    String? maskedEmail;
    bool submitting = false;
    bool identityVerified = false;
    _showBlurDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(identityVerified ? 'Change password' : 'Verify your identity'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!identityVerified) ...[
                  if (maskedEmail == null)
                    const Text('A verification code will be sent to your current email.'),
                  if (maskedEmail != null) ...[
                    Text('A code was sent to $maskedEmail. Enter it below.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: identityCodeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '6-digit identity code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
                if (identityVerified) ...[
                  TextField(
                    controller: currentPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      helperText: 'Min 8 chars, uppercase + lowercase + digit/special.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            if (!identityVerified && maskedEmail == null)
              FilledButton(
                onPressed: submitting ? null : () async {
                  setDialogState(() { submitting = true; error = null; });
                  try {
                    final result = await widget.onSendIdentityCode!();
                    setDialogState(() {
                      submitting = false;
                      maskedEmail = result['masked_email']?.toString() ?? '***';
                    });
                  } catch (e) {
                    setDialogState(() {
                      submitting = false;
                      error = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                },
                child: Text(submitting ? 'Sending...' : 'Send code'),
              ),
            if (!identityVerified && maskedEmail != null)
              FilledButton(
                onPressed: submitting ? null : () {
                  if (identityCodeCtrl.text.trim().isEmpty) {
                    setDialogState(() => error = 'Enter the verification code.');
                    return;
                  }
                  setDialogState(() { identityVerified = true; error = null; });
                },
                child: const Text('Verify'),
              ),
            if (identityVerified)
              FilledButton(
                onPressed: submitting ? null : () async {
                  if (newPwCtrl.text != confirmPwCtrl.text) {
                    setDialogState(() => error = 'Passwords do not match.');
                    return;
                  }
                  if (newPwCtrl.text.length < 8) {
                    setDialogState(() => error = 'Password must be at least 8 characters.');
                    return;
                  }
                  setDialogState(() { submitting = true; error = null; });
                  try {
                    await widget.onChangePassword!(
                      currentPwCtrl.text, newPwCtrl.text, identityCodeCtrl.text.trim(),
                    );
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Password changed.')),
                      );
                    }
                  } catch (e) {
                    setDialogState(() {
                      submitting = false;
                      error = e.toString().replaceFirst('Exception: ', '');
                    });
                  }
                },
                child: Text(submitting ? 'Saving...' : 'Change password'),
              ),
          ],
        ),
      ),
    ).then((_) {
      identityCodeCtrl.dispose();
      currentPwCtrl.dispose();
      newPwCtrl.dispose();
      confirmPwCtrl.dispose();
    });
  }

  void _openChangeEmailDialog(BuildContext context) {
    final identityCodeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String? error;
    String? successMessage;
    String? maskedEmail;
    bool submitting = false;
    bool identityVerified = false;
    bool codeSent = false;
    _showBlurDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) {
          final String title;
          if (!identityVerified) {
            title = 'Verify your identity';
          } else if (!codeSent) {
            title = 'Change email';
          } else {
            title = 'Confirm new email';
          }
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step 0: identity verification
                  if (!identityVerified) ...[
                    if (maskedEmail == null)
                      const Text('A verification code will be sent to your current email.'),
                    if (maskedEmail != null) ...[
                      Text('A code was sent to $maskedEmail. Enter it below.'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: identityCodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '6-digit identity code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                  // Step 1: enter new email
                  if (identityVerified && !codeSent) ...[
                    const Text('Enter your new email address.'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'New email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  // Step 2: confirm code sent to new email
                  if (identityVerified && codeSent) ...[
                    Text('A code was sent to ${emailCtrl.text}. Enter it below.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '6-digit code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                  ],
                  if (successMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(successMessage!, style: const TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              // Step 0a: send identity code
              if (!identityVerified && maskedEmail == null)
                FilledButton(
                  onPressed: submitting ? null : () async {
                    setDialogState(() { submitting = true; error = null; });
                    try {
                      final result = await widget.onSendIdentityCode!();
                      setDialogState(() {
                        submitting = false;
                        maskedEmail = result['masked_email']?.toString() ?? '***';
                      });
                    } catch (e) {
                      setDialogState(() {
                        submitting = false;
                        error = e.toString().replaceFirst('Exception: ', '');
                      });
                    }
                  },
                  child: Text(submitting ? 'Sending...' : 'Send code'),
                ),
              // Step 0b: verify identity code (client-side gate)
              if (!identityVerified && maskedEmail != null)
                FilledButton(
                  onPressed: submitting ? null : () {
                    if (identityCodeCtrl.text.trim().isEmpty) {
                      setDialogState(() => error = 'Enter the verification code.');
                      return;
                    }
                    setDialogState(() { identityVerified = true; error = null; });
                  },
                  child: const Text('Verify'),
                ),
              // Step 1: send code to new email
              if (identityVerified && !codeSent)
                FilledButton(
                  onPressed: submitting ? null : () async {
                    if (emailCtrl.text.trim().isEmpty) {
                      setDialogState(() => error = 'Enter a new email address.');
                      return;
                    }
                    setDialogState(() { submitting = true; error = null; });
                    try {
                      final result = await widget.onChangeEmailRequest!(
                        emailCtrl.text.trim(), identityCodeCtrl.text.trim(),
                      );
                      setDialogState(() {
                        submitting = false;
                        codeSent = true;
                        successMessage = result['message']?.toString();
                      });
                    } catch (e) {
                      setDialogState(() {
                        submitting = false;
                        error = e.toString().replaceFirst('Exception: ', '');
                      });
                    }
                  },
                  child: Text(submitting ? 'Sending...' : 'Send code'),
                ),
              // Step 2: confirm new email code
              if (identityVerified && codeSent)
                FilledButton(
                  onPressed: submitting ? null : () async {
                    if (codeCtrl.text.trim().isEmpty) {
                      setDialogState(() => error = 'Enter the verification code.');
                      return;
                    }
                    setDialogState(() { submitting = true; error = null; successMessage = null; });
                    try {
                      await widget.onChangeEmailConfirm!(emailCtrl.text.trim(), codeCtrl.text.trim());
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Email updated.')),
                        );
                      }
                    } catch (e) {
                      setDialogState(() {
                        submitting = false;
                        error = e.toString().replaceFirst('Exception: ', '');
                      });
                    }
                  },
                  child: Text(submitting ? 'Verifying...' : 'Confirm'),
                ),
            ],
          );
        },
      ),
    ).then((_) {
      identityCodeCtrl.dispose();
      emailCtrl.dispose();
      codeCtrl.dispose();
    });
  }

  Widget _buildProfileFields(BuildContext context) {
    final avatarUrl = widget.profile?['image_url']?.toString() ??
        widget.settings?['image_url']?.toString();
    final resolvedAvatar = avatarUrl != null && avatarUrl.isNotEmpty
        ? _resolveRemoteUrl(avatarUrl, apiBaseUrl: widget.apiBaseUrl)
        : '';
    final username = widget.profile?['username']?.toString() ?? 'User';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => _previewAvatar(resolvedAvatar, username),
              child: _RemoteAvatar(
                radius: 32,
                imageUrl: resolvedAvatar,
                fallbackLabel: username,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.profile?['display_name']?.toString() ?? username,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '@$username',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  Text(
                    widget.profile?['email']?.toString() ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: _uploadingAvatar ? null : _handleAvatarUpload,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: Text(_uploadingAvatar ? 'Uploading...' : 'Change avatar'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Last name',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mottoController,
          decoration: const InputDecoration(
            labelText: 'Motto',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _socialController,
          decoration: InputDecoration(
            labelText: 'Social link',
            hintText: 'https://...',
            border: const OutlineInputBorder(),
            errorText: _socialLinkError,
          ),
          onChanged: (_) {
            if (_socialLinkError != null) {
              setState(() => _socialLinkError = null);
            }
          },
        ),
      ],
    );
  }

  void _previewAvatar(String imageUrl, String username) {
    if (imageUrl.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                username,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, maxHeight: 400),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Icon(Icons.broken_image_outlined, size: 64),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// App preferences: editor mode, theme, API base URL. Every control
  /// works without an account and auto-saves on change — no explicit button.
  /// Renamed from "Editor preferences" in 0.1.20 so the same label can be
  /// reused unchanged across editor/planner/portal once the shared Settings
  /// widget lands.
  Widget _buildOfflinePreferencesSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'App preferences',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _editorMode,
              items: const [
                DropdownMenuItem(value: 'P', child: Text('Plain text editor')),
                DropdownMenuItem(value: 'G', child: Text('Live markdown editor')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _editorMode = value);
                }
              },
              decoration: const InputDecoration(
                labelText: 'Default editor',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _themePreset,
                    items: _themePresetEntries.entries
                        .map((entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _themePreset = value);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Theme preset',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _themeMode,
                    items: const [
                      DropdownMenuItem(value: 'S', child: Text('System')),
                      DropdownMenuItem(value: 'L', child: Text('Light')),
                      DropdownMenuItem(value: 'D', child: Text('Dark')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _themeMode = value);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Theme mode',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // API base URL is locked while the user is signed in: changing
            // backend mid-session would invalidate the token and lose
            // cached remote data. Tooltip explains the path forward
            // (logout first, then change).
            Tooltip(
              message: _isAuthenticated
                  ? 'Log out before changing the API base URL. A logged-in '
                      'token is only valid against its issuing backend.'
                  : '',
              child: TextField(
                controller: _apiBaseController,
                enabled: !_isAuthenticated,
                decoration: InputDecoration(
                  labelText: 'API base URL',
                  border: const OutlineInputBorder(),
                  helperText: _isAuthenticated
                      ? 'Locked while signed in. Log out to change.'
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildSectionButtons(
              hasChanges: _hasPreferenceChanges,
              onCancel: _cancelPreferenceChanges,
            ),
            const SizedBox(height: 16),
            // Offline account actions row — previously lived in a separate
            // "Configuration" card, now inlined here because everything below
            // works without a cloud session.
            Text(
              'Offline account',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (widget.onDownloadConfig != null)
                  OutlinedButton.icon(
                    onPressed: widget.onDownloadConfig,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download config file'),
                  ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _runMaintenanceAction(widget.onRestoreTemplateCourses),
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('Restore template categories'),
                ),
                OutlinedButton.icon(
                  onPressed: _openRecycleBinDialog,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: Text(
                    'Recycle bin (${widget.deletedNotes.length})',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _confirmClearAllLocalData,
                  icon: Icon(Icons.warning_amber_outlined,
                      color: Theme.of(context).colorScheme.error),
                  label: Text(
                    'Clear all local data',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Simplified debug log: local stats and recent UI logs with copy button.
  Widget _buildDebugSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Debug log',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${widget.localDraftCount} local draft(s), ${widget.localCourseCount} local category(ies).',
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.onCopyLogs,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Copy logs'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: widget.uiLogs.isEmpty
                  ? const Center(child: Text('No frontend logs captured yet.'))
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
}

/// Displays the current MCP API key (prefix only) and the MCP endpoint URL,
/// and lets the user rotate the key. After rotation, the plaintext key is
/// shown ONCE with a copy button — the backend only stores a SHA-256 hash.
class _ApiKeySection extends StatefulWidget {
  const _ApiKeySection({
    required this.apiKeyPrefix,
    required this.apiBaseUrl,
    required this.onRotate,
  });

  final String apiKeyPrefix;
  final String apiBaseUrl;
  final Future<Map<String, dynamic>> Function()? onRotate;

  @override
  State<_ApiKeySection> createState() => _ApiKeySectionState();
}

class _ApiKeySectionState extends State<_ApiKeySection> {
  String _currentPrefix = '';
  String? _plaintextKey; // shown once after rotation
  bool _rotating = false;

  @override
  void initState() {
    super.initState();
    _currentPrefix = widget.apiKeyPrefix;
  }

  @override
  void didUpdateWidget(covariant _ApiKeySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKeyPrefix != widget.apiKeyPrefix && _plaintextKey == null) {
      setState(() => _currentPrefix = widget.apiKeyPrefix);
    }
  }

  /// Strip any `/api/...` suffix from [apiBaseUrl] so the MCP endpoint
  /// lives at `<origin>/mcp/`. Returns an empty string if the base URL is
  /// empty, so the helper text can hide itself cleanly.
  String _mcpEndpoint() {
    final base = widget.apiBaseUrl.trim();
    if (base.isEmpty) return '';
    try {
      final uri = Uri.parse(base);
      if (uri.scheme.isEmpty || uri.host.isEmpty) return '';
      final origin =
          '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      return '$origin/mcp/';
    } catch (_) {
      return '';
    }
  }

  Future<void> _rotate() async {
    if (widget.onRotate == null || _rotating) return;
    setState(() => _rotating = true);
    try {
      final result = await widget.onRotate!();
      final key = result['api_key']?.toString() ?? '';
      final prefix = result['api_key_prefix']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _plaintextKey = key.isNotEmpty ? key : null;
        if (prefix.isNotEmpty) _currentPrefix = prefix;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to rotate API key: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  void _dismissPlaintext() {
    setState(() => _plaintextKey = null);
  }

  Future<void> _copyPlaintext() async {
    if (_plaintextKey == null) return;
    await Clipboard.setData(ClipboardData(text: _plaintextKey!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key copied to clipboard.')),
    );
  }

  Future<void> _copyMcpEndpoint() async {
    final endpoint = _mcpEndpoint();
    if (endpoint.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: endpoint));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MCP endpoint copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onRotate == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final labelStyle =
        theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      color: theme.colorScheme.onSurface,
      fontSize: 13,
    );
    final displayPrefix = _currentPrefix.isNotEmpty
        ? '$_currentPrefix•••••••••••••••••••••••••'
        : '(no API key — click Rotate to generate one)';
    final mcpEndpoint = _mcpEndpoint();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('API key', style: labelStyle),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(displayPrefix, style: monoStyle),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _rotating ? null : _rotate,
              icon: _rotating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(
                _currentPrefix.isNotEmpty ? 'Rotate' : 'Generate',
              ),
            ),
          ],
        ),
        if (_plaintextKey != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Copy this key now — it will NOT be shown again:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SelectableText(_plaintextKey!, style: monoStyle),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _copyPlaintext,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                    TextButton(
                      onPressed: _dismissPlaintext,
                      child: const Text('I have saved it'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Use this key with MCP clients (e.g. Claude Desktop) by setting the '
          'Authorization header to "Bearer ntc_<key>".',
          style: helperStyle,
        ),
        if (mcpEndpoint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: helperStyle,
                    children: [
                      const TextSpan(text: 'MCP endpoint: '),
                      TextSpan(
                        text: mcpEndpoint,
                        style: monoStyle.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy MCP endpoint',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 16,
                icon: const Icon(Icons.copy),
                onPressed: _copyMcpEndpoint,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shows linked Google/GitHub accounts with bind/unbind controls.
class _ConnectedAccountsSection extends StatefulWidget {
  const _ConnectedAccountsSection({
    this.onListSocialAccounts,
    this.onUnlinkSocialAccount,
    this.onBindGoogle,
    this.onBindGithub,
  });

  final Future<List<Map<String, dynamic>>> Function()? onListSocialAccounts;
  final Future<void> Function(String provider)? onUnlinkSocialAccount;
  final VoidCallback? onBindGoogle;
  final VoidCallback? onBindGithub;

  @override
  State<_ConnectedAccountsSection> createState() =>
      _ConnectedAccountsSectionState();
}

class _ConnectedAccountsSectionState extends State<_ConnectedAccountsSection> {
  List<Map<String, dynamic>>? _accounts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.onListSocialAccounts == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final accounts = await widget.onListSocialAccounts!();
      if (mounted) setState(() { _accounts = accounts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _accountFor(String provider) {
    return _accounts?.cast<Map<String, dynamic>?>().firstWhere(
      (a) => a?['provider'] == provider,
      orElse: () => null,
    );
  }

  Future<void> _unlink(String provider) async {
    if (widget.onUnlinkSocialAccount == null) return;
    try {
      await widget.onUnlinkSocialAccount!(provider);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyProvider = widget.onBindGoogle != null || widget.onBindGithub != null;
    if (!hasAnyProvider && widget.onListSocialAccounts == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connected accounts',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else ...[
          _buildProviderRow(context, 'google', 'Google', Icons.g_mobiledata, widget.onBindGoogle),
          _buildProviderRow(context, 'github', 'GitHub', Icons.code, widget.onBindGithub),
        ],
      ],
    );
  }

  Widget _buildProviderRow(
    BuildContext context,
    String provider,
    String label,
    IconData icon,
    VoidCallback? onBind,
  ) {
    final account = _accountFor(provider);
    final linked = account != null;
    final email = account?['email']?.toString() ?? '';
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: linked
          ? Text(email.isNotEmpty ? email : 'Linked')
          : const Text('Not linked'),
      dense: true,
      trailing: linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onBind != null)
                  TextButton(onPressed: onBind, child: const Text('Switch')),
                TextButton(
                  onPressed: () => _unlink(provider),
                  child: Text('Unlink',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            )
          : onBind != null
              ? TextButton(onPressed: onBind, child: Text('Link $label'))
              : null,
    );
  }
}

