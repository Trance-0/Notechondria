import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/api_debug_snapshot.dart';
import 'debug_widgets.dart';

/// Shared full-page error surface with retry and API diagnostics.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
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
            ApiDebugSummary(
              apiBaseUrl: apiBaseUrl,
              snapshot: debugSnapshot,
              history: const [],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: Text(AppLocalizations.of(context).commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}
