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
    this.apiBaseUrl,
    this.debugSnapshotListenable,
    this.debugHistoryListenable,
    this.debugLogController,
    this.onExportLocalData,
    this.onRestoreFromLocalImport,
    this.onSaveMcpSkill,
    this.githubSyncCardBuilder,
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
    double deadlineTimeWeight,
    double deadlineImportanceWeight,
  ) onSave;
  final Future<void> Function() onLogout;
  final Future<ActionFeedback> Function(String email, String password) onLogin;

  /// Replays the first-run onboarding tour from the App preferences
  /// card. Null hides the row.
  final VoidCallback? onReplayTour;

  /// Persisted Language value ('system' | 'en' | 'zh') and the
  /// apply-immediately callback. When both are non-null the App
  /// preferences card renders a Language dropdown; picking a value
  /// fires `onSetLocale`, which persists `locale` and rebuilds the
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
  /// returned by `/api/v1/auth/casdoor/config/`. Threaded through to
  /// `AuthHub` so its "Login via third party" + "Sign up via Casdoor"
  /// CTAs can redirect the browser there. Null when the backend has
  /// no Casdoor config.
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
  final Future<void> Function()? onExportLocalData;
  final Future<void> Function()? onRestoreFromLocalImport;

  /// Persists the user's MCP `skill.md` body to the backend Creator
  /// row. Returns an `ActionFeedback` so the section widget can show a
  /// snackbar. Null when the user is signed out.
  final Future<ActionFeedback> Function(String skillMd)? onSaveMcpSkill;

  /// Builder for the experimental GitHub-Sync card. Constructed in
  /// `app_shell` so the network callbacks bind to the authenticated
  /// client + token. Null when the user is signed out.
  final Widget Function()? githubSyncCardBuilder;

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
    _deadlineTimeWeightController = TextEditingController(
      text: (widget.localSettings['deadline_time_weight'] ?? 1.0).toString(),
    );
    _deadlineImportanceWeightController = TextEditingController(
      text: (widget.localSettings['deadline_importance_weight'] ?? 1.0)
          .toString(),
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
      _deadlineTimeWeightController.text =
          (widget.localSettings['deadline_time_weight'] ?? 1.0).toString();
      _deadlineImportanceWeightController.text =
          (widget.localSettings['deadline_importance_weight'] ?? 1.0)
              .toString();
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
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https');
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
        // Storage usage — local-data breakdown + browser quota. The
        // shared card is fed the planner's bucket sizes, attachment
        // bytes, and the backend storage-arch probe.
        _StorageUsageSection(
          backendHost: _hostOf(
            widget.apiBaseUrl ?? widget.localSettings['api_base_url'],
          ),
          onProbeStorageArch: widget.onProbeStorageArch,
        ),
        const SizedBox(height: 16),
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
                    onLogin: widget.onLogin,
                    onCasdoorLogin: widget.onCasdoorLogin,
                    casdoorOrgLoginUrl: widget.casdoorOrgLoginUrl,
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
                        onPressed: () =>
                            _runMaintenanceAction(widget.onPullCloudData),
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('Pull cloud → local'),
                      ),
                      if (widget.onOpenLocalRecycleBin != null)
                        OutlinedButton.icon(
                          onPressed: widget.onOpenLocalRecycleBin,
                          icon: const Icon(Icons.restore_from_trash_outlined),
                          label: Text(
                            'Synced drafts (recoverable) '
                            '(${widget.localTrashedDraftCount + widget.localTrashedCourseCount})',
                          ),
                        ),
                      if (widget.onExportLocalData != null)
                        OutlinedButton.icon(
                          onPressed: () => widget.onExportLocalData!(),
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('Download local data'),
                        ),
                      if (widget.onRestoreFromLocalImport != null)
                        OutlinedButton.icon(
                          onPressed: () => widget.onRestoreFromLocalImport!(),
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('Restore from local archive'),
                        ),
                      OutlinedButton(
                        onPressed: widget.onLogout,
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ConnectedAccountsSection(
                    onBindCasdoor: widget.onBindCasdoor,
                    onUnlinkCasdoor: widget.onUnlinkCasdoor,
                    casdoorLinked: widget.settings?['casdoor_linked'] == true,
                    casdoorOrgLoginUrl: widget.casdoorOrgLoginUrl,
                  ),
                  // 0.1.119: Agent Skill (McpSkillSection) moved out
                  // of the account card and into a sibling
                  // "Integrations" card below — matches editor's
                  // API-settings placement so the MCP skill markdown
                  // doesn't read as an account / sign-in concern.
                  // TODO: when planner grows subpages, move
                  // Integrations into a dedicated `_ApiSettingsPage`
                  // like editor + portal.
                ],
              ],
            ),
          ),
        ),
        if (widget.onSaveMcpSkill != null) ...[
          const SizedBox(height: 16),
          widget.githubSyncCardBuilder?.call() ??
              const GithubSyncExperimentalCard(appId: 'planner'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: McpSkillSection(
                initialContent:
                    widget.settings?['mcp_skill_md']?.toString() ?? '',
                onSave: widget.onSaveMcpSkill!,
              ),
            ),
          ),
        ],
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
                  currentLocale: widget.onSetLocale == null
                      ? null
                      : (widget.localSettings['locale']?.toString() ??
                          'system'),
                  onLocaleChanged: widget.onSetLocale == null
                      ? null
                      : (v) => widget.onSetLocale!(v),
                  onReplayTour: widget.onReplayTour,
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
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
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
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
                        ? const Center(
                            child: Text('No frontend logs captured yet.'))
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

