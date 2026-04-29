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
  String? _plaintextKey;
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
        : '(no API key — click Generate to create one)';
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

/// Wrapper section that groups the API key display, password change,
/// and email change controls under a "Security" heading.
class _SecuritySection extends StatelessWidget {
  const _SecuritySection({
    required this.apiKeyPrefix,
    required this.apiBaseUrl,
    required this.onRotateApiKey,
    required this.onSendIdentityCode,
    required this.onChangePassword,
    required this.onChangeEmailRequest,
    required this.onChangeEmailConfirm,
    required this.onOpenChangePassword,
    required this.onOpenChangeEmail,
  });

  final String apiKeyPrefix;
  final String apiBaseUrl;
  final Future<Map<String, dynamic>> Function()? onRotateApiKey;
  final Future<Map<String, dynamic>> Function()? onSendIdentityCode;
  final Future<Map<String, dynamic>> Function(
    String currentPassword,
    String newPassword,
    String identityCode,
  )? onChangePassword;
  final Future<Map<String, dynamic>> Function(
    String newEmail,
    String identityCode,
  )? onChangeEmailRequest;
  final Future<Map<String, dynamic>> Function(
    String newEmail,
    String code,
  )? onChangeEmailConfirm;
  final VoidCallback onOpenChangePassword;
  final VoidCallback onOpenChangeEmail;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Security',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _ApiKeySection(
              apiKeyPrefix: apiKeyPrefix,
              apiBaseUrl: apiBaseUrl,
              onRotate: onRotateApiKey,
            ),
            if (onSendIdentityCode != null) ...[
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change password'),
                subtitle: const Text('Identity-code verified two-step flow.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenChangePassword,
                dense: true,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined),
                title: const Text('Change email'),
                trailing: const Icon(Icons.chevron_right),
                onTap: onOpenChangeEmail,
                dense: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
