part of notechondria_frontend;

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
    this.onGoogleLogin,
    this.onGithubLogin,
    this.onGoogleLoginOnly,
    this.onGithubLoginOnly,
    this.onBindGoogle,
    this.onBindGithub,
    this.onListSocialAccounts,
    this.onUnlinkSocialAccount,
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
    String apiBaseUrl,
    double deadlineTimeWeight,
    double deadlineImportanceWeight,
  ) onSave;
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

  /// Opens the local recycle-bin browser. See editor_app/modules/
  /// settings.dart for the contract; the bin holds drafts /
  /// categories that were moved to client-side trash after a
  /// successful cloud sync.
  final Future<void> Function()? onOpenLocalRecycleBin;

  /// Recycle-bin counts so the button badge renders without an
  /// extra SharedPreferences hit.
  final int localTrashedDraftCount;
  final int localTrashedCourseCount;

  final int localDraftCount;
  final int localCourseCount;
  final List<String> uiLogs;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;
  final ValueListenable<List<ApiDebugSnapshot>>? debugHistoryListenable;
  final DebugLogController? debugLogController;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _mottoController;
  late final TextEditingController _socialController;
  late final TextEditingController _apiBaseController;
  late final TextEditingController _deadlineTimeWeightController;
  late final TextEditingController _deadlineImportanceWeightController;
  String _editorMode = 'P';
  String _themePreset = 'teal';
  String _themeMode = 'S';
  ActionFeedback? _saveFeedback;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _socialLinkError;

  bool get _isAuthenticated => widget.profile != null && widget.settings != null;

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
    _deadlineTimeWeightController = TextEditingController(
      text: (widget.localSettings['deadline_time_weight'] ?? 1.0).toString(),
    );
    _deadlineImportanceWeightController = TextEditingController(
      text: (widget.localSettings['deadline_importance_weight'] ?? 1.0).toString(),
    );
    _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
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
      _emailController.text = widget.settings?['email']?.toString() ??
          widget.profile?['email']?.toString() ??
          '';
      _mottoController.text = widget.settings?['motto']?.toString() ?? '';
      _socialController.text = widget.settings?['social_link']?.toString() ?? '';
      _editorMode = widget.settings?['editor_mode']?.toString() ?? _editorMode;
    }
    if (oldWidget.localSettings != widget.localSettings) {
      _apiBaseController.text = widget.localSettings['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          _defaultApiBaseUrl();
      _deadlineTimeWeightController.text =
          (widget.localSettings['deadline_time_weight'] ?? 1.0).toString();
      _deadlineImportanceWeightController.text =
          (widget.localSettings['deadline_importance_weight'] ?? 1.0).toString();
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
    _deadlineTimeWeightController.dispose();
    _deadlineImportanceWeightController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  Future<void> _submitSettings() async {
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
    final deadlineTimeWeight =
        double.tryParse(_deadlineTimeWeightController.text.trim()) ?? 1.0;
    final deadlineImportanceWeight =
        double.tryParse(_deadlineImportanceWeightController.text.trim()) ?? 1.0;
    final feedback = await widget.onSave(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _mottoController.text.trim(),
      _socialController.text.trim(),
      _editorMode,
      _themePreset,
      _themeMode,
      _apiBaseController.text.trim(),
      deadlineTimeWeight,
      deadlineImportanceWeight,
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
          'Planner settings',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'This app keeps planner-focused controls only: login/sync, deadline-ordering preferences, and debug output.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Login and sync',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (!_isAuthenticated) ...[
                  const Text(
                    'Sign in to sync course plans, module discussion roots, and planner deadlines. Local planner data remains usable while signed out.',
                  ),
                  const SizedBox(height: 12),
                  AuthHub(
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
                  Text(
                    'Signed in as ${widget.profile?['email']?.toString() ?? widget.profile?['username']?.toString() ?? 'user'}.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _runMaintenanceAction(
                          () => widget.onSyncLocalData(announce: false),
                        ),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Push local → cloud'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _runMaintenanceAction(widget.onPullCloudData),
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('Pull cloud → local'),
                      ),
                      if (widget.onOpenLocalRecycleBin != null)
                        OutlinedButton.icon(
                          onPressed: widget.onOpenLocalRecycleBin,
                          icon: const Icon(
                              Icons.restore_from_trash_outlined),
                          label: Text(
                            'Synced drafts (recoverable) '
                            '(${widget.localTrashedDraftCount + widget.localTrashedCourseCount})',
                          ),
                        ),
                      OutlinedButton(
                        onPressed: widget.onLogout,
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ConnectedAccountsSection(
                    onListSocialAccounts: widget.onListSocialAccounts,
                    onUnlinkSocialAccount: widget.onUnlinkSocialAccount,
                    onBindGoogle: widget.onBindGoogle,
                    onBindGithub: widget.onBindGithub,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planner preferences',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                AppPreferencesCard(
                  editorMode: _editorMode,
                  themePreset: _themePreset,
                  themeMode: _themeMode,
                  apiBaseController: _apiBaseController,
                  isAuthenticated: _isAuthenticated,
                  onEditorModeChanged: (v) => setState(() => _editorMode = v),
                  onThemePresetChanged: (v) => setState(() => _themePreset = v),
                  onThemeModeChanged: (v) => setState(() => _themeMode = v),
                  offlineMode: widget.onOfflineModeChanged == null
                      ? null
                      : widget.localSettings['offline_mode'] == true,
                  onOfflineModeChanged: widget.onOfflineModeChanged == null
                      ? null
                      : (value) {
                          widget.onOfflineModeChanged!(value);
                        },
                  extrasBuilder: (context) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _deadlineTimeWeightController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Deadline time weight (a)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _deadlineImportanceWeightController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Deadline importance weight (b)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Deadlines sort by (a × time pressure) × (b × importance). Importance uses the existing event weight.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_saveFeedback != null) ...[
                  FeedbackText(feedback: _saveFeedback!),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _saving ? null : _submitSettings,
                  child: Text(_saving ? 'Saving...' : 'Save planner settings'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (widget.debugLogController != null)
          DebugLogCard(
            controller: widget.debugLogController!,
            title: 'Debug log',
            summary:
                '${widget.localDraftCount} local note(s), ${widget.localCourseCount} local course(s).',
            onCopyLogs: widget.onCopyLogs,
            onPing: () => pingBackend(widget.apiBaseUrl),
          )
        else
          Card(
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
                          '${widget.localDraftCount} local note(s), ${widget.localCourseCount} local course(s).',
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
          ),
      ],
    );
  }

}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}


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
    final hasAny = widget.onBindGoogle != null || widget.onBindGithub != null;
    if (!hasAny && widget.onListSocialAccounts == null) {
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
    BuildContext context, String provider, String label, IconData icon, VoidCallback? onBind,
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
