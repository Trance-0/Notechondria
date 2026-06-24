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
    if (oldWidget.apiKeyPrefix != widget.apiKeyPrefix &&
        _plaintextKey == null) {
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

/// Shows the Casdoor SSO link with bind/unlink controls. Per-provider
/// Google / GitHub rows were retired in favor of Casdoor's own
/// provider proxy (configure them on the Casdoor application's
/// Providers tab).
class _ConnectedAccountsSection extends StatefulWidget {
  const _ConnectedAccountsSection({
    this.onBindCasdoor,
    this.onUnlinkCasdoor,
    this.casdoorLinked = false,
    this.casdoorOrgLoginUrl,
  });

  /// Triggers `launchOAuth('casdoor', intent: 'bind')`. Null when
  /// the backend reports Casdoor is in shadow mode.
  final VoidCallback? onBindCasdoor;

  /// Calls `DELETE /api/v1/auth/casdoor/unlink/`. Null when the
  /// backend is in shadow mode (nothing to unlink).
  final Future<void> Function()? onUnlinkCasdoor;

  /// Mirrors `Settings.casdoor_linked` on the server. Drives the
  /// "Linked" / "Not linked" subtitle on the Casdoor row without an
  /// extra round-trip.
  final bool casdoorLinked;

  /// Org-themed Casdoor login page URL (e.g.
  /// `https://auth.trance-0.com/login/trance-0`). Built from env
  /// vars (`CASDOOR_ENDPOINT`, `CASDOOR_ORG_NAME`) by the backend's
  /// `/api/v1/auth/casdoor/config/` endpoint and threaded through
  /// the OAuth probe — no client-side hard-coding. Empty / null
  /// when the backend is in shadow mode; the manage-account button
  /// hides itself in that state.
  final String? casdoorOrgLoginUrl;

  @override
  State<_ConnectedAccountsSection> createState() =>
      _ConnectedAccountsSectionState();
}

class _ConnectedAccountsSectionState extends State<_ConnectedAccountsSection> {
  @override
  Widget build(BuildContext context) {
    if (widget.onBindCasdoor == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final manageUrl = widget.casdoorOrgLoginUrl ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.connectedAccountsTitle,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _buildCasdoorRow(context),
        if (manageUrl.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => url_strategy.browserRedirect(manageUrl),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(l10n.connectedAccountsManageCasdoor),
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          // 0.1.119: surface a clear escalation path when SSO is
          // unreachable. The probe at boot logs a warning under
          // `Editor.Auth/casdoor.config.probe`, but most users
          // won't read the debug log — they'll see a sign-in
          // failure and not know who to contact.
          l10n.connectedAccountsUnavailableHelp,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildCasdoorRow(BuildContext context) {
    final linked = widget.casdoorLinked;
    return ListTile(
      leading: const Icon(Icons.shield_outlined),
      title: const Text('Casdoor SSO'),
      subtitle: Text(linked ? 'Linked' : 'Not linked'),
      dense: true,
      trailing: linked
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onBindCasdoor != null)
                  TextButton(
                    onPressed: widget.onBindCasdoor,
                    child: const Text('Switch'),
                  ),
                TextButton(
                  onPressed: widget.onUnlinkCasdoor == null
                      ? null
                      : () async {
                          try {
                            await widget.onUnlinkCasdoor!();
                          } catch (_) {}
                          if (mounted) setState(() {});
                        },
                  child: Text(
                    'Unlink',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            )
          : TextButton(
              onPressed: widget.onBindCasdoor,
              child: const Text('Link Casdoor'),
            ),
    );
  }
}

// _McpSkillSection moved to notechondria_shared/lib/src/components/
// mcp_skill_section.dart so editor / planner / portal share one UI.
