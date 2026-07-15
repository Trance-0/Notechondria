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
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).settingsPersonalInfoTitle)),
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).settingsSecurityTitle)),
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
              l10n.settingsAccountCasdoorNotice,
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar:
          AppBar(title: Text(AppLocalizations.of(context).settingsApiTitle)),
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
                        l10n.prefsApiBaseUrl,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: p._isAuthenticated
                            ? l10n.settingsApiBaseLockedTooltip
                            : l10n.settingsApiBaseTooltip,
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
            _SettingsCaption(
              text: l10n.settingsApiBaseApplyCaption,
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
              _SettingsCaption(
                text: l10n.settingsMcpKeyCaption,
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).settingsConnectedAccounts)),
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
            _SettingsCaption(
              text: l10n.settingsConnectedAccountsCaption,
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

  late final TextEditingController _splashUrlController =
      TextEditingController(
    text: widget.parent.widget.localSettings['splash_image_url']?.toString() ??
        '',
  );

  @override
  void dispose() {
    _splashUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    return Scaffold(
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).settingsPortalPreferences)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            _SettingsGroupCard(
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_note_outlined),
                  title: Text(
                      AppLocalizations.of(context).settingsDefaultEditorMode),
                  subtitle: Text(_editorModeLabel(context, p._editorMode)),
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
                  title: Text(AppLocalizations.of(context).settingsThemePreset),
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
                  title: Text(AppLocalizations.of(context).settingsThemeMode),
                  subtitle: Text(_themeModeLabel(context, p._themeMode)),
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
            if (p.widget.onApplyLocalSettings != null) ...[
              const SizedBox(height: 12),
              _SettingsGroupCard(
                children: [
                  ListTile(
                    leading: const Icon(Icons.wallpaper_outlined),
                    title: const Text('Startup image'),
                    subtitle: Text(_splashImageLabel(p)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _splashUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Remote image URL',
                        hintText: 'https://example.com/startup.png',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveSplashUrl(p),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.link, size: 18),
                          label: const Text('Use URL'),
                          onPressed: () => _saveSplashUrl(p),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_outlined,
                              size: 18),
                          label: const Text('Upload image (≤50 MB)'),
                          onPressed: () => _uploadSplashImage(p),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('Reset to default'),
                          onPressed: () => _resetSplashImage(p),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _SettingsCaption(
              text: AppLocalizations.of(context).settingsImmediateSaveCaption,
            ),
          ],
        ),
      ),
    );
  }

  String _splashImageLabel(_SettingsPageState p) {
    final local = p.widget.localSettings['splash_image_local']?.toString() ?? '';
    final url = p.widget.localSettings['splash_image_url']?.toString() ?? '';
    if (local.isNotEmpty) return 'Custom uploaded image';
    if (url.isNotEmpty) return url;
    return 'Default reactor animation';
  }

  Future<void> _saveSplashUrl(_SettingsPageState p) async {
    final url = _splashUrlController.text.trim();
    if (url.isEmpty) return;
    await p.widget.onApplyLocalSettings!({
      'splash_image_url': url,
      'splash_image_local': '',
    });
    if (mounted) setState(() {});
  }

  Future<void> _uploadSplashImage(_SettingsPageState p) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > 50 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Startup image not set: file exceeds 50 MB.')));
      }
      return;
    }
    final store = await LocalAttachmentStore.open();
    await store.put(
      noteUuid: 'app-splash',
      filename: 'startup-image',
      contentType: 'image/*',
      bytes: bytes,
    );
    await p.widget.onApplyLocalSettings!({
      'splash_image_local': 'local://app-splash/startup-image',
      'splash_image_url': '',
    });
    if (mounted) setState(() {});
  }

  Future<void> _resetSplashImage(_SettingsPageState p) async {
    await p.widget.onApplyLocalSettings!({
      'splash_image_local': '',
      'splash_image_url': '',
    });
    _splashUrlController.clear();
    if (mounted) setState(() {});
  }

  static String _editorModeLabel(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context);
    if (code == 'P') return l10n.prefsEditorPlain;
    if (code == 'M') return l10n.prefsEditorMarkdown;
    for (final entry in kEditorModes) {
      if (entry.key == code) return entry.value;
    }
    return code;
  }

  static String _themePresetLabel(String code) {
    return kThemePresetEntries[code] ?? code;
  }

  static String _themeModeLabel(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context);
    switch (code) {
      case 'L':
        return l10n.prefsThemeModeLight;
      case 'D':
        return l10n.prefsThemeModeDark;
      case 'S':
      default:
        return l10n.settingsThemeModeMatchSystem;
    }
  }

  Future<String?> _pickEditorMode(BuildContext context, String current) {
    final l10n = AppLocalizations.of(context);
    return _pickFromList<String>(
      context,
      title: l10n.prefsDefaultEditor,
      current: current,
      options: [
        for (final entry in kEditorModes)
          _PickerOption(
            value: entry.key,
            label: _editorModeLabel(context, entry.key),
          ),
      ],
      tooltip: l10n.settingsEditorModePickerHelp,
    );
  }

  Future<String?> _pickThemePreset(BuildContext context, String current) {
    final l10n = AppLocalizations.of(context);
    return _pickFromList<String>(
      context,
      title: l10n.prefsThemePreset,
      current: current,
      options: [
        for (final entry in kThemePresetEntries.entries)
          _PickerOption(value: entry.key, label: entry.value),
      ],
      tooltip: l10n.settingsThemePresetPickerHelp,
    );
  }

  Future<String?> _pickThemeMode(BuildContext context, String current) {
    final l10n = AppLocalizations.of(context);
    return _pickFromList<String>(
      context,
      title: l10n.prefsThemeMode,
      current: current,
      options: [
        _PickerOption(value: 'S', label: l10n.settingsThemeModeMatchSystem),
        _PickerOption(value: 'L', label: l10n.prefsThemeModeLight),
        _PickerOption(value: 'D', label: l10n.prefsThemeModeDark),
      ],
      tooltip: l10n.settingsThemeModePickerHelp,
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
    final l10n = AppLocalizations.of(context);
    final offlineMode = p.widget.localSettings['offline_mode'] == true;
    final canEditOffline = p.widget.onOfflineModeChanged != null;
    return Scaffold(
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).settingsBackendTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FeedbackBanner(parent: p),
            _SettingsGroupCard(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_off_outlined),
                  title: Text(l10n.prefsOfflineMode),
                  subtitle: Text(l10n.settingsOfflineModeSubtitleShort),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.dns_outlined),
                      const SizedBox(width: 12),
                      Text(
                        l10n.prefsApiBaseUrl,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: p._isAuthenticated
                            ? l10n.settingsApiBaseLockedTooltip
                            : l10n.settingsApiBaseTooltip,
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
                    // Pressing Enter commits the URL change immediately so a
                    // signed-out user can repoint the backend without
                    // hunting for a Save button.
                    onSubmitted: (_) => p._autoSavePreferences(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _SettingsCaption(
              text: l10n.settingsApiBaseApplyLockedCaption,
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(AppLocalizations.of(context).settingsLocalDataTitle)),
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
                  l10n.settingsLocalDataCounts(
                    p.widget.localDraftCount,
                    p.widget.localCourseCount,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SettingsGroupCard(
              children: [
                if (p.widget.onExportLocalData != null)
                  ListTile(
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text(l10n.settingsDownloadLocalData),
                    subtitle: Text(l10n.settingsDownloadLocalDataSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: p.widget.onExportLocalData,
                  ),
                if (p.widget.onExportLocalData != null &&
                    p.widget.onRestoreFromLocalImport != null)
                  const Divider(height: 0, indent: 16, endIndent: 16),
                if (p.widget.onRestoreFromLocalImport != null)
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined),
                    title: Text(l10n.settingsRestoreLocalArchive),
                    subtitle: Text(l10n.settingsRestoreLocalArchiveSubtitle),
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
                  title: Text(l10n.settingsPushLocalCloud),
                  subtitle: Text(l10n.settingsPushLocalCloudSubtitle),
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
                  title: Text(l10n.settingsPullCloudLocal),
                  subtitle: Text(l10n.settingsPullCloudLocalSubtitle),
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
                  title: Text(l10n.settingsClearLocalCache),
                  subtitle: Text(l10n.settingsClearLocalCacheSubtitle),
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
                    l10n.settingsRemoveLocalData,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(
                    l10n.settingsRemoveLocalDataSubtitle,
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
                    title: Text(l10n.settingsRestoreTemplateCourses),
                    subtitle: Text(l10n.settingsRestoreTemplateCoursesSubtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => p._runMaintenanceAction(
                        p.widget.onRestoreTemplateCourses),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _SettingsCaption(
                text: l10n.settingsRestoreTemplateCoursesCaption,
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
    final l10n = AppLocalizations.of(context);
    final recoverableCount =
        p.widget.localTrashedDraftCount + p.widget.localTrashedCourseCount;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsRecycleBinTitle)),
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
                    title: Text(l10n.settingsSyncedLocalDrafts),
                    subtitle: Text(
                      l10n.settingsLocalRecycleCount(recoverableCount),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: p.widget.onOpenLocalRecycleBin,
                  ),
                if (p.widget.onOpenLocalRecycleBin != null)
                  const Divider(height: 0, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(l10n.settingsCloudRecycleBin),
                  subtitle: Text(
                    p._isAuthenticated
                        ? l10n.settingsCloudRecycleCount(
                            p.widget.deletedNotes.length,
                          )
                        : l10n.settingsCloudRecycleSignIn,
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
