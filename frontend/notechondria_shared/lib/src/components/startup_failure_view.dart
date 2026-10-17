import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'copyable_feedback.dart';

/// Full-page fallback shown when an app cannot finish starting (a startup
/// step threw, or an uncaught error hit before the first frame). Replaces
/// what would otherwise be a blank or half-initialized screen with the
/// AGENTS.md §1.8 message, a Retry action, and, when [onContinue] is set,
/// a way into the app with whatever data is already on the device (so
/// Settings > Local data stays reachable when the local cache itself is
/// what broke startup).
class StartupFailureView extends StatelessWidget {
  const StartupFailureView({
    super.key,
    required this.source,
    required this.cause,
    required this.onRetry,
    this.onContinue,
  });

  /// Module/process that failed, e.g. `Portal.Startup/bootstrap`.
  final String source;

  /// Triggering condition, typically the caught error's message.
  final String cause;
  final VoidCallback onRetry;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                    semanticLabel: l10n.startupFailureTitle,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.startupFailureTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  SelectableMessageText(
                    l10n.startupFailureMessage(source, cause),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: onRetry,
                        child: Text(l10n.commonRetry),
                      ),
                      CopyMessageButton(
                        message: l10n.startupFailureMessage(source, cause),
                      ),
                      if (onContinue != null)
                        OutlinedButton(
                          onPressed: onContinue,
                          child: Text(l10n.startupContinueAnyway),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
