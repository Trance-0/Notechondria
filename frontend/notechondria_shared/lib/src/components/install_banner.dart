import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/web_install_env.dart'
    if (dart.library.html) '../utils/web_install_env_web.dart';

/// Shows a one-time, dismissible `MaterialBanner` nudging mobile-web
/// users to add the app to their Home Screen — the supported install
/// channel and the only durable-storage path on iOS (Safari's ITP
/// evicts a plain bookmark's script-writable storage after ~7 days of
/// inactivity; a home-screen install is exempt). See
/// `docs/readme.md` "Installing on a phone".
///
/// Renders nothing (returns false) unless ALL hold:
/// - running in a mobile browser tab (not native, not an installed
///   PWA) — [isMobileWebBrowser];
/// - the user has not dismissed it before ([dismissed]).
///
/// Copy adapts to risk: a signed-out user with local-only drafts
/// ([hasLocalDrafts]) gets a data-durability warning; everyone else
/// gets a gentle install tip. [onDismiss] persists the one-time flag
/// (host writes it to local stats); the banner does not reappear once
/// dismissed.
bool maybeShowInstallBanner(
  BuildContext context, {
  required bool dismissed,
  required bool isSignedIn,
  required bool hasLocalDrafts,
  required Future<void> Function() onDismiss,
}) {
  if (dismissed || !isMobileWebBrowser()) return false;

  final messenger = ScaffoldMessenger.of(context);
  final atRisk = !isSignedIn && hasLocalDrafts;
  final theme = Theme.of(context);
  final l10n = AppLocalizations.of(context);

  Future<void> dismiss() async {
    messenger.hideCurrentMaterialBanner();
    await onDismiss();
  }

  messenger.showMaterialBanner(
    MaterialBanner(
      leading: Icon(
        atRisk ? Icons.warning_amber_outlined : Icons.add_to_home_screen,
        color: atRisk ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
      content: Text(
        atRisk ? l10n.installBannerAtRisk : l10n.installBannerTip,
      ),
      actions: [
        TextButton(
          onPressed: dismiss,
          child: Text(l10n.commonGotIt),
        ),
      ],
    ),
  );
  return true;
}