/// Compact host extracted from an API base URL, for the storage card.
String _hostOf(Object? rawApiUrl) {
  final raw = rawApiUrl?.toString().trim() ?? '';
  if (raw.isEmpty) return '';
  final uri = Uri.tryParse(raw);
  return (uri == null || uri.host.isEmpty) ? raw : uri.host;
}

/// Gathers the async storage inputs (per-bucket sizes, attachment
/// bytes, backend storage arch) and renders the shared
/// [StorageUsageCard]. Mirrors the editor's `_StorageUsageSection`.
class _StorageUsageSection extends StatefulWidget {
  const _StorageUsageSection({
    required this.backendHost,
    this.onProbeStorageArch,
  });

  final String backendHost;
  final Future<String?> Function()? onProbeStorageArch;

  @override
  State<_StorageUsageSection> createState() => _StorageUsageSectionState();
}

class _StorageUsageSectionState extends State<_StorageUsageSection> {
  Map<String, int>? _buckets;
  int _attachmentBytes = 0;
  String _storageArch = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _gather();
  }

  Future<void> _gather() async {
    final buckets = await _LocalAppStore.bucketSizes();
    var attachmentBytes = 0;
    try {
      final store = await LocalAttachmentStore.open();
      attachmentBytes = await store.totalBytes();
    } catch (_) {
      attachmentBytes = 0;
    }
    final arch = (await widget.onProbeStorageArch?.call()) ?? '';
    if (!mounted) return;
    setState(() {
      _buckets = buckets;
      _attachmentBytes = attachmentBytes;
      _storageArch = arch;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    return StorageUsageCard(
      backendHost: widget.backendHost,
      storageArchLabel: _storageArch,
      bucketSizes: _buckets ?? const {},
      attachmentBytes: _attachmentBytes,
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

// _ConnectedAccountsSection (planner copy) — Casdoor is now the only
// connected-account row; per-provider Google / GitHub bindings were
// retired in favor of letting Casdoor itself proxy those identities
// via its application Providers tab.
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

  /// Org-themed Casdoor login page URL built from env vars
  /// (`CASDOOR_ENDPOINT` + `CASDOOR_ORG_NAME`) on the backend.
  /// Empty / null in shadow mode.
  final String? casdoorOrgLoginUrl;

  @override
  State<_ConnectedAccountsSection> createState() =>
      _ConnectedAccountsSectionState();
}

class _ConnectedAccountsSectionState extends State<_ConnectedAccountsSection> {
  @override
  Widget build(BuildContext context) {
    final shadowMode = widget.onBindCasdoor == null;
    final manageUrl = widget.casdoorOrgLoginUrl ?? '';
    if (shadowMode && manageUrl.isEmpty) {
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
        if (!shadowMode) _buildCasdoorRow(context),
        if (manageUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => url_strategy.browserRedirect(manageUrl),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Manage Casdoor account'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'If sign-in is unavailable, contact your Notechondria '
          'admin (Casdoor backend may be off).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCasdoorRow(BuildContext context) {
    final linked = widget.casdoorLinked;
    return ListTile(
      leading: const Icon(Icons.shield_outlined),
      title: const Text('Casdoor SSO'),
      subtitle: Text(linked ? 'Linked' : 'Not linked'),
      dense: true,
      trailing: linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onBindCasdoor != null)
                  TextButton(
                    onPressed: widget.onBindCasdoor,
                    child: const Text('Switch'),
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
                    'Unlink',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            )
          : TextButton(
              onPressed: widget.onBindCasdoor,
              child: const Text('Link Casdoor'),
            ),
    );
  }
}
