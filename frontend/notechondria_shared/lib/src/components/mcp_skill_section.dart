import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shell/url_strategy.dart'
    if (dart.library.html) '../app_shell/url_strategy_web.dart'
    as url_strategy;
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
      const SnackBar(content: Text('skill.md copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dirty = _controller.text != _lastSaved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Agent skill (skill.md)',
          style: theme.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Personal playbook for MCP-connected agents. Use this to '
          'describe where to pull notes from (e.g. external sites like '
          'notenextra.trance-0.com), how to format imports, which files '
          'to export, and where to publish them. Sent verbatim as the '
          '`instructions` field of the MCP initialize response.',
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
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
            hintText:
                '# Import\n- Pull notes from notenextra.trance-0.com once a day...\n\n'
                '# Export\n- Mirror to GitHub Gist as YAML+markdown.\n\n'
                '# Format\n- Wrap math in \$...\$. Tag deadlines with \\#deadline.',
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
              label: const Text('Save'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _controller.text.isEmpty ? null : _copy,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy'),
            ),
            const Spacer(),
            if (dirty)
              Text(
                'unsaved changes',
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
    super.key,
  });

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

  @override
  void initState() {
    super.initState();
    _refreshStatus();
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
      _snackError('Cannot load GitHub Sync status', error);
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
      _snackError('Cannot select repository', error);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pushed to GitHub (sha ${sha.substring(0, sha.length < 8 ? sha.length : 8)}).')),
      );
      await _refreshStatus();
    } catch (error) {
      _snackError('GitHub Sync push failed', error);
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
      _snackError('Cannot disconnect GitHub Sync', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openInstallUrl() {
    final url = _installUrl;
    if (url.isEmpty) {
      _snackError(
        'Cannot install GitHub App',
        Exception('Frontend.GithubSync/install — no install_url configured.'),
      );
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      _snackError(
        'Cannot install GitHub App',
        Exception('Frontend.GithubSync/install — install_url is not a valid http(s) URL.'),
      );
      return;
    }
    // Same-tab redirect: GitHub returns the user back via the
    // configured callback URL after the install completes.
    url_strategy.browserRedirect(url);
  }

  void _snackError(String prefix, Object error) {
    final msg = error.toString().replaceFirst('Exception: ', '');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$prefix: $msg')),
    );
  }

  Widget _buildDisconnectedActions(BuildContext context) {
    final theme = Theme.of(context);
    final hasInstallUrl = _installUrl.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasInstallUrl)
          const _DisabledHint(
            text: 'Operator note: GITHUB_DATA_SYNC_APP_INSTALL_URL '
                'is not configured on this backend. See '
                'docs/integrations/github-sync.md for the env-var '
                'contract.',
          )
        else ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _openInstallUrl,
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Install Notechondria GitHub App'),
          ),
          const SizedBox(height: 6),
          Text(
            'After approving the install, GitHub redirects back here '
            'and we persist your installation id automatically. The '
            'app stays installed until you remove it from your GitHub '
            'settings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConnectedActions(BuildContext context) {
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
                    ? 'GitHub App installed.'
                    : 'GitHub App installed on @$account.',
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
          const _DisabledHint(
            text: 'No repositories visible to this installation. '
                'Open GitHub settings → Applications → Notechondria '
                'data sync, and grant access to a repo.',
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedRepo,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sync target repository',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final repo in repos)
                DropdownMenuItem<String>(
                  value: repo['full_name']?.toString(),
                  child: Text(
                    repo['full_name']?.toString() ?? 'unknown',
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
          onChanged: _busy
              ? null
              : (value) => setState(() => _includeAssets = value),
          title: const Text('Include assets'),
          subtitle: Text(
            _includeAssets
                ? 'Avatar, cover images, and attachments are inlined '
                    'under assets/. Subject to per-file (50 MB) and '
                    'per-push (200 MB) caps.'
                : 'Static assets stay referenced by URL only. Faster '
                    'push, but a fresh server can\'t recover the bytes.',
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
              label: const Text('Push now'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Disconnect'),
            ),
          ],
        ),
        if (_lastCommitSha != null && _lastCommitSha!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Last push: ${_lastCommitSha!.substring(0, _lastCommitSha!.length < 8 ? _lastCommitSha!.length : 8)}',
            style: theme.textTheme.bodySmall,
          ),
        ] else if (lastPushAt.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Last push at $lastPushAt.',
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
                  'Experimental — GitHub Sync',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Push your full account (profile, settings, MCP skill, '
              'courses, notes, custom meta, planner events) to a '
              'GitHub repo you own so you can recover everything if '
              'our server is wiped. Static assets we host (avatars, '
              'attachments, cover images) are referenced by URL, not '
              'committed. See docs/integrations/github-sync.md for '
              'the full flow.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (!_hasCallbacks)
              const _DisabledHint(
                  text: 'Sign in to enable GitHub Sync.')
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
