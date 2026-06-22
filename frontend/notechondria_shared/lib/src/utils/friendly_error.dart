import '../l10n/app_localizations.dart';

/// Maps a raw error/exception string to a friendly, localized,
/// user-facing message. The frontend surfaces many failures by
/// stringifying the caught exception (e.g. a browser
/// `ClientException: Failed to fetch` when offline, a backend `500`, a
/// timeout). Those raw strings are fine in the debug log but read as
/// gibberish in the UI, so wrap them here before showing a SnackBar,
/// error bar, or banner.
///
/// Recognized classes get a clean localized sentence; anything
/// unrecognized (typically an already-human backend message like
/// "Title is required") passes through unchanged so we never hide a
/// useful server message behind a generic one.
String friendlyError(AppLocalizations l10n, Object? rawError) {
  final raw = (rawError?.toString() ?? '')
      .replaceFirst('Exception: ', '')
      .trim();
  if (raw.isEmpty) return l10n.errorNetwork;
  final lower = raw.toLowerCase();

  // Network unreachable: the browser's fetch failure, dart:io socket
  // errors, and connection resets all mean "we couldn't talk to the
  // server".
  const networkMarkers = [
    'failed to fetch',
    'clientexception',
    'socketexception',
    'network is unreachable',
    'connection refused',
    'connection closed',
    'connection reset',
    'connection terminated',
    'xmlhttprequest',
    'err_connection',
    'err_internet',
    'err_name_not_resolved',
  ];
  if (networkMarkers.any(lower.contains)) {
    return l10n.errorNetwork;
  }

  if (lower.contains('timeout') || lower.contains('timed out')) {
    return l10n.errorTimeout;
  }

  // A 5xx-shaped backend failure.
  if (lower.contains('http 5') ||
      lower.contains(' 500 ') ||
      lower.contains('500:') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('internal server error') ||
      lower.contains('bad gateway') ||
      lower.contains('service unavailable')) {
    return l10n.errorServer;
  }

  return raw;
}
