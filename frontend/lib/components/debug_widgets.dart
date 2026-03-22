part of notechondria_frontend;

/// Shows the latest captured API response details for debugging.
class _ApiDebugCard extends StatelessWidget {
  const _ApiDebugCard({
    required this.apiBaseUrl,
    required this.snapshotListenable,
  });

  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? snapshotListenable;

  @override
  Widget build(BuildContext context) {
    if (snapshotListenable == null) {
      return _ApiDebugSummary(apiBaseUrl: apiBaseUrl, snapshot: null);
    }
    return ValueListenableBuilder<ApiDebugSnapshot?>(
      valueListenable: snapshotListenable!,
      builder: (context, snapshot, child) {
        return _ApiDebugSummary(apiBaseUrl: apiBaseUrl, snapshot: snapshot);
      },
    );
  }
}

/// Renders a compact summary of the current API base URL and last response.
class _ApiDebugSummary extends StatelessWidget {
  const _ApiDebugSummary({
    required this.apiBaseUrl,
    required this.snapshot,
  });

  final String? apiBaseUrl;
  final ApiDebugSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('API base: ${apiBaseUrl ?? 'custom client'}',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            if (snapshot == null)
              const Text('No API response captured yet.')
            else ...[
              Text('${snapshot!.method} ${snapshot!.url}',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(
                'Status ${snapshot!.statusCode} | Content-Type: ${snapshot!.contentType.isEmpty ? 'unknown' : snapshot!.contentType}',
                style: theme.textTheme.bodySmall,
              ),
              if (snapshot!.note != null) ...[
                const SizedBox(height: 8),
                Text(
                  snapshot!.note!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: snapshot!.looksLikeHtml
                        ? theme.colorScheme.error
                        : theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SelectableText(
                snapshot!.bodyPreview.isEmpty
                    ? '(empty body)'
                    : snapshot!.bodyPreview,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
