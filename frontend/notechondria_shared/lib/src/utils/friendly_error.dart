import '../l10n/app_localizations.dart';
import '../startup/startup_budget.dart';

/// Maps a raw error/exception string to a friendly, localized,
/// user-facing message. The frontend surfaces many failures by
/// stringifying the caught exception (e.g. a browser
/// `ClientException: Failed to fetch` when offline, a backend `500`, a
/// timeout). Those raw strings are fine in the debug log but read as
/// gibberish in the UI, so wrap them here before showing a SnackBar,
/// error bar, or banner.
///
/// Recognized classes get a localized AGENTS.md §1.8 sentence
/// (consequence, module/process, cause). The module/process is taken
/// from the raw message when it carries one (e.g. `Portal.HTTP/request`
/// from the HTTP layer, `Editor.Startup/bootstrap` from a startup
/// timeout); otherwise [source] is used. Anything unrecognized (typically
/// an already-human backend message like "Title is required") passes
/// through unchanged so we never hide a useful server message behind a
/// generic one.
String friendlyError(
  AppLocalizations l10n,
  Object? rawError, {
  String source = _kUnknownSource,
}) {
  final raw = (rawError?.toString() ?? '')
      .replaceFirst('Exception: ', '')
      .trim();
  if (raw.isEmpty) return l10n.errorNetwork(source);

  // A bounded startup request that timed out (or was skipped after one
  // did). Checked first: it is the "backend not responding" state.
  final startupTimeout = BackendStartupTimeout.tryParse(raw);
  if (startupTimeout != null) {
    return l10n.startupBackendTimeout(
      startupTimeout.source,
      startupTimeout.seconds,
    );
  }

  final lower = raw.toLowerCase();
  final origin = _moduleProcessIn(raw) ?? source;

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
    return l10n.errorNetwork(origin);
  }

  if (lower.contains('timeout') || lower.contains('timed out')) {
    return l10n.errorTimeout(origin);
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
    return l10n.errorServer(origin);
  }

  return raw;
}

/// Used when neither the raw message nor the caller names the
/// module/process that failed.
const String _kUnknownSource = 'Backend.HTTP/request';

/// Matches the `Module.Sub/process` token of a §1.8 message, e.g.
/// `Portal.HTTP/request` or `Backend.Auth/GET`. The module needs at least
/// one dot so URL path segments (`api/v1`) never match.
final RegExp _moduleProcessPattern =
    RegExp(r'\b([A-Z][A-Za-z]*(?:\.[A-Z][A-Za-z]*)+/[A-Za-z_][\w.]*)');

String? _moduleProcessIn(String raw) => _moduleProcessPattern
    .firstMatch(raw)
    ?.group(1)
    ?.replaceFirst(RegExp(r'\.+$'), '');
