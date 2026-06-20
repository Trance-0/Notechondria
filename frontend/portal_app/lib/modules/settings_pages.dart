part of notechondria_frontend;

/// Apple-style two-level Settings sub-pages for the portal. Each
/// page is a pushed `MaterialPageRoute` opened by a row tap on the
/// top-level `_SettingsPage`. Pages reuse the parent's
/// `_SettingsPageState` to read + mutate shared fields like
/// `_editorMode`, `_themePreset`, `_themeMode`, and
/// `_apiBaseController`. They take the parent state as a constructor
/// argument because `Navigator.push` builds the new route in a fresh
/// widget subtree that doesn't have the parent's `State` ancestor
/// available via `findAncestorStateOfType`. Mirrors the editor's
/// `frontend/editor_app/lib/modules/settings_pages.dart` pattern.

/// Subpage 1 — Personal information. Avatar + username + motto +
/// social link. Hosts an explicit Save / Cancel row tied to the
/// parent's `_submitSettings` so the user can commit profile edits
/// without backing out to the top-level Settings page.
class _PersonalInformationPage extends StatefulWidget {
  const _PersonalInformationPage({required this.parent});

  final _SettingsPageState parent;

  @override
  State<_PersonalInformationPage> createState() =>
      _PersonalInformationPageState();
}

