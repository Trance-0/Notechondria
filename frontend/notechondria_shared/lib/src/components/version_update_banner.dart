import 'dart:async';

import 'package:flutter/material.dart';

import '../app_shell/url_strategy.dart'
    if (dart.library.html) '../app_shell/url_strategy_web.dart' as url_strategy;
import '../l10n/app_localizations.dart';
import '../utils/version_status.dart';

/// Thin top-of-screen banner that tells the user when their running
/// build no longer matches the backend: a newer version has deployed
/// (refresh to update), a deploy is rolling out, or their build is below
/// the supported floor. Self-contained — it owns the periodic probe and
/// renders nothing while the client is current or the backend is
/// unreachable.
///
/// The host drops one of these at the top of its scaffold and supplies
/// [frontendVersion] (the build's `APP_VERSION`) plus a [probe] that
/// hits the handshake and returns the backend's version facts (or null
/// when offline).
class VersionUpdateBanner extends StatefulWidget {
  const VersionUpdateBanner({
    super.key,
    required this.frontendVersion,
    required this.probe,
    this.pollInterval = const Duration(minutes: 15),
    this.onRefresh,
  });

  final String frontendVersion;
  final Future<BackendVersionInfo?> Function() probe;
  final Duration pollInterval;

  /// Override the refresh action (defaults to a hard browser reload).
  /// Useful for tests.
  final VoidCallback? onRefresh;

  @override
  State<VersionUpdateBanner> createState() => _VersionUpdateBannerState();
}

class _VersionUpdateBannerState extends State<VersionUpdateBanner> {
  AppVersionStatus _status = AppVersionStatus.upToDate;
  AppVersionStatus? _dismissed;
  Timer? _timer;

  /// Remote (backend-reported) version from the last probe, shown next to
  /// the banner text so users can see exactly which build they are on and
  /// which one is available (e.g. "v0.1.181 → v0.1.183").
  String _remoteVersion = '';

  @override
  void initState() {
    super.initState();
    // First check after the first frame so a slow probe never blocks
    // paint; then poll on the interval.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(widget.pollInterval, (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    BackendVersionInfo? info;
    try {
      info = await widget.probe();
    } catch (_) {
      info = null;
    }
    if (!mounted) return;
    final remote = info?.version ?? '';
    final next = info == null
        ? AppVersionStatus.upToDate
        : computeVersionStatus(
            frontendVersion: widget.frontendVersion,
            backendVersion: info.version,
            minFrontendVersion: info.minFrontendVersion,
          );
    if (next != _status || remote != _remoteVersion) {
      setState(() {
        _remoteVersion = remote;
        _status = next;
        // A new, distinct status re-shows even if a prior one was
        // dismissed.
        if (_dismissed != null && _dismissed != next) _dismissed = null;
      });
    }
  }

  void _refresh() {
    if (widget.onRefresh != null) {
      widget.onRefresh!();
    } else {
      url_strategy.browserReload();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == AppVersionStatus.upToDate || _status == _dismissed) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isHard = _status == AppVersionStatus.unsupported;
    final isDeploying = _status == AppVersionStatus.deploying;

    final String message;
    switch (_status) {
      case AppVersionStatus.updateAvailable:
        message = l10n.versionUpdateAvailable;
        break;
      case AppVersionStatus.deploying:
        message = l10n.versionDeploying;
        break;
      case AppVersionStatus.unsupported:
        message = l10n.versionUnsupported;
        break;
      case AppVersionStatus.upToDate:
        return const SizedBox.shrink();
    }
    // Current → available build numbers, so the user knows exactly which
    // version they're on and which one the refresh delivers.
    final versionDetail = _remoteVersion.isEmpty
        ? ' (v${widget.frontendVersion})'
        : ' (v${widget.frontendVersion} → v$_remoteVersion)';

    final bg = isHard
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final fg = isHard
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isHard
                  ? Icons.warning_amber_outlined
                  : Icons.system_update_alt_outlined,
              color: fg,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message + versionDetail, style: TextStyle(color: fg)),
            ),
            // "Rolling out" needs no user action yet, but a refresh still
            // lets an impatient user re-check. Always offer Refresh.
            TextButton(
              onPressed: _refresh,
              style: TextButton.styleFrom(foregroundColor: fg),
              child: Text(l10n.versionRefresh),
            ),
            // The soft banners are dismissible; the unsupported one isn't.
            if (!isHard && !isDeploying)
              IconButton(
                onPressed: () => setState(() => _dismissed = _status),
                icon: Icon(Icons.close, size: 18, color: fg),
                tooltip: l10n.commonDismiss,
              ),
          ],
        ),
      ),
    );
  }
}
