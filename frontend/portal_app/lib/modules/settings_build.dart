part of notechondria_frontend;

/// Apple-style grouped settings card. Wraps a column of `ListTile`s
/// (or any widget) in a rounded surface with no padding so the rows
/// can render edge-to-edge inside the card. Mirrors the editor's
/// primitive of the same name; copied here intentionally so portal
/// doesn't reach across app boundaries (per AGENTS.md §1.2 — three
/// similar lines beats a premature shared abstraction).
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

/// Top-of-body banner that mirrors `_SettingsPageState._feedback`
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
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
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

/// Apple-style picker bottom sheet. A tap on a settings row opens
/// this sheet and returns the picked value (or null if dismissed).
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

/// Build-helpers for `_SettingsPageState`: the signed-in / signed-out
/// account block, profile-fields editor, avatar upload handler, and
/// the small helpers that the sub-pages reuse. Routes state mutations
/// through `refreshState()` since extensions can't call `setState`
/// directly (same pattern used on `_AppShellState`).
extension _SettingsPageBuildX on _SettingsPageState {
  /// Online account section: AuthHub when signed out; account card
  /// with avatar / nav rows when signed in.
  Widget _buildOnlineAccountSection(BuildContext context) {
    if (!_isAuthenticated) {
      return _buildSignedOutAccount(context);
    }
    return _buildSignedInAccount(context);
  }

  /// Signed-out account block. Renders the shared `AuthHub` which
  /// already handles Casdoor primary + email/password fallback
  /// behind an expander. Wrapped in a Padding so it sits flush with
  /// the rest of the Apple-style cards.
  Widget _buildSignedOutAccount(BuildContext context) {
    return AuthHub(
      onLogin: widget.onLogin,
      onCasdoorLogin: widget.onCasdoorLogin,
      casdoorOrgLoginUrl: widget.casdoorOrgLoginUrl,
      apiBaseUrl: widget.apiBaseUrl,
    );
  }

  /// Signed-in account card: avatar + display-name + email header,
  /// followed by nav rows for Personal information, Sign in & security,
  /// API settings, and Connected accounts.
  Widget _buildSignedInAccount(BuildContext context) {
    final username = widget.profile?['username']?.toString() ?? 'User';
    final displayName =
        widget.profile?['display_name']?.toString() ?? username;
    final email = widget.profile?['email']?.toString() ?? '';
    final avatarUrl = widget.profile?['image_url']?.toString() ??
        widget.settings?['image_url']?.toString();
    final resolvedAvatar = avatarUrl != null && avatarUrl.isNotEmpty
        ? _resolveRemoteUrl(avatarUrl, apiBaseUrl: widget.apiBaseUrl)
        : '';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: _RemoteAvatar(
              radius: 20,
              imageUrl: resolvedAvatar,
              fallbackLabel: username,
            ),
            title: Text(
              displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: email.isEmpty ? null : Text(email),
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Personal information'),
            subtitle: const Text('Avatar, username, motto, social link.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _PersonalInformationPage(parent: this),
                ),
              );
            },
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Sign in & security'),
            subtitle: const Text(
              'Active sessions, change email, change password, agent skill.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _SignInSecurityPage(parent: this),
                ),
              );
            },
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('API settings'),
            subtitle: const Text('API base URL and MCP key.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _ApiSettingsPage(parent: this),
                ),
              );
            },
          ),
          const Divider(height: 0, indent: 16, endIndent: 16),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('Connected accounts'),
            subtitle: Text(
              widget.settings?['casdoor_linked'] == true
                  ? 'Casdoor SSO linked.'
                  : 'No third-party accounts linked.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _ConnectedAccountsPage(parent: this),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Profile fields shown on `_PersonalInformationPage`: avatar
  /// preview + name + motto + social link. Email is intentionally
  /// not exposed here — verified change-email flow lives on the
  /// Sign-in & security page.
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
        TextField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
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
              _socialLinkError = null;
              refreshState();
            }
          },
        ),
      ],
    );
  }

  /// Whether any profile field has been edited since the last load
  /// from the server.
  bool get _hasProfileChanges {
    final s = widget.settings ?? const {};
    final p = widget.profile ?? const {};
    final serverUsername =
        s['username']?.toString() ?? p['username']?.toString() ?? '';
    final serverMotto = s['motto']?.toString() ?? '';
    final serverSocial = s['social_link']?.toString() ?? '';
    return _usernameController.text.trim() != serverUsername ||
        _mottoController.text.trim() != serverMotto ||
        _socialController.text.trim() != serverSocial;
  }

  /// Restores profile fields to server values.
  void _cancelProfileChanges() {
    final s = widget.settings ?? const {};
    final p = widget.profile ?? const {};
    _usernameController.text =
        s['username']?.toString() ?? p['username']?.toString() ?? '';
    _mottoController.text = s['motto']?.toString() ?? '';
    _socialController.text = s['social_link']?.toString() ?? '';
    refreshState();
  }

  /// Save / Cancel button pair shared by the Personal information page.
  Widget _buildSectionButtons({
    required bool hasChanges,
    required VoidCallback onCancel,
  }) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _submitSettings,
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
              foregroundColor:
                  hasChanges ? null : Theme.of(context).colorScheme.outline,
            ),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }

  /// Auto-save hook used by the Apple-style preference sub-pages
  /// each pick on the sub-page calls this so the change persists
  /// across restarts without the user having to back out and tap
  /// Save. Delegates to `_submitSettings` which already pushes every
  /// field to the host.
  Future<void> _autoSavePreferences() async {
    await _submitSettings();
  }

  /// Opens a full-screen avatar preview when the user taps the
  /// circular avatar on the Personal information page.
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
}
