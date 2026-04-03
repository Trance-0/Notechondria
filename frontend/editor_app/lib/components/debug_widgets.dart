part of notechondria_frontend;

/// Shows the latest captured API response details for debugging.
class _ApiDebugCard extends StatelessWidget {
  const _ApiDebugCard({
    required this.apiBaseUrl,
    required this.snapshotListenable,
    this.historyListenable,
  });

  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? snapshotListenable;
  final ValueListenable<List<ApiDebugSnapshot>>? historyListenable;

  @override
  Widget build(BuildContext context) {
    if (snapshotListenable == null) {
      return _ApiDebugSummary(
        apiBaseUrl: apiBaseUrl,
        snapshot: null,
        history: const [],
      );
    }
    final history = historyListenable;
    if (history == null) {
      return ValueListenableBuilder<ApiDebugSnapshot?>(
        valueListenable: snapshotListenable!,
        builder: (context, snapshot, child) {
          return _ApiDebugSummary(
            apiBaseUrl: apiBaseUrl,
            snapshot: snapshot,
            history: const [],
          );
        },
      );
    }
    return ValueListenableBuilder<List<ApiDebugSnapshot>>(
      valueListenable: history,
      builder: (context, entries, child) {
        return ValueListenableBuilder<ApiDebugSnapshot?>(
          valueListenable: snapshotListenable!,
          builder: (context, snapshot, child) {
            return _ApiDebugSummary(
              apiBaseUrl: apiBaseUrl,
              snapshot: snapshot,
              history: entries,
            );
          },
        );
      },
    );
  }
}

/// Renders a compact summary of the current API base URL and last response.
class _ApiDebugSummary extends StatelessWidget {
  const _ApiDebugSummary({
    required this.apiBaseUrl,
    required this.snapshot,
    required this.history,
  });

  final String? apiBaseUrl;
  final ApiDebugSnapshot? snapshot;
  final List<ApiDebugSnapshot> history;

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
              Text(
                'Last response at ${_formatCompactTimestamp(snapshot!.recordedAt.toIso8601String())}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
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
            if (history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Recent API requests',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 160,
                child: ListView(
                  children: [
                    for (final entry in history.take(8))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: SelectableText(
                          '[${entry.recordedAt.toIso8601String()}] ${entry.method} ${entry.url} -> ${entry.statusCode == 0 ? 'failed' : entry.statusCode}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
