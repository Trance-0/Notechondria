part of notechondria_frontend;

/// Displays the current MCP API key (prefix only) and the MCP endpoint URL,
/// and lets the user rotate the key. After rotation, the plaintext key is
/// shown ONCE with a copy button — the backend only stores a SHA-256 hash.
class _ApiKeySection extends StatefulWidget {
  const _ApiKeySection({
    required this.apiKeyPrefix,
    required this.apiBaseUrl,
    required this.onRotate,
  });

  final String apiKeyPrefix;
  final String apiBaseUrl;
  final Future<Map<String, dynamic>> Function()? onRotate;

  @override
  State<_ApiKeySection> createState() => _ApiKeySectionState();
}

class _ApiKeySectionState extends State<_ApiKeySection> {
  String _currentPrefix = '';
  String? _plaintextKey; // shown once after rotation
  bool _rotating = false;

  @override
  void initState() {
    super.initState();
    _currentPrefix = widget.apiKeyPrefix;
  }

  @override
  void didUpdateWidget(covariant _ApiKeySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKeyPrefix != widget.apiKeyPrefix && _plaintextKey == null) {
      setState(() => _currentPrefix = widget.apiKeyPrefix);
    }
  }

  /// Strip any `/api/...` suffix from [apiBaseUrl] so the MCP endpoint
  /// lives at `<origin>/mcp/`. Returns an empty string if the base URL is
  /// empty, so the helper text can hide itself cleanly.
  String _mcpEndpoint() {
    final base = widget.apiBaseUrl.trim();
    if (base.isEmpty) return '';
    try {
      final uri = Uri.parse(base);
      if (uri.scheme.isEmpty || uri.host.isEmpty) return '';
      final origin =
          '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      return '$origin/mcp/';
    } catch (_) {
      return '';
    }
  }

  Future<void> _rotate() async {
    if (widget.onRotate == null || _rotating) return;
    setState(() => _rotating = true);
    try {
      final result = await widget.onRotate!();
      final key = result['api_key']?.toString() ?? '';
      final prefix = result['api_key_prefix']?.toString() ?? '';
      if (!mounted) return;
      setState(() {
        _plaintextKey = key.isNotEmpty ? key : null;
        if (prefix.isNotEmpty) _currentPrefix = prefix;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to rotate API key: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  void _dismissPlaintext() {
    setState(() => _plaintextKey = null);
  }

  Future<void> _copyPlaintext() async {
    if (_plaintextKey == null) return;
    await Clipboard.setData(ClipboardData(text: _plaintextKey!));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API key copied to clipboard.')),
    );
  }

  Future<void> _copyMcpEndpoint() async {
    final endpoint = _mcpEndpoint();
    if (endpoint.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: endpoint));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('MCP endpoint copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onRotate == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final labelStyle =
        theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700);
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      color: theme.colorScheme.onSurface,
      fontSize: 13,
    );
    final displayPrefix = _currentPrefix.isNotEmpty
        ? '$_currentPrefix•••••••••••••••••••••••••'
        : '(no API key — click Rotate to generate one)';
    final mcpEndpoint = _mcpEndpoint();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('API key', style: labelStyle),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(displayPrefix, style: monoStyle),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _rotating ? null : _rotate,
              icon: _rotating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(
                _currentPrefix.isNotEmpty ? 'Rotate' : 'Generate',
              ),
            ),
          ],
        ),
        if (_plaintextKey != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Copy this key now — it will NOT be shown again:',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SelectableText(_plaintextKey!, style: monoStyle),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _copyPlaintext,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                    TextButton(
                      onPressed: _dismissPlaintext,
                      child: const Text('I have saved it'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Use this key with MCP clients (e.g. Claude Desktop) by setting the '
          'Authorization header to "Bearer ntc_<key>".',
          style: helperStyle,
        ),
        if (mcpEndpoint.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: helperStyle,
                    children: [
                      const TextSpan(text: 'MCP endpoint: '),
                      TextSpan(
                        text: mcpEndpoint,
                        style: monoStyle.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy MCP endpoint',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 16,
                icon: const Icon(Icons.copy),
                onPressed: _copyMcpEndpoint,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Shows linked Google/GitHub accounts with bind/unbind controls.
class _ConnectedAccountsSection extends StatefulWidget {
  const _ConnectedAccountsSection({
    this.onListSocialAccounts,
    this.onUnlinkSocialAccount,
    this.onBindGoogle,
    this.onBindGithub,
  });

  final Future<List<Map<String, dynamic>>> Function()? onListSocialAccounts;
  final Future<void> Function(String provider)? onUnlinkSocialAccount;
  final VoidCallback? onBindGoogle;
  final VoidCallback? onBindGithub;

  @override
  State<_ConnectedAccountsSection> createState() =>
      _ConnectedAccountsSectionState();
}

class _ConnectedAccountsSectionState extends State<_ConnectedAccountsSection> {
  List<Map<String, dynamic>>? _accounts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.onListSocialAccounts == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final accounts = await widget.onListSocialAccounts!();
      if (mounted) setState(() { _accounts = accounts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _accountFor(String provider) {
    return _accounts?.cast<Map<String, dynamic>?>().firstWhere(
      (a) => a?['provider'] == provider,
      orElse: () => null,
    );
  }

  Future<void> _unlink(String provider) async {
    if (widget.onUnlinkSocialAccount == null) return;
    try {
      await widget.onUnlinkSocialAccount!(provider);
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final hasAnyProvider = widget.onBindGoogle != null || widget.onBindGithub != null;
    if (!hasAnyProvider && widget.onListSocialAccounts == null) {
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
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else ...[
          _buildProviderRow(context, 'google', 'Google', Icons.g_mobiledata, widget.onBindGoogle),
          _buildProviderRow(context, 'github', 'GitHub', Icons.code, widget.onBindGithub),
        ],
      ],
    );
  }

  Widget _buildProviderRow(
    BuildContext context,
    String provider,
    String label,
    IconData icon,
    VoidCallback? onBind,
  ) {
    final account = _accountFor(provider);
    final linked = account != null;
    final email = account?['email']?.toString() ?? '';
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: linked
          ? Text(email.isNotEmpty ? email : 'Linked')
          : const Text('Not linked'),
      dense: true,
      trailing: linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onBind != null)
                  TextButton(onPressed: onBind, child: const Text('Switch')),
                TextButton(
                  onPressed: () => _unlink(provider),
                  child: Text('Unlink',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            )
          : onBind != null
              ? TextButton(onPressed: onBind, child: Text('Link $label'))
              : null,
    );
  }
}

/// Editable text area for the user's MCP `skill.md`. The contents are
/// surfaced to MCP-connected agents via the `instructions` field of the
/// JSON-RPC `initialize` response. Treat it as a personal prompt
/// playbook: import sources (e.g. notenextra.trance-0.com), preferred
/// note formats, target export platforms, and any other agent-facing
/// preferences.
class _McpSkillSection extends StatefulWidget {
  const _McpSkillSection({
    required this.initialContent,
    required this.onSave,
  });

  final String initialContent;
  final Future<ActionFeedback> Function(String skillMd) onSave;

  @override
  State<_McpSkillSection> createState() => _McpSkillSectionState();
}

class _McpSkillSectionState extends State<_McpSkillSection> {
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
  void didUpdateWidget(covariant _McpSkillSection old) {
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

