import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shell/url_strategy.dart'
    if (dart.library.html) '../app_shell/url_strategy_web.dart' as url_strategy;
import '../l10n/app_localizations.dart';
import '../models/action_feedback.dart';

/// Editable text area for the user's MCP `skill.md`. Surfaced to MCP-
/// connected agents as the `instructions` field of the JSON-RPC
/// `initialize` response. Treat it as a personal prompt playbook:
/// import sources, preferred note formats, target export platforms,
/// and any other agent-facing preferences.
///
/// Shared across editor / planner / portal so the surface stays
/// identical regardless of which app the user opens.
class McpSkillSection extends StatefulWidget {
  const McpSkillSection({
    required this.initialContent,
    required this.onSave,
    super.key,
  });

  final String initialContent;
  final Future<ActionFeedback> Function(String skillMd) onSave;

  @override
  State<McpSkillSection> createState() => _McpSkillSectionState();
}

class _McpSkillSectionState extends State<McpSkillSection> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialContent);
  bool _saving = false;
  String _lastSaved = '';

  @override
  void initState() {
    super.initState();
    _lastSaved = widget.initialContent;
  }

  @override
  void didUpdateWidget(covariant McpSkillSection old) {
    super.didUpdateWidget(old);
    if (old.initialContent != widget.initialContent &&
        _controller.text == old.initialContent) {
      _controller.text = widget.initialContent;
      _lastSaved = widget.initialContent;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await widget.onSave(_controller.text);
      if (!mounted) return;
      if (!result.isError) {
        _lastSaved = _controller.text;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy() async {
    final text = _controller.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).mcpSkillCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dirty = _controller.text != _lastSaved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.mcpSkillTitle,
          style:
              theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.mcpSkillDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          minLines: 8,
          maxLines: 24,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: l10n.mcpSkillHint,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: dirty && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(l10n.commonSave),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _controller.text.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l10n.commonCopy),
            ),
            const Spacer(),
            if (dirty)
              Text(
                l10n.mcpSkillUnsavedChanges,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Stateful "Connect to GitHub" card for the experimental data-sync
/// feature. Shared across editor / planner / portal. Three states:
///
/// - **No callbacks** (signed out): renders a passive description card
///   so anonymous users still see what the feature is.
/// - **Disconnected** (callbacks present, status returns
///   `connected: false`): renders an "Install Notechondria GitHub App"
///   button that opens `install_url` in a new tab. After the GitHub
///   App callback returns, the host page is responsible for calling
///   `onConnect(installation_id)` from the URL query string.
/// - **Connected**: renders a repo-picker dropdown sourced from
///   `onListRepos()`, a "Push now" action that calls `onPushNow()` and
///   surfaces the resulting commit SHA, and a Disconnect button.
///
/// The widget never makes its own HTTP calls — every network operation
/// is delegated to a callback so each app's `NotechondriaClient` keeps
/// owning the HTTP layer. Errors are surfaced via the SnackBar pattern
/// already used by `McpSkillSection` so the failure copy stays
/// consistent across the three apps.
class GithubSyncExperimentalCard extends StatefulWidget {
  const GithubSyncExperimentalCard({
    this.onLoadStatus,
    this.onListRepos,
    this.onConnect,
    this.onPushNow,
    this.onDisconnect,
    this.appId = '',
    super.key,
  });

  /// Originating app id (`editor` / `planner` / `portal`). Appended
  /// to the GitHub App install URL as `state=app_<appId>` so the
  /// backend `oauth_callback` can route the same-tab fallback back to
  /// the launching app instead of the historical editor default
  /// (0.1.128). Empty = no state appended (legacy behavior).
  final String appId;

  /// `GET /api/v1/integrations/github/status/`. Returns the raw
  /// payload (`connected`, `install_url`, `repo_full_name`, etc.).
  /// Null for signed-out users.
  final Future<Map<String, dynamic>> Function()? onLoadStatus;

  /// `GET /api/v1/integrations/github/repos/`. Returns the
  /// `repositories` list once an installation is wired.
  final Future<List<Map<String, dynamic>>> Function()? onListRepos;

  /// `POST /api/v1/integrations/github/callback/`. Persists
  /// installation id + chosen repo. The host calls this in two
  /// places: (a) right after the GitHub App install redirect with
  /// just `installation_id`; (b) when the user picks a repo from the
  /// dropdown, including `repo_full_name` and `repo_default_branch`.
  final Future<Map<String, dynamic>> Function({
    required String installationId,
    String? accountLogin,
    String? repoFullName,
    String? repoDefaultBranch,
  })? onConnect;

  /// `POST /api/v1/integrations/github/push/`. Returns the commit SHA
  /// or surfaces a `GithubSyncError` message via thrown exception.
  /// ``includeAssets`` opts into inlining avatar / cover / attachment
  /// bytes under ``assets/`` so the resulting clone is self-contained;
  /// subject to the per-file and per-push size caps documented in
  /// `creators.services.github_sync`.
  final Future<Map<String, dynamic>> Function({bool includeAssets})? onPushNow;

  /// `DELETE /api/v1/integrations/github/status/`. Drops the
  /// integration row; the GitHub App stays installed on the user's
  /// side until they uninstall it from their GitHub settings.
  final Future<void> Function()? onDisconnect;

  @override
  State<GithubSyncExperimentalCard> createState() =>
      _GithubSyncExperimentalCardState();
}

class _GithubSyncExperimentalCardState
    extends State<GithubSyncExperimentalCard> {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>>? _repos;
  String? _selectedRepo;
  bool _loading = true;
  bool _busy = false;
  bool _includeAssets = false;
  String? _lastCommitSha;

  // 0.1.120: pop-up install flow. The closer detaches the
  // postMessage listener and closes the orphaned popup window when
  // the widget unmounts, so a stale reply can't fire against a
  // disposed state. See `url_strategy_web.openPopupInstall` for
  // the rationale (avoids the same-tab redirect that was racing
  // a near-expiry Casdoor JWT and silently logging the user out).
  void Function()? _installPopupCloser;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _installPopupCloser?.call();
    _installPopupCloser = null;
    super.dispose();
  }

  bool get _hasCallbacks => widget.onLoadStatus != null;

  bool get _isConnected => _status?['connected'] == true;

  String get _installUrl => _status?['install_url']?.toString() ?? '';

  Future<void> _refreshStatus() async {
    if (widget.onLoadStatus == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final status = await widget.onLoadStatus!();
      if (!mounted) return;
      setState(() {
        _status = status;
        _selectedRepo = status['repo_full_name']?.toString();
        if (_selectedRepo != null && _selectedRepo!.isEmpty) {
          _selectedRepo = null;
        }
        _loading = false;
      });
      if (status['connected'] == true && widget.onListRepos != null) {
        try {
          final repos = await widget.onListRepos!();
          if (!mounted) return;
          setState(() => _repos = repos);
        } catch (_) {
          // Repo listing can fail if the install token can't be
          // refreshed (e.g. private key not yet provisioned). Leave
          // _repos null so the UI shows the error chip below.
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      _snackError(
        (l10n, cause) => l10n.githubSyncLoadStatusFailed(cause),
        error,
      );
    }
  }

  Future<void> _selectRepo(String? fullName) async {
    if (fullName == null || fullName.isEmpty) return;
    if (widget.onConnect == null) return;
    final installationId = _status?['installation_id']?.toString() ??
        // Fall back to whatever is on the row already; the callback
        // helper on the app side may keep the install id implicit.
        '';
    final defaultBranch = _repos
            ?.firstWhere(
              (r) => r['full_name']?.toString() == fullName,
              orElse: () => const {},
            )['default_branch']
            ?.toString() ??
        'main';
    setState(() => _busy = true);
    try {
      await widget.onConnect!(
        installationId: installationId,
        repoFullName: fullName,
        repoDefaultBranch: defaultBranch,
      );
      if (!mounted) return;
      setState(() => _selectedRepo = fullName);
      await _refreshStatus();
    } catch (error) {
      _snackError(
        (l10n, cause) => l10n.githubSyncSelectRepositoryFailed(cause),
        error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pushNow() async {
    if (widget.onPushNow == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.onPushNow!(includeAssets: _includeAssets);
      final sha = result['commit_sha']?.toString() ?? '';
      if (!mounted) return;
      setState(() => _lastCommitSha = sha);
      final shortSha = sha.substring(0, sha.length < 8 ? sha.length : 8);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).githubSyncPushed(shortSha)),
        ),
      );
      await _refreshStatus();
    } catch (error) {
      _snackError(
        (l10n, cause) => l10n.githubSyncPushFailed(cause),
        error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    if (widget.onDisconnect == null) return;
    setState(() => _busy = true);
    try {
      await widget.onDisconnect!();
      if (!mounted) return;
      setState(() {
        _status = {'connected': false};
        _repos = null;
        _selectedRepo = null;
        _lastCommitSha = null;
      });
    } catch (error) {
      _snackError(
        (l10n, cause) => l10n.githubSyncDisconnectFailed(cause),
        error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openInstallUrl() {
    var url = _installUrl;
    if (url.isEmpty) {
      _snackMessage(AppLocalizations.of(context).githubSyncInstallMissingUrl);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      _snackMessage(AppLocalizations.of(context).githubSyncInstallInvalidUrl);
      return;
    }
    // Carry the originating app through GitHub's state round-trip so
    // the backend's same-tab fallback redirect lands back here
    // instead of the editor default (see oauth_callback, 0.1.128).
    if (widget.appId.isNotEmpty) {
      url = uri.replace(queryParameters: {
        ...uri.queryParameters,
        'state': 'app_${widget.appId}',
      }).toString();
    }
    // 0.1.120: popup-based install. The pre-refactor full-page
    // redirect was costing the user their session — a long round
    // trip through GitHub's UI plus a near-expiry Casdoor JWT meant
    // the cold-booted SPA's first authenticated request hit 401 and
    // the auth-error interceptor signed the user out (the "GH link
    // logged me out, no logs on backend" bug). The popup keeps the
    // SPA loaded; the install-callback page postMessages the
    // install id back, we POST it to the backend straight from the
    // existing `_selectRepo` flow.
    _installPopupCloser?.call();
    _installPopupCloser = url_strategy.openPopupInstall(
      url: url,
      onInstallation: _handleInstallationCallback,
    );
  }

  /// Wire-up for the postMessage payload from the install popup. See
  /// `url_strategy_web.openPopupInstall` for the envelope shape; the
  /// only field we strictly need is `installation_id`.
  Future<void> _handleInstallationCallback(Map<String, String> params) async {
    if (!mounted) return;
    _installPopupCloser?.call();
    _installPopupCloser = null;
    final installationId = params['installation_id'] ?? '';
    if (installationId.isEmpty || widget.onConnect == null) {
      // Either the popup closed without an install (user cancelled)
      // or the host app isn't wired to accept callbacks. Either way
      // a status refresh is the right next step — if the install
      // really happened the backend already has it.
      await _refreshStatus();
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onConnect!(
        installationId: installationId,
        accountLogin: params['account_login'],
      );
      if (!mounted) return;
      await _refreshStatus();
    } catch (error) {
      _snackError(
        (l10n, cause) => l10n.githubSyncInstallCompleteFailed(cause),
        error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snackError(
    String Function(AppLocalizations l10n, String cause) messageFor,
    Object error,
  ) {
    final msg = error.toString().replaceFirst('Exception: ', '');
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    _snackMessage(messageFor(l10n, msg));
  }

  void _snackMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Widget _buildDisconnectedActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hasInstallUrl = _installUrl.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasInstallUrl)
          _DisabledHint(text: l10n.githubSyncInstallUrlMissingHelp)
        else ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _openInstallUrl,
            icon: const Icon(Icons.link, size: 18),
            label: Text(l10n.githubSyncInstall),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.githubSyncInstallHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConnectedActions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repos = _repos;
    final account = _status?['account_login']?.toString() ?? '';
    final lastPushAt = _status?['last_push_at']?.toString() ?? '';
    final lastError = _status?['last_error']?.toString() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                account.isEmpty
                    ? l10n.githubSyncInstalled
                    : l10n.githubSyncInstalledOn(account),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (repos == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (repos.isEmpty)
          _DisabledHint(
            text: l10n.githubSyncNoRepos,
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedRepo,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.githubSyncTargetRepo,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final repo in repos)
                DropdownMenuItem<String>(
                  value: repo['full_name']?.toString(),
                  child: Text(
                    repo['full_name']?.toString() ?? l10n.commonUnknown,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy ? null : _selectRepo,
          ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _includeAssets,
          onChanged:
              _busy ? null : (value) => setState(() => _includeAssets = value),
          title: Text(l10n.githubSyncIncludeAssets),
          subtitle: Text(
            _includeAssets
                ? l10n.githubSyncIncludeAssetsOn
                : l10n.githubSyncIncludeAssetsOff,
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            FilledButton.icon(
              onPressed: (_busy || _selectedRepo == null) ? null : _pushNow,
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_outlined, size: 18),
              label: Text(l10n.githubSyncPushNow),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: Text(l10n.githubSyncDisconnect),
            ),
          ],
        ),
        if (_lastCommitSha != null && _lastCommitSha!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            l10n.githubSyncLastPush(
              _lastCommitSha!.substring(
                0,
                _lastCommitSha!.length < 8 ? _lastCommitSha!.length : 8,
              ),
            ),
            style: theme.textTheme.bodySmall,
          ),
        ] else if (lastPushAt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            l10n.githubSyncLastPushAt(lastPushAt),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (lastError.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            lastError,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
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
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.githubSyncTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.githubSyncDescription,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (!_hasCallbacks)
              _DisabledHint(text: l10n.githubSyncSignIn)
            else if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else if (!_isConnected)
              _buildDisconnectedActions(context)
            else
              _buildConnectedActions(context),
          ],
        ),
      ),
    );
  }
}

class _DisabledHint extends StatelessWidget {
  const _DisabledHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}
