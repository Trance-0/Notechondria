import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/friendly_error.dart';

/// The connection / load-error bar each app shell shows above its page
/// when the last data load failed: the backend is unreachable, timed out
/// at startup, or answered with an error. Renders [message] through
/// [friendlyError] (so the text keeps its AGENTS.md §1.8 shape and is
/// localized), plus Work offline (when [onWorkOffline] is set), Retry,
/// and Dismiss.
///
/// Shared since 0.1.198; editor, planner, and portal previously carried
/// identical hand-rolled copies.
class LoadErrorBanner extends StatelessWidget {
  const LoadErrorBanner({
    super.key,
    required this.message,
    required this.source,
    required this.onRetry,
    required this.onDismiss,
    this.onWorkOffline,
  });

  /// Raw error text (as stored in the shell's `_errorMessage`).
  final String message;

  /// Module/process used when [message] does not name its own, e.g.
  /// `Portal.Startup/initial_data`.
  final String source;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  /// Switches the app to offline mode. Null hides the action (already
  /// offline).
  final VoidCallback? onWorkOffline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.cloud_off_outlined,
                color: colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  friendlyError(l10n, message, source: source),
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
              if (onWorkOffline != null)
                TextButton(
                  onPressed: onWorkOffline,
                  child: Text(l10n.errorWorkOffline),
                ),
              TextButton(
                onPressed: onRetry,
                child: Text(l10n.commonRetry),
              ),
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close),
                tooltip: l10n.commonDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
