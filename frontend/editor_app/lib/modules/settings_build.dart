part of notechondria_frontend;

/// Build-helpers for `_SettingsPageState`: the big per-section Card
/// widgets (online-account, profile fields, preferences, debug) plus
/// the password/email change dialogs and the avatar preview. Routes
/// state mutations through `refreshState()` since extensions can't call
/// `setState` directly (same pattern used on `_AppShellState`).
/// Extracted from `modules/settings.dart` so that file stays closer
/// to the AGENTS.md §1.5 1000-line ceiling.
extension _SettingsPageBuildX on _SettingsPageState {
  /// Online account section: login/register when signed out; profile fields,
  /// sync buttons, and logout when signed in. Hosts every control that only
  /// makes sense with an active cloud session.
  Widget _buildOnlineAccountSection(BuildContext context) {
    if (!_isAuthenticated) {
      return _buildSignedOutAccount(context);
    }
    return _buildSignedInAccount(context);
  }

  /// Signed-out variant: Sign-up + Login on the same row (equal-width
  /// FilledButtons), then two full-width pill buttons for the
  /// third-party providers ("Continue with Google" / "Continue with
  /// GitHub"). Each OAuth button spans the full row so it's easy to
  /// hit on mobile and reads as a primary CTA.
  Widget _buildSignedInAccount(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final username = widget.profile?['username']?.toString() ?? l10n.commonUser;
    final displayName = widget.profile?['display_name']?.toString() ?? username;
    final email = widget.profile?['email']?.toString() ?? '';
    final avatarUrl = widget.profile?['image_url']?.toString() ??
        widget.settings?['image_url']?.toString();
    final resolvedAvatar = avatarUrl != null && avatarUrl.isNotEmpty
        ? _resolveRemoteUrl(avatarUrl, apiBaseUrl: widget.apiBaseUrl)
        : '';
    return Column(
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
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
                title: Text(l10n.settingsPersonalInfoTitle),
                subtitle: Text(l10n.settingsPersonalInfoSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _PersonalInfoPage(parent: this),
                    ),
                  );
                },
              ),
              const Divider(height: 0, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(l10n.settingsSecurityTitle),
                subtitle: Text(l10n.settingsSecuritySubtitle),
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
                title: Text(l10n.settingsApiTitle),
                subtitle: Text(l10n.settingsApiSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _ApiSettingsPage(parent: this),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Logout sits in its own card, full-width, red text. Matches
        // the iOS Settings convention of a destructive bottom action
        // separated from the menu rows above.
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(Icons.logout, color: scheme.error),
            title: Text(
              l10n.settingsSignOut,
              style: TextStyle(
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: widget.onLogout,
          ),
        ),
      ],
    );
  }

  /// Signed-out account block. 0.1.120 unified this onto the shared
  /// `AuthHub` widget so editor + portal + planner render the same
  /// auth surface (Casdoor SSO pill + "Sign up via Casdoor" link +
  /// email/password fallback expander). The earlier in-line copies
  /// (`_OAuthPillButton`, `_legacyAuthBlock`, `_openLoginDialog`,
  /// `_casdoorBrowserLoginUrl`, `_openCasdoorBrowserLogin`) have all
  /// been deleted in favor of the shared widget.
  Widget _buildSignedOutAccount(BuildContext context) {
    return AuthHub(
      apiBaseUrl: widget.apiBaseUrl,
      onLogin: widget.onLogin,
      onCasdoorLogin: widget.onCasdoorLogin,
      casdoorOrgLoginUrl: widget.casdoorOrgLoginUrl,
    );
  }

  // ↓ The block below was the old in-line auth surface. Marked as
  //   dead code in 0.1.120; see AuthHub for the live implementation.
  //   Kept in this commit purely to make the diff easier to read;
  //   the next maintenance round can delete it outright.
  // ignore: unused_element

  Widget _buildProfileFields(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final avatarUrl = widget.profile?['image_url']?.toString() ??
        widget.settings?['image_url']?.toString();
    final resolvedAvatar = avatarUrl != null && avatarUrl.isNotEmpty
        ? _resolveRemoteUrl(avatarUrl, apiBaseUrl: widget.apiBaseUrl)
        : '';
    final username = widget.profile?['username']?.toString() ?? l10n.commonUser;
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
              label: Text(
                _uploadingAvatar
                    ? l10n.commonUploading
                    : l10n.settingsChangeAvatar,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstNameController,
                decoration: InputDecoration(
                  labelText: l10n.settingsFirstName,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lastNameController,
                decoration: InputDecoration(
                  labelText: l10n.settingsLastName,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _mottoController,
          decoration: InputDecoration(
            labelText: l10n.settingsMotto,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _socialController,
          decoration: InputDecoration(
            labelText: l10n.settingsSocialLink,
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
        const SizedBox(height: 12),
        // 0.1.120: per-account display label for the synthetic
        // uncategorized folder rendered at the top of the sidebar
        // (groups every note with no category). Falls back to "Inbox"
        // when blank, matching the backend default.
        TextField(
          controller: _uncategorizedFolderNameController,
          decoration: InputDecoration(
            labelText: l10n.settingsUncategorizedFolderName,
            helperText: l10n.settingsUncategorizedFolderHelp,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  void _previewAvatar(String imageUrl, String username) {
    if (imageUrl.isEmpty) return;
    final l10n = AppLocalizations.of(context);
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
                child: Text(l10n.commonClose),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Simplified debug log: local stats and recent UI logs with copy button.
  Widget _buildDebugSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final summary = l10n.editorDebugSummary(
      widget.localDraftCount,
      widget.localCourseCount,
    );
    final controller = widget.debugLogController;
    if (controller != null) {
      return Column(
        children: [
          DebugLogCard(
            controller: controller,
            title: l10n.debugLogTitle,
            summary: summary,
            onCopyLogs: widget.onCopyLogs,
            onPing: () => pingBackend(widget.apiBaseUrl),
          ),
          const SizedBox(height: 8),
          _AttachmentStorageTile(),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.debugLogTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(summary)),
                TextButton.icon(
                  onPressed: widget.onCopyLogs,
                  icon: const Icon(Icons.copy_all_outlined),
                  label: Text(l10n.debugCopyLogs),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: widget.uiLogs.isEmpty
                  ? Center(child: Text(l10n.debugNoLogs))
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
            const SizedBox(height: 8),
            _AttachmentStorageTile(),
          ],
        ),
      ),
    );
  }
}

/// Small tile showing local attachment storage usage. Loads
/// stats asynchronously from [LocalAttachmentStore] and displays
/// total bytes. Shows nothing when the store is empty or not
/// yet initialized.
class _AttachmentStorageTile extends StatefulWidget {
  @override
  State<_AttachmentStorageTile> createState() => _AttachmentStorageTileState();
}

class _AttachmentStorageTileState extends State<_AttachmentStorageTile> {
  int? _totalBytes;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    try {
      final store = await LocalAttachmentStore.open();
      final total = await store.totalBytes();
      if (mounted) {
        setState(() {
          _totalBytes = total;
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loaded = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _totalBytes == null || _totalBytes == 0) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final overLimit = _totalBytes! > 500 * 1024 * 1024;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.storage_outlined,
              size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            l10n.editorLocalAttachments(formatBytes(_totalBytes!)),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          if (overLimit) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: l10n.editorAttachmentsOverLimit,
              child: Icon(Icons.warning_amber_rounded,
                  size: 14, color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
