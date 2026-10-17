import 'dart:async';

import '../components/debug_log.dart';
import 'startup_budget.dart';

/// Outcome line a startup step reports on success (see
/// `AppShellLogMixin.startupStep`): the level and the full AGENTS.md §1.8
/// message.
typedef StartupOutcome = ({DebugLogLevel level, String message});

/// Turns a failed request (or any startup step error) into a short,
/// specific cause for a §1.8 log line or message, so connection refused,
/// DNS failure, TLS failure, timeouts, and HTML-instead-of-JSON answers
/// stay distinguishable in the debug log (0.1.199; before, the HTTP layer
/// logged only `exc=ClientException`).
///
/// URL query strings are dropped and `Token` / `Bearer` credentials are
/// redacted, so the result is safe to log.
String describeRequestFailure(Object error) {
  if (error is BackendStartupTimeout) {
    final seconds = error.timeout.inSeconds;
    return error.skipped
        ? 'skipped: an earlier startup request timed out after ${seconds}s'
        : 'timeout after ${seconds}s (server did not respond)';
  }
  if (error is TimeoutException) {
    final seconds = error.duration?.inSeconds;
    return seconds == null
        ? 'timeout (server did not respond)'
        : 'timeout after ${seconds}s (server did not respond)';
  }
  final text = _redact(error.toString());
  final lower = text.toLowerCase();

  // The HTTP layer already described the cause; reuse it verbatim.
  final embedded = _embeddedCause.firstMatch(text);
  if (embedded != null) return embedded.group(1)!;

  final html = _htmlStatus.firstMatch(text);
  if (html != null || lower.contains('received html')) {
    return html == null
        ? 'HTML instead of JSON'
        : 'HTML instead of JSON (HTTP ${html.group(1)})';
  }
  final startupTimeout =
      BackendStartupTimeout.tryParse(text.replaceFirst('Exception: ', ''));
  if (startupTimeout != null) {
    return lower.contains('was skipped')
        ? 'skipped: an earlier startup request timed out after '
            '${startupTimeout.seconds}s'
        : 'timeout after ${startupTimeout.seconds}s (server did not respond)';
  }
  if (lower.contains('timed out') || lower.contains('timeoutexception')) {
    return 'timeout (server did not respond)';
  }
  if (lower.contains('connection refused') ||
      lower.contains('err_connection_refused')) {
    return 'connection refused';
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('name_not_resolved') ||
      lower.contains('no address associated') ||
      lower.contains('nodename nor servname')) {
    return 'DNS lookup failed';
  }
  if (lower.contains('handshakeexception') ||
      lower.contains('certificate_verify_failed') ||
      lower.contains('tls handshake') ||
      lower.contains('ssl handshake') ||
      lower.contains('err_ssl') ||
      lower.contains('err_cert')) {
    return 'TLS handshake failed';
  }
  if (lower.contains('connection reset') ||
      lower.contains('connection closed') ||
      lower.contains('connection terminated')) {
    return 'connection reset before a response';
  }
  if (lower.contains('xmlhttprequest error') ||
      lower.contains('failed to fetch') ||
      lower.contains('clientexception') ||
      lower.contains('networkerror')) {
    return 'network error with no readable response (browser hides the '
        'reason: connection refused, DNS failure, or a CORS/opaque '
        'response)';
  }

  var line = text.split('\n').first.trim();
  final plainException = line.startsWith('Exception: ');
  if (plainException) line = line.substring('Exception: '.length);
  if (line.length > 160) line = '${line.substring(0, 159)}\u2026';
  final type = error.runtimeType.toString();
  if (line.isEmpty) return type;
  // Release web builds minify type names (`minified:Au`), which only adds
  // noise in front of the message.
  return plainException || type.startsWith('minified:') ? line : '$type: $line';
}

final RegExp _embeddedCause =
    RegExp(r'before a response arrived \((.+)\)\.?\s*$');
final RegExp _htmlStatus =
    RegExp(r'(?:received|got) HTML[^(]*\(HTTP (\d{3})', caseSensitive: false);
final RegExp _queryString = RegExp(r'(https?://[^\s?#)]+)\?[^\s#)]*');
// Authorization header schemes as the HTTP layer writes them (capitalized),
// so ordinary prose such as "session token expired" is left alone.
final RegExp _credential = RegExp(r'\b(Token|Bearer)\s+[A-Za-z0-9._~+/=\-]+');

String _redact(String text) => text
    .replaceAllMapped(_queryString, (m) => m.group(1)!)
    .replaceAllMapped(_credential, (m) => '${m.group(1)} <redacted>');
