part of notechondria_frontend;

/// Build-helpers for `_SettingsPageState`: the big per-section Card
/// widgets (online-account, profile fields, preferences, debug) plus
/// the password/email change dialogs and the avatar preview. Routes
/// state mutations through `_refresh()` since extensions can't call
/// `setState` directly (same pattern used on `_AppShellState`).
/// Extracted from `modules/settings.dart` so that file stays closer
/// to the AGENTS.md §1.5 1000-line ceiling.
extension _SettingsPageBuildX on _SettingsPageState {
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
    showBlurDialog<void>(
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
    showBlurDialog<void>(
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
              _socialLinkError = null;
              _refresh();
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
            // API base URL is locked while the user is signed in: changing
            // backend mid-session would invalidate the token and lose
            // cached remote data. The lock + tooltip live inside
            // AppPreferencesCard.
            AppPreferencesCard(
              editorMode: _editorMode,
              themePreset: _themePreset,
              themeMode: _themeMode,
              apiBaseController: _apiBaseController,
              isAuthenticated: _isAuthenticated,
              onEditorModeChanged: (v) { _editorMode = v; _refresh(); },
              onThemePresetChanged: (v) { _themePreset = v; _refresh(); },
              onThemeModeChanged: (v) { _themeMode = v; _refresh(); },
              offlineMode: widget.onOfflineModeChanged == null
                  ? null
                  : widget.localSettings['offline_mode'] == true,
              onOfflineModeChanged: widget.onOfflineModeChanged == null
                  ? null
                  : (value) {
                      widget.onOfflineModeChanged!(value);
                    },
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
                if (widget.onExportLocalData != null)
                  OutlinedButton.icon(
                    onPressed: widget.onExportLocalData,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Download local user data'),
                  ),
                if (widget.onRestoreFromLocalImport != null)
                  OutlinedButton.icon(
                    onPressed: widget.onRestoreFromLocalImport,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Restore from local imports'),
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
    final summary =
        '${widget.localDraftCount} local draft(s), ${widget.localCourseCount} local category(ies).';
    final controller = widget.debugLogController;
    if (controller != null) {
      return DebugLogCard(
        controller: controller,
        title: 'Debug log',
        summary: summary,
        onCopyLogs: widget.onCopyLogs,
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
          ],
        ),
      ),
    );
  }
}
