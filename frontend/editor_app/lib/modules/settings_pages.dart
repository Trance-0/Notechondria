part of notechondria_frontend;

/// Apple-style two-level Settings sub-pages. Each page is a pushed
/// route the top-level `_SettingsPage` opens via a row tap. Pages
/// host the actual controls — the top-level menu only hosts row
/// labels + chevrons. Tooltips explain non-obvious controls; no
/// round buttons in this layer (the spec calls for an Apple-style
/// list UI throughout).
///
/// All four pages reuse the parent's `_SettingsPageState` to read
/// + mutate fields like `_editorMode`, `_themePreset`, `_themeMode`,
/// and `_apiBaseController`. They take the parent state as a
/// constructor argument because Flutter's `Navigator.push` builds
/// the new route in a fresh widget subtree that doesn't have the
/// parent's `State` ancestor available via `findAncestorStateOfType`.

/// Subpage 1 — editor preferences. Default editor mode (P/M/T), theme
/// preset, theme mode. No backend / no offline-mode controls; those
/// live in `_BackendSettingsPage` next door.
class _EditorSettingsPage extends StatefulWidget {
  const _EditorSettingsPage({required this.parent});

  final _SettingsPageState parent;

  @override
  State<_EditorSettingsPage> createState() => _EditorSettingsPageState();
}

class _EditorSettingsPageState extends State<_EditorSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Editor settings')),
      body: ListView(
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
                  final picked = await _pickEditorMode(context, p._editorMode);
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
                  final picked = await _pickThemePreset(context, p._themePreset);
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
            ],
          ),
          const SizedBox(height: 12),
          const _SettingsCaption(
            text: 'Each change is saved and persisted immediately — '
                'no Save button needed in this menu.',
          ),
        ],
      ),
    );
  }

  static String _editorModeLabel(String code) {
    switch (code) {
      case 'P':
        return 'Plain text';
      case 'M':
        return 'Live markdown';
      case 'T':
        return 'Structured (block) editor';
      default:
        return code;
    }
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
      options: const [
        _PickerOption(value: 'P', label: 'Plain text'),
        _PickerOption(value: 'M', label: 'Live markdown'),
        _PickerOption(value: 'T', label: 'Structured (block) editor'),
      ],
      tooltip:
          'Picks how new notes open by default. You can still switch '
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
}

/// Subpage 2 — backend settings. Offline-mode toggle plus the API
/// base URL field. The API base URL is locked while authenticated
/// (changing the backend mid-session would invalidate the token).
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
      body: ListView(
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
          const SizedBox(height: 16),
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
                              'the backend the editor talks to.'
                          : 'Points the editor at a different '
                              'Notechondria backend. The handshake probe '
                              'verifies the URL before saving.',
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
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
                    hintText: 'https://example.com/api/v1',
                  ),
                  onChanged: (_) => p.refreshState(),
                  // Pressing Enter (or hitting Save in software
                  // keyboard) commits the URL change immediately so
                  // the user doesn't have to back out to the parent
                  // page to find a Save button.
                  onSubmitted: (_) {
                    p._autoSavePreferences();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const _SettingsCaption(
            text: 'Press Enter in the API field to apply the URL '
                'change. You will be asked to confirm the handshake '
                'response before the URL replaces the active '
                'backend. Offline-mode toggle saves immediately.',
          ),
        ],
      ),
    );
  }
}

