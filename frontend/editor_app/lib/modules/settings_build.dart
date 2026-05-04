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
    final scheme = Theme.of(context).colorScheme;
    final username = widget.profile?['username']?.toString() ?? 'User';
    final displayName =
        widget.profile?['display_name']?.toString() ?? username;
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
                title: const Text('Personal information'),
                subtitle: const Text('Avatar, name, motto, social link.'),
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
                title: const Text('Sign in & security'),
                subtitle: const Text(
                  'Third-party accounts, email, password.',
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
                subtitle: const Text('MCP API key + endpoint.'),
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
              'Logout',
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

  /// Signed-out account block. Sign-up and Login live on the same
  /// row as equal-width FilledButtons (per spec: "always as button
  /// in the same row"); the two third-party providers stack as
  /// full-width pill buttons below ("show in round button, span
  /// horizontal line").
  Widget _buildSignedOutAccount(BuildContext context) {
    final hasCasdoor = widget.onCasdoorLogin != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Account',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasCasdoor
                  ? 'Sign in via the Notechondria SSO. Account creation '
                      'and password reset are handled on the Casdoor '
                      'side; use the link below to register or contact '
                      'the administrator if your password needs to be '
                      'reset.'
                  : 'Sign in to sync notes with the cloud. Local notes '
                      'stay editable while signed out.',
            ),
            const SizedBox(height: 16),
            if (hasCasdoor) ...[
              _OAuthPillButton(
                icon: Icons.shield_outlined,
                label: 'Continue with Casdoor SSO',
                onPressed: widget.onCasdoorLogin!,
              ),
            ],
            if (_casdoorBrowserLoginUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openCasdoorBrowserLogin,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Login via third party'),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _openCasdoorBrowserLogin,
                  icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                  label: const Text('No account? Sign up via Casdoor'),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: toggleLegacyAuthFallback,
                icon: Icon(
                  _showLegacyAuthFallback
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 18,
                ),
                label: Text(
                  _showLegacyAuthFallback
                      ? 'Hide email / password fallback'
                      : 'Use email / password instead',
                ),
              ),
            ),
            if (_showLegacyAuthFallback) ...[
              const Divider(),
              const SizedBox(height: 8),
              _legacyAuthBlock(context),
            ],
          ],
        ),
      ),
    );
  }

  /// Casdoor org-login page URL (e.g. https://auth.trance-0.com/login/notechondria).
  /// Empty string when the backend hasn't reported a Casdoor config —
  /// in that state the third-party / signup CTAs collapse.
  String get _casdoorBrowserLoginUrl =>
      widget.casdoorOrgLoginUrl ?? '';

  void _openCasdoorBrowserLogin() {
    final url = _casdoorBrowserLoginUrl;
    if (url.isEmpty) return;
    url_strategy.browserRedirect(url);
  }

  /// Legacy email + password Login block. After the 0.1.103 cutover,
  /// signup lives on the Casdoor side — this block is just the
  /// fallback Login button + a caption pointing un-migrated users
  /// at the administrator for password resets.
  Widget _legacyAuthBlock(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonal(
          onPressed: () => _openLoginDialog(context),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Login'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Forgot password? Contact the administrator to reset it. '
          'Self-service password reset has moved to Casdoor for '
          'accounts that have been migrated.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Opens the email-password login dialog. After the 0.1.103 cutover,
  /// self-registration and password reset both moved to the Casdoor
  /// side \u2014 there's no in-app signup wizard or forgot-password flow
  /// anymore; the dialog only needs the username + password fields.
  void _openLoginDialog(BuildContext context) {
    showBlurDialog<void>(
      context: context,
      child: EmailPasswordDialog(
        title: 'Login',
        description: _apiBaseHostSubtitle(),
        submitLabel: 'Login',
        emailLabel: 'Email or username',
        onSubmit: widget.onLogin,
      ),
    );
  }

  /// Format the API host as a friendly subtitle for the login
  /// dialog. Mirrors the helper that used to live inside `AuthHub`.
  String _apiBaseHostSubtitle() {
    final raw = widget.apiBaseUrl ?? '';
    if (raw.isEmpty) return 'Sign in to your Notechondria backend.';
    final uri = Uri.tryParse(raw);
    final host = uri?.host;
    if (host == null || host.isEmpty) {
      return 'Sign in to your Notechondria backend.';
    }
    return 'Signing in to $host.';
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
              _socialLinkError = null;
              refreshState();
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

  /// Simplified debug log: local stats and recent UI logs with copy button.
  Widget _buildDebugSection(BuildContext context) {
    final summary =
        '${widget.localDraftCount} local draft(s), ${widget.localCourseCount} local category(ies).';
    final controller = widget.debugLogController;
    if (controller != null) {
      return Column(
        children: [
          DebugLogCard(
            controller: controller,
            title: 'Debug log',
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
              'Debug log',
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
            const SizedBox(height: 8),
            _AttachmentStorageTile(),
          ],
        ),
      ),
    );
  }
}

/// Full-width pill button used for the third-party OAuth providers
/// in the signed-out account block. Apple-style: rounded, single
/// line, span horizontal with a leading icon. Uses `OutlinedButton`
/// (not FilledButton) so the providers don't compete visually with
/// the primary Sign-up CTA above.
class _OAuthPillButton extends StatelessWidget {
  const _OAuthPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(48),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
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
  State<_AttachmentStorageTile> createState() =>
      _AttachmentStorageTileState();
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
            'Local attachments: ${formatBytes(_totalBytes!)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          if (overLimit) ...[
            const SizedBox(width: 8),
            Tooltip(
              message:
                  'Attachments exceed 500 MB — sync to free up space.',
              child: Icon(Icons.warning_amber_rounded,
                  size: 14, color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
