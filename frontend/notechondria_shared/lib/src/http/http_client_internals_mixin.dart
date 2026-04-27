import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../components/debug_log.dart';
import '../models/api_debug_snapshot.dart';

/// Internal HTTP plumbing for each app's `HttpNotechondriaClient`.
/// Owns the four headline helpers from `docs/TODO.md` plus their
/// internal-only dependencies — all byte-identical across editor /
/// planner / portal before this refactor (modulo the log-tag
/// prefix in `_send`).
///
/// What this mixin owns:
///   - `send(method, uri, operation, {requestBytes})` — the request
///     wrapper that emits a DEBUG line on dispatch, an INFO/WARNING
///     line on response (depending on status), and a snapshot on
///     failure. Logs prefixed with `httpLogTagPrefix` so editor
///     emits `Editor.HTTP/...`, planner `Planner.HTTP/...`, etc.
///   - `decode(response, {uri, method})` — JSON decode with
///     HTML-detection, debug-snapshot recording, and 4xx/5xx →
///     `Exception(shapedErrorMessage(...))` reshape.
///   - `headers({token, includeJsonContentType})` — Authorization
///     + Accept + optional Content-Type header builder.
///   - `shapedErrorMessage({...})` — wraps 401/403 errors in the
///     AGENTS.md §1.7 shape so no bare backend error reaches the
///     UI.
///
/// What stays per-app (in `core/http_client_internals.dart`):
///   - `_uri(path)` — small URL constructor, depends on private
///     `_baseUrl` field. Keeping this per-app avoids exposing
///     `_baseUrl` as a getter on every host class.
///   - `_get` / `_post` / `_patch` / `_delete` — verb wrappers
///     that internally call `send(...)` from this mixin. The
///     wrapper bodies are tiny but used at hundreds of call
///     sites; renaming them would churn 600+ lines repo-wide for
///     marginal dedup. Deferred.
///
/// Usage in `HttpNotechondriaClient`:
/// ```dart
/// class HttpNotechondriaClient
///     with HttpClientInternalsMixin
///     implements NotechondriaClient {
///   final http.Client _httpClient;
///   String _baseUrl;
///   void Function(DebugLogLevel, String, String)? _logger;
///
///   @override
///   http.Client get httpClient => _httpClient;
///   @override
///   void Function(DebugLogLevel, String, String)? get logger => _logger;
///   @override
///   String get httpLogTagPrefix => 'Editor';
///   // debugSnapshot + debugHistory are already public ValueNotifier
///   // fields on the class — no override needed.
/// }
/// ```
mixin HttpClientInternalsMixin {
  /// The shared `http.Client` instance the host uses for outbound
  /// requests. Exposed via getter so the mixin can be on a class
  /// that holds the field privately.
  http.Client get httpClient;

  /// Optional debug-log sink. When non-null, `send` emits one
  /// DEBUG line on request dispatch and one INFO/WARNING line on
  /// response (level depends on status code).
  void Function(DebugLogLevel level, String source, String message)?
      get logger;

  /// Latest API call snapshot. Updated on every `decode` and on
  /// `send` failure. Each app's `HttpNotechondriaClient` exposes
  /// this as a `final ValueNotifier<ApiDebugSnapshot?>` field
  /// already, so no override is needed for this getter.
  ValueNotifier<ApiDebugSnapshot?> get debugSnapshot;

  /// 32-deep ring of past API call snapshots. Same per-app
  /// public-field pattern as `debugSnapshot`.
  ValueNotifier<List<ApiDebugSnapshot>> get debugHistory;

  /// Per-app log-tag prefix: `'Editor'` / `'Planner'` / `'Portal'`.
  /// Drives the `Editor.HTTP/request` / `Planner.HTTP/response`
  /// / `Portal.HTTP/request_failed` source tags emitted by `send`.
  String get httpLogTagPrefix;

  /// Wraps a backend call so its dispatch + response are logged at
  /// debug level and a debug-snapshot is recorded on failure.
  /// Used as `send('GET', uri, () => httpClient.get(uri, ...))`.
  /// `requestBytes` is shown in the dispatch line for POST/PATCH
  /// payloads so the debug terminal surfaces request size at a
  /// glance.
  Future<http.Response> send(
    String method,
    Uri uri,
    Future<http.Response> Function() operation, {
    int requestBytes = 0,
  }) async {
    final tag = httpLogTagPrefix;
    final started = DateTime.now();
    logger?.call(
      DebugLogLevel.debug,
      '$tag.HTTP/request',
      'HTTP request sent: $tag.HTTP/request — '
          '$method ${uri.path}'
          '${requestBytes > 0 ? " (${requestBytes}B payload)" : ""}.',
    );
    try {
      final response = await operation();
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      logger?.call(
        _levelForStatus(response.statusCode),
        '$tag.HTTP/response',
        'HTTP response received: $tag.HTTP/response — '
            '$method ${uri.path} → ${response.statusCode} '
            '(${elapsedMs}ms, ${response.bodyBytes.length}B).',
      );
      return response;
    } catch (error) {
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      logger?.call(
        DebugLogLevel.warning,
        '$tag.HTTP/request_failed',
        'HTTP request failed: $tag.HTTP/request_failed — '
            '$method ${uri.path} (${elapsedMs}ms, exc=${error.runtimeType}).',
      );
      _recordDebugSnapshot(ApiDebugSnapshot(
        recordedAt: DateTime.now(),
        method: method,
        url: uri.toString(),
        statusCode: 0,
        contentType: '',
        bodyPreview: error.toString(),
        looksLikeHtml: false,
        note: 'Request failed before a response was received.',
      ));
      throw Exception('Client failed to fetch, uri=$uri');
    }
  }

  /// Decode a JSON response with HTML-detection. On success,
  /// records a debug snapshot and returns the parsed body. On 4xx
  /// or 5xx, throws `Exception(shapedErrorMessage(...))`. On
  /// non-JSON bodies (often an HTML proxy error page), records a
  /// snapshot with `looksLikeHtml: true` and throws an Exception
  /// with a hint about API_BASE_URL.
  ///
  /// Empty 2xx bodies (e.g. 204 No Content) decode to `{}` so
  /// callers don't have to special-case them.
  Future<dynamic> decode(
    http.Response response, {
    required Uri uri,
    required String method,
  }) async {
    final body = response.body;
    final contentType = response.headers['content-type'] ?? '';
    final trimmed = body.trimLeft();
    final looksLikeHtml = trimmed.startsWith('<!DOCTYPE') ||
        trimmed.startsWith('<html') ||
        trimmed.startsWith('<');
    if (response.body.isEmpty) {
      if (response.statusCode >= 400) {
        throw Exception('Request failed with ${response.statusCode}');
      }
      return {};
    }
    dynamic data;
    try {
      data = jsonDecode(body);
    } on FormatException {
      _recordDebugSnapshot(ApiDebugSnapshot(
        recordedAt: DateTime.now(),
        method: method,
        url: uri.toString(),
        statusCode: response.statusCode,
        contentType: contentType,
        bodyPreview: _previewBody(body),
        looksLikeHtml: looksLikeHtml,
        note: looksLikeHtml
            ? 'The response body looks like HTML, not JSON.'
            : 'The response body is not valid JSON.',
      ));
      throw Exception(_formatDecodeError(uri, response, looksLikeHtml));
    }
    _recordDebugSnapshot(ApiDebugSnapshot(
      recordedAt: DateTime.now(),
      method: method,
      url: uri.toString(),
      statusCode: response.statusCode,
      contentType: contentType,
      bodyPreview: _previewBody(body),
      looksLikeHtml: looksLikeHtml,
    ));
    if (response.statusCode >= 400) {
      throw Exception(shapedErrorMessage(
        statusCode: response.statusCode,
        uri: uri,
        method: method,
        data: data,
      ));
    }
    return data;
  }

  /// Build the standard request headers: always `Accept:
  /// application/json`; optionally `Content-Type: application/json`
  /// (set true for POST/PATCH/PUT bodies); `Authorization: Token
  /// <token>` when token is non-null and non-empty.
  Map<String, String> headers({
    String? token,
    bool includeJsonContentType = false,
  }) {
    final out = {'Accept': 'application/json'};
    if (includeJsonContentType) {
      out['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      out['Authorization'] = 'Token $token';
    }
    return out;
  }

  /// Wraps a backend error response in the AGENTS.md §1.7 shape so
  /// no bare `"Invalid token."` / `"Authentication credentials were
  /// not provided."` ever reaches the UI. Callers already catch the
  /// `Exception` `decode` produces; this only affects the
  /// stringified body.
  ///
  /// * 401 → `"Session rejected: Backend.Auth/<method> <path> — <cause>."`
  /// * 403 → `"Request forbidden: Backend.Auth/<method> <path> — <cause>."`
  /// * Other 4xx/5xx → legacy `_stringifyErrors` body, unchanged.
  ///
  /// Backend-side §1.7 messages contain an em-dash already; those
  /// land verbatim and aren't double-wrapped.
  String shapedErrorMessage({
    required int statusCode,
    required Uri uri,
    required String method,
    required dynamic data,
  }) {
    final raw = _stringifyErrors(data);
    if (raw.contains('—')) return raw;
    final path = uri.path;
    if (statusCode == 401) {
      return 'Session rejected: Backend.Auth/$method $path — $raw';
    }
    if (statusCode == 403) {
      return 'Request forbidden: Backend.Auth/$method $path — $raw';
    }
    return raw;
  }

  // ---- internal-only helpers ------------------------------------
  // Underscored => library-private to `notechondria_shared`, so
  // they're not exposed on the host `HttpNotechondriaClient` and
  // can't be called from per-app code. Internal use by the four
  // public methods above only.

  String _stringifyErrors(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (data['detail'] != null) {
        return data['detail'].toString();
      }
      return data.entries.map((entry) {
        final value = entry.value;
        if (value is List) {
          return '${entry.key}: ${value.join(", ")}';
        }
        return '${entry.key}: $value';
      }).join('\n');
    }
    return data.toString();
  }

  String _previewBody(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 240) return compact;
    return '${compact.substring(0, 240)}...';
  }

  String _formatDecodeError(
    Uri uri,
    http.Response response,
    bool looksLikeHtml,
  ) {
    final target = '${response.request?.method ?? 'REQUEST'} ${uri.toString()}';
    if (looksLikeHtml) {
      return 'Expected JSON from $target but received HTML. '
          'Check API_BASE_URL and backend routing.';
    }
    return 'Expected JSON from $target but received an invalid response.';
  }

  void _recordDebugSnapshot(ApiDebugSnapshot snapshot) {
    debugSnapshot.value = snapshot;
    final next = [snapshot, ...debugHistory.value];
    if (next.length > 32) {
      next.removeRange(32, next.length);
    }
    debugHistory.value = List<ApiDebugSnapshot>.unmodifiable(next);
  }
}

/// DEBUG for 2xx/3xx (happy path), INFO for 4xx (client error,
/// expected traffic like a 401 before login), WARNING for 5xx.
/// Top-level free function rather than a static mixin method so
/// it doesn't pollute the host's static surface — every concrete
/// `HttpNotechondriaClient` subclass would otherwise gain a
/// matching static method via mixin, which is just noise.
DebugLogLevel _levelForStatus(int status) {
  if (status >= 500) return DebugLogLevel.warning;
  if (status >= 400) return DebugLogLevel.info;
  return DebugLogLevel.debug;
}