/// Subpage 3 — local data. Download (export `.nchron`) and restore
/// (import `.nchron`). The two actions are stacked rather than side-
/// by-side so the labels can stay readable on a phone.
class _LocalDataPage extends StatelessWidget {
  const _LocalDataPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Local data')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeedbackBanner(parent: p),
          _SettingsGroupCard(
            children: [
              if (p.widget.onExportLocalData != null)
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Download local data'),
                  subtitle: const Text(
                    'Exports drafts, categories, settings, and logs '
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
                  'Upload local drafts and categories to your cloud '
                  'account. Requires sign-in.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => p._runMaintenanceAction(
                  () => p.widget.onSyncLocalData(announce: false),
                ),
              ),
              const Divider(height: 0, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.download_for_offline_outlined),
                title: const Text('Pull cloud → local'),
                subtitle: const Text(
                  'Download notes and categories from the cloud to '
                  'this device.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => p._runMaintenanceAction(p.widget.onPullCloudData),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingsGroupCard(
            children: [
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Restore starter inbox'),
                subtitle: const Text(
                  'Re-seeds the local Inbox category and welcome '
                  'note. Safe to run any time — only fires when the '
                  'workspace is empty.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => p._runMaintenanceAction(
                    p.widget.onRestoreLocalStarterTemplate),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const _SettingsCaption(
            text: 'The legacy three-course template restore (admin-'
                'only, requires a cloud session) is now in the '
                'Developer section of the main Settings page.',
          ),
        ],
      ),
    );
  }
}

/// Subpage 5 — Developer. Houses controls that aren't appropriate for
/// regular users — currently the admin-only `restoreTemplateCourses`
/// remote endpoint that re-seeds three template courses on the
/// backend. Tucked under its own page so the user-facing Local data
/// page stays uncluttered.
class _DeveloperSettingsPage extends StatelessWidget {
  const _DeveloperSettingsPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Developer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeedbackBanner(parent: p),
          _SettingsGroupCard(
            children: [
              ListTile(
                leading: Icon(
                  Icons.science_outlined,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                title: const Text('Restore remote template courses'),
                subtitle: const Text(
                  'Admin-only. Calls the backend to re-seed the '
                  'three-course template catalog (Inbox / Examples / '
                  'Templates) with a welcome note in each.',
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
                'sessions will see a server-side error in the banner '
                'above without changing any data.',
          ),
        ],
      ),
    );
  }
}

