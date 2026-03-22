part of notechondria_frontend;

/// Shared full-page error surface with retry and API diagnostics.
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
    this.apiBaseUrl,
    this.debugSnapshot,
  });

  final String message;
  final Future<void> Function() onRetry;
  final String? apiBaseUrl;
  final ApiDebugSnapshot? debugSnapshot;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            _ApiDebugSummary(
              apiBaseUrl: apiBaseUrl,
              snapshot: debugSnapshot,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