class _PersonalInformationPageState extends State<_PersonalInformationPage> {
  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Personal information')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: p._buildProfileFields(context),
              ),
            ),
            const SizedBox(height: 12),
            p._buildSectionButtons(
              hasChanges: p._hasProfileChanges,
              onCancel: () {
                p._cancelProfileChanges();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Subpage 2 — Sign in & security. Active Sessions, Change email,
/// Change password, MCP Skill (agent skill markdown). Mirrors the
/// editor's `_SignInSecurityPage` but keeps the MCP skill card here
/// (per spec) rather than alongside the API key.
class _SignInSecurityPage extends StatelessWidget {
  const _SignInSecurityPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in & security')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            // Post-Casdoor cutover: account creation, password change,
            // email change, and per-device session management all
            // live on the Casdoor user portal at `auth.trance-0.com`.
            // Casdoor bind / unlink toggles live one row up in the
            // Account page.
            //
            // 0.1.119: Agent Skill (MCP skill markdown) moved to the
            // API settings subpage so it sits next to the MCP API
            // key + base URL controls — matches the editor app's
            // placement. Sign-in & Security is now Casdoor-only.
            const SizedBox(height: 8),
            Text(
              'Account creation, password change, email change, and '
              'per-device session management live on the Casdoor user '
              'portal. Casdoor bind / unlink controls are on the '
              'Account page.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Subpage 3 — API settings. API base URL editor + API key rotate.
/// The base URL field is locked while authenticated (changing the
/// backend mid-session would invalidate the token).
class _ApiSettingsPage extends StatefulWidget {
  const _ApiSettingsPage({required this.parent});

  final _SettingsPageState parent;

  @override
  State<_ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<_ApiSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    return Scaffold(
      appBar: AppBar(title: const Text('API settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            _SettingsGroupCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_outlined),
                      const SizedBox(width: 12),
                      Text(
                        'API base URL',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: p._isAuthenticated
                            ? 'Locked while signed in. Sign out to switch '
                                'the backend the portal talks to.'
                            : 'Points the portal at a different '
                                'Notechondria backend.',
                        child: Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: TextField(
                    controller: p._apiBaseController,
                    enabled: !p._isAuthenticated,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      hintText: 'http://localhost:9060/api/v1',
                    ),
                    onChanged: (_) => p.refreshState(),
                    // Pressing Enter commits the URL change immediately
                    // so the user doesn't have to back out to find a
                    // Save button.
                    onSubmitted: (_) {
                      p._autoSavePreferences();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const _SettingsCaption(
              text: 'Press Enter to apply the URL change. Stored locally '
                  'and mirrored to the profile on login.',
            ),
            if (p.widget.onRotateApiKey != null) ...[
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ApiKeySection(
                    apiKeyPrefix:
                        p.widget.settings?['api_key_prefix']?.toString() ?? '',
                    apiBaseUrl: p.widget.apiBaseUrl ?? '',
                    onRotate: p.widget.onRotateApiKey,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const _SettingsCaption(
                text: 'The MCP key authenticates the backend Model '
                    'Context Protocol bridge. Rotate it if you suspect '
                    'leakage.',
              ),
            ],
            // 0.1.119: Agent Skill moved here from Sign-in &
            // Security. The MCP skill markdown is an
            // MCP-integration concern, not an account / security
            // setting; placing it next to the MCP API key matches
            // the editor app's pattern.
            if (p.widget.onSaveMcpSkill != null) ...[
              const SizedBox(height: 16),
              Card(
                clipBehavior: Clip.antiAlias,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: McpSkillSection(
                    initialContent:
                        p.widget.settings?['mcp_skill_md']?.toString() ?? '',
                    onSave: p.widget.onSaveMcpSkill!,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Subpage 4 — Connected accounts. Lists Casdoor SSO link state and
/// exposes link / unlink controls.
class _ConnectedAccountsPage extends StatelessWidget {
  const _ConnectedAccountsPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Connected accounts')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _ConnectedAccountsSection(
                  onBindCasdoor: p.widget.onBindCasdoor,
                  onUnlinkCasdoor: p.widget.onUnlinkCasdoor,
                  casdoorLinked: p.widget.settings?['casdoor_linked'] == true,
                  casdoorOrgLoginUrl: p.widget.casdoorOrgLoginUrl,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const _SettingsCaption(
              text: 'Casdoor proxies third-party identities (Google, '
                  'GitHub, etc.) — configure them on the Casdoor '
                  "application's Providers tab.",
            ),
          ],
        ),
      ),
    );
  }
}

/// Subpage 5 — Portal preferences. Theme preset + theme mode +
/// default editor mode. Each row opens a picker bottom sheet and
/// auto-saves the choice. Portal currently has no deadline-weight
/// controls (planner-specific), so this page is shorter than the
/// editor's equivalent.
class _PortalPreferencesPage extends StatefulWidget {
  const _PortalPreferencesPage({required this.parent});

  final _SettingsPageState parent;

  @override
  State<_PortalPreferencesPage> createState() => _PortalPreferencesPageState();
}

class _PortalPreferencesPageState extends State<_PortalPreferencesPage> {
  /// Local echo of the picked Language so the row updates immediately;
  /// the parent's `currentLocale` only refreshes on the next app-shell
  /// rebuild. Mirrors the editor's `_localeOverride`.
  String? _localeOverride;

  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Portal preferences')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            _SettingsGroupCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: const Text('Default editor mode'),
                  subtitle: Text(_editorModeLabel(p._editorMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked =
                        await _pickEditorMode(context, p._editorMode);
                    if (picked != null) {
                      setState(() => p._editorMode = picked);
                      p.refreshState();
                      await p._autoSavePreferences();
                    }
                  },
                ),
                const Divider(height: 0, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Theme preset'),
                  subtitle: Text(_themePresetLabel(p._themePreset)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked =
                        await _pickThemePreset(context, p._themePreset);
                    if (picked != null) {
                      setState(() => p._themePreset = picked);
                      p.refreshState();
                      await p._autoSavePreferences();
                    }
                  },
                ),
                const Divider(height: 0, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: const Text('Theme mode'),
                  subtitle: Text(_themeModeLabel(p._themeMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final picked = await _pickThemeMode(context, p._themeMode);
                    if (picked != null) {
                      setState(() => p._themeMode = picked);
                      p.refreshState();
                      await p._autoSavePreferences();
                    }
                  },
                ),
                if (p.widget.onSetLocale != null) ...[
                  const Divider(height: 0, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.language_outlined),
                    title: Text(AppLocalizations.of(context).prefsLanguage),
                    subtitle: Text(_localeLabel(
                      context,
                      _localeOverride ?? p.widget.currentLocale ?? 'system',
                    )),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final current = _localeOverride ??
                          p.widget.currentLocale ??
                          'system';
                      final picked = await _pickLocale(context, current);
                      if (picked != null) {
                        await p.widget.onSetLocale!(picked);
                        if (mounted) {
                          setState(() => _localeOverride = picked);
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            const _SettingsCaption(
              text: 'Each change is saved and persisted immediately — '
                  'no Save button needed in this menu.',
            ),
          ],
        ),
      ),
    );
  }

  static String _editorModeLabel(String code) {
    for (final entry in kEditorModes) {
      if (entry.key == code) return entry.value;
    }
    return code;
  }

  static String _themePresetLabel(String code) {
    return kThemePresetEntries[code] ?? code;
  }

  static String _themeModeLabel(String code) {
    switch (code) {
      case 'L':
        return 'Light';
      case 'D':
        return 'Dark';
      case 'S':
      default:
        return 'Match system';
    }
  }

  Future<String?> _pickEditorMode(BuildContext context, String current) {
    return _pickFromList<String>(
      context,
      title: 'Default editor mode',
      current: current,
      options: [
        for (final entry in kEditorModes)
          _PickerOption(value: entry.key, label: entry.value),
      ],
      tooltip: 'Picks how new notes open by default. You can still switch '
          'modes per note from the editor toolbar.',
    );
  }

  Future<String?> _pickThemePreset(BuildContext context, String current) {
    return _pickFromList<String>(
      context,
      title: 'Theme preset',
      current: current,
      options: [
        for (final entry in kThemePresetEntries.entries)
          _PickerOption(value: entry.key, label: entry.value),
      ],
      tooltip: 'Each preset uses a different seed color for the '
          'Material 3 ColorScheme.',
    );
  }

  Future<String?> _pickThemeMode(BuildContext context, String current) {
    return _pickFromList<String>(
      context,
      title: 'Theme mode',
      current: current,
      options: const [
        _PickerOption(value: 'S', label: 'Match system'),
        _PickerOption(value: 'L', label: 'Light'),
        _PickerOption(value: 'D', label: 'Dark'),
      ],
      tooltip: 'Match system follows the device-level Light/Dark '
          'toggle. Light and Dark override the system choice.',
    );
  }

  String _localeLabel(BuildContext context, String value) {
    if (value == 'system') {
      return AppLocalizations.of(context).settingsLanguageSystem;
    }
    for (final opt in kLocaleOptions) {
      if (opt.value == value) return opt.label;
    }
    return value;
  }

  Future<String?> _pickLocale(BuildContext context, String current) {
    final l10n = AppLocalizations.of(context);
    return _pickFromList<String>(
      context,
      title: l10n.prefsLanguage,
      current: current,
      options: [
        for (final opt in kLocaleOptions)
          _PickerOption(
            value: opt.value,
            label:
                opt.value == 'system' ? l10n.settingsLanguageSystem : opt.label,
          ),
      ],
    );
  }
}

/// Subpage 6 — Backend settings. Offline-mode toggle plus the
/// experimental GitHub Sync card when authenticated. Portal has no
/// version-readout / handshake-info endpoints today so this page is
/// intentionally sparse — the spec called those out as future
/// additions; the page is in place so they have a home.
class _BackendSettingsPage extends StatefulWidget {
  const _BackendSettingsPage({required this.parent});

  final _SettingsPageState parent;

  @override
  State<_BackendSettingsPage> createState() => _BackendSettingsPageState();
}

class _BackendSettingsPageState extends State<_BackendSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    final offlineMode = p.widget.localSettings['offline_mode'] == true;
    final canEditOffline = p.widget.onOfflineModeChanged != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Backend settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            _SettingsGroupCard(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Offline mode'),
                  subtitle: const Text(
                    'Skip every remote fetch on startup; render '
                    'everything from the local cache.',
                  ),
                  value: offlineMode,
                  onChanged: canEditOffline
                      ? (value) {
                          p.widget.onOfflineModeChanged!(value);
                          setState(() {});
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SettingsGroupCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('Backend endpoint'),
                  subtitle: Text(
                    p.widget.apiBaseUrl ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const _SettingsCaption(
              text: 'Edit the API base URL on the API settings page. '
                  'A version / handshake readout will surface here once '
                  'the backend exposes it.',
            ),
            if (p.widget.githubSyncCardBuilder != null) ...[
              const SizedBox(height: 16),
              p.widget.githubSyncCardBuilder!(),
            ],
          ],
        ),
      ),
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

/// Subpage 7 — Local data. Sync, pull, clear cache, clear data,
/// export, import, restore templates. Mirrors the editor's
/// `_LocalDataPage` but keeps portal's `onClearLocalCache` row
/// (editor doesn't have it) and the admin-only template restore
/// (editor moves this to Developer; portal currently surfaces it
/// inline when admin).
class _LocalDataPage extends StatelessWidget {
  const _LocalDataPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Local data')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            // Storage usage — local-data breakdown + browser quota.
            _StorageUsageSection(
              backendHost: _hostOf(
                p.widget.apiBaseUrl ?? p.widget.localSettings['api_base_url'],
              ),
              onProbeStorageArch: p.widget.onProbeStorageArch,
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${p.widget.localDraftCount} local draft(s), '
                  '${p.widget.localCourseCount} local course(s).',
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsGroupCard(
              children: [
                if (p.widget.onExportLocalData != null)
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: const Text('Download local data'),
                    subtitle: const Text(
                      'Exports drafts, courses, settings, and logs '
                      'as a .nchron archive.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: p.widget.onExportLocalData,
                  ),
                if (p.widget.onExportLocalData != null &&
                    p.widget.onRestoreFromLocalImport != null)
                  const Divider(height: 0, indent: 16, endIndent: 16),
                if (p.widget.onRestoreFromLocalImport != null)
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: const Text('Restore from local archive'),
                    subtitle: const Text(
                      'Imports a previously-exported .nchron archive. '
                      'Replaces existing local data after a confirm '
                      'dialog.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: p.widget.onRestoreFromLocalImport,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsGroupCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: const Text('Push local → cloud'),
                  subtitle: const Text(
                    'Upload local drafts and courses to your cloud '
                    'account. Requires sign-in.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: p._isAuthenticated
                      ? () => p._runMaintenanceAction(
                            () => p.widget.onSyncLocalData(announce: false),
                          )
                      : null,
                ),
                const Divider(height: 0, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('Pull cloud → local'),
                  subtitle: const Text(
                    'Download notes and courses from the cloud to '
                    'this device.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: p._isAuthenticated
                      ? () => p._runMaintenanceAction(p.widget.onPullCloudData)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SettingsGroupCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text('Clear local cache'),
                  subtitle: const Text(
                    'Drops cached API responses but keeps drafts and '
                    'courses on disk.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      p._runMaintenanceAction(p.widget.onClearLocalCache),
                ),
                const Divider(height: 0, indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(
                    Icons.delete_sweep_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Remove local data',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    'Wipes drafts, courses, settings, and logs from '
                    'this device. Cloud copies are not touched.',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.8),
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onTap: () =>
                      p._runMaintenanceAction(p.widget.onClearLocalData),
                ),
              ],
            ),
            if (p._isAdmin) ...[
              const SizedBox(height: 16),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.science_outlined,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    title: const Text('Restore template courses'),
                    subtitle: const Text(
                      'Admin-only. Re-seeds the three-course template '
                      'catalog (Inbox / Examples / Templates).',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => p._runMaintenanceAction(
                        p.widget.onRestoreTemplateCourses),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const _SettingsCaption(
                text: 'Requires a signed-in admin account. Non-admin '
                    'sessions will see a server-side error in the '
                    'banner above without changing any data.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Subpage 8 — Recycle bin. Local recycle bin (synced drafts /
/// courses moved aside after a successful cloud promotion) plus the
/// cloud recycle bin (server-side soft-deletes).
class _RecycleBinPage extends StatelessWidget {
  const _RecycleBinPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    final recoverableCount =
        p.widget.localTrashedDraftCount + p.widget.localTrashedCourseCount;
    return Scaffold(
      appBar: AppBar(title: const Text('Recycle bin')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            _SettingsGroupCard(
              children: [
                if (p.widget.onOpenLocalRecycleBin != null)
                  ListTile(
                    leading: const Icon(Icons.restore_from_trash_outlined),
                    title: const Text('Synced local drafts'),
                    subtitle: Text(
                      '$recoverableCount item(s) waiting in the local '
                      'recycle bin.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: p.widget.onOpenLocalRecycleBin,
                  ),
                if (p.widget.onOpenLocalRecycleBin != null)
                  const Divider(height: 0, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Cloud recycle bin'),
                  subtitle: Text(
                    p._isAuthenticated
                        ? '${p.widget.deletedNotes.length} soft-deleted '
                            'note(s) on the server.'
                        : 'Sign in to manage deleted cloud notes.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: p._isAuthenticated ? p._openRecycleBinDialog : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 0.1.116: `_DebugPage` removed along with its menu-row entry in
// `settings.dart`. The inline Debug log card on the main Settings
// scroll (`_buildInlineDebugCard`, since 0.1.105) now owns the only
// debug surface, matching the editor app's pattern. Both the focused
// subpage and its menu row were carrying the same `DebugLogCard` /
// fallback widget — keeping them in lockstep was busywork. Restore
// from git history if a future surface needs a focused debug page.