/// Subpage 4 — recycle bins. Two stacked groups: client-side recycle
/// bin (synced local drafts moved aside after a successful cloud
/// promotion, restorable) and the cloud recycle bin (notes the user
/// soft-deleted).
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
      body: ListView(
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
              const Divider(height: 0, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Cloud recycle bin'),
                subtitle: Text(
                  '${p.widget.deletedNotes.length} soft-deleted note(s) '
                  'on the server.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: p._openRecycleBinDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Subpage 6 — Personal information. Avatar + name + motto + social
/// link. Delegates to the existing `_buildProfileFields` builder on
/// `_SettingsPageBuildX` so the form layout stays in one place;
/// adds the explicit Save / Cancel row that the sub-page needs.
class _PersonalInfoPage extends StatefulWidget {
  const _PersonalInfoPage({required this.parent});

  final _SettingsPageState parent;

  @override
  State<_PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<_PersonalInfoPage> {
  @override
  Widget build(BuildContext context) {
    final p = widget.parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Personal information')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeedbackBanner(parent: p),
          Card(
            clipBehavior: Clip.antiAlias,
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
    );
  }
}

/// Subpage 7 — Sign-in & security. Hosts the third-party-account
/// linking widget plus change-email and change-password actions.
class _SignInSecurityPage extends StatelessWidget {
  const _SignInSecurityPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in & security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeedbackBanner(parent: p),
          // Active Sessions card — multi-device session manager
          // shipped in 0.1.65 (backend) / this round (frontend).
          // Lists every device currently signed in to the user's
          // account; the trash button revokes by id. The card
          // hides itself when signed out (its `onListSessions`
          // callback is null then).
          if (p.widget.onListSessions != null &&
              p.widget.onRevokeSession != null) ...[
            ActiveSessionsCard(
              onListSessions: p.widget.onListSessions!,
              onRevokeSession: p.widget.onRevokeSession!,
              onCurrentRevoked: p.widget.onCurrentSessionRevoked,
            ),
            const SizedBox(height: 16),
          ],
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _ConnectedAccountsSection(
                onListSocialAccounts: p.widget.onListSocialAccounts,
                onUnlinkSocialAccount: p.widget.onUnlinkSocialAccount,
                onBindGoogle: p.widget.onBindGoogle,
                onBindGithub: p.widget.onBindGithub,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SettingsGroupCard(
            children: [
              if (p.widget.onChangeEmailRequest != null)
                ListTile(
                  leading: const Icon(Icons.alternate_email_outlined),
                  title: const Text('Change email'),
                  subtitle: Text(
                    p.widget.profile?['email']?.toString() ?? '',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => p._openChangeEmailDialog(context),
                ),
              if (p.widget.onChangeEmailRequest != null &&
                  p.widget.onChangePassword != null)
                const Divider(height: 0, indent: 16, endIndent: 16),
              if (p.widget.onChangePassword != null)
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  subtitle: const Text(
                    'Identity-code verified two-step flow.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => p._openChangePasswordDialog(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Subpage 8 — API settings. Currently surfaces the MCP API key
/// section. Future per-app integration keys (Linear, Slack, ...)
/// can stack into the same page.
class _ApiSettingsPage extends StatelessWidget {
  const _ApiSettingsPage({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    final p = parent;
    return Scaffold(
      appBar: AppBar(title: const Text('API settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FeedbackBanner(parent: p),
          Card(
            clipBehavior: Clip.antiAlias,
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
          if (p.widget.onSaveMcpSkill != null) ...[
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _McpSkillSection(
                  initialContent:
                      p.widget.settings?['mcp_skill_md']?.toString() ?? '',
                  onSave: p.widget.onSaveMcpSkill!,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Experimental — GitHub Sync',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Push your full account (profile, settings, MCP '
                    'skill, courses, notes, custom meta, planner '
                    'events) to a GitHub repo you own so you can '
                    'recover everything if our server is wiped. '
                    'Static assets we host (avatars, attachments, '
                    'cover images) are referenced by URL, not '
                    'committed. Wire-up requires a Notechondria '
                    'GitHub App install — see docs/integrations/'
                    'github-sync.md for the full flow.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Connect to GitHub (coming soon)'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Apple-style grouped settings card. Wraps a column of `ListTile`s
/// (or any widget) in a rounded surface with no padding so the rows
/// can render edge-to-edge inside the card.
class _SettingsGroupCard extends StatelessWidget {
  const _SettingsGroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

/// Top-of-body banner that mirrors `_SettingsPageState._feedback` —
/// every long-running action (`_runMaintenanceAction`, the avatar
/// upload, settings save, ...) writes the result here. The top page
/// AND every pushed sub-page wrap their content with this widget so
/// errors / success messages surface wherever the user actually
/// triggered the action.
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.parent});

  final _SettingsPageState parent;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ActionFeedback?>(
      valueListenable: parent._feedback,
      builder: (context, feedback, _) {
        if (feedback == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: FeedbackText(feedback: feedback),
        );
      },
    );
  }
}

/// Small italicized caption shown under settings groups to explain
/// behavior. Mirrors iOS Settings' grey footer text style.
class _SettingsCaption extends StatelessWidget {
  const _SettingsCaption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

/// Single option in a value-picker bottom sheet.
class _PickerOption<T> {
  const _PickerOption({required this.value, required this.label});
  final T value;
  final String label;
}

/// Apple-style picker bottom sheet. Replaces the current settings'
/// inline radio chips with a tap-to-pick row that opens this sheet,
/// matching the navigation-row pattern used elsewhere on this page.
Future<T?> _pickFromList<T>(
  BuildContext context, {
  required String title,
  required T current,
  required List<_PickerOption<T>> options,
  String? tooltip,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (tooltip != null)
                    Tooltip(
                      message: tooltip,
                      child: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(sheetContext)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            for (final option in options)
              ListTile(
                title: Text(option.label),
                trailing: option.value == current
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option.value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
