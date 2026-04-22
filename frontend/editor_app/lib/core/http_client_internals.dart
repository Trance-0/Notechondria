part of notechondria_frontend;

/// Internal HTTP plumbing for `HttpNotechondriaClient`:
///   * URL construction (`_uri`)
///   * response decode + shaped-error wrapping (`_decode`,
///     `_shapedErrorMessage`, `_stringifyErrors`, `_previewBody`,
///     `_formatDecodeError`)
///   * request wrapper (`_send`) with debug logging
///   * verb helpers (`_get`, `_post`, `_patch`, `_delete`)
///   * auth / JSON header builder (`_headers`)
///   * debug snapshot ring (`_recordDebugSnapshot`)
/// None of these are part of the `NotechondriaClient` interface (all
/// `_`-prefixed so they're library-private), so they move cleanly into
/// an extension. Extracted from `http_client.dart` so that file stays
/// closer to the AGENTS.md §1.5 1000-line ceiling.
extension HttpNotechondriaClientInternalsX on HttpNotechondriaClient {
  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

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
    if (compact.length <= 240) {
      return compact;
    }
    return '${compact.substring(0, 240)}...';
  }

  String _formatDecodeError(
    Uri uri,
    http.Response response,
    bool looksLikeHtml,
  ) {
    final target = '${response.request?.method ?? 'REQUEST'} ${uri.toString()}';
    if (looksLikeHtml) {
      return 'Expected JSON from $target but received HTML. Check API_BASE_URL and backend routing.';
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

  Future<dynamic> _decode(
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
      throw Exception(_shapedErrorMessage(
        statusCode: response.statusCode,
        uri: uri,
        method: method,
        data: data,
      ));
    }
    return data;
  }

  /// Wraps a backend error response in the AGENTS.md \u00a71.7 shape so no
  /// bare `"Invalid token."` / `"Authentication credentials were not
  /// provided."` ever reaches the UI. Callers already catch the
  /// `Exception` this produces; the reshape only affects the
  /// stringified body.
  ///
  /// * 401 \u2192 `"Session rejected: Backend.Auth/<method> <path> \u2014 <cause>."`
  /// * 403 \u2192 `"Request forbidden: Backend.Auth/<method> <path> \u2014 <cause>."`
  /// * Other 4xx/5xx \u2192 legacy `_stringifyErrors` body, unchanged.
  String _shapedErrorMessage({
    required int statusCode,
    required Uri uri,
    required String method,
    required dynamic data,
  }) {
    final raw = _stringifyErrors(data);
    // Already shaped? Don't double-wrap; backend-side \u00a71.7 messages land
    // verbatim and shouldn't be wrapped again.
    if (raw.contains('\u2014')) {
      return raw;
    }
    final path = uri.path;
    if (statusCode == 401) {
      return 'Session rejected: Backend.Auth/$method $path \u2014 $raw';
    }
    if (statusCode == 403) {
      return 'Request forbidden: Backend.Auth/$method $path \u2014 $raw';
    }
    return raw;
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Future<http.Response> Function() operation, {
    int requestBytes = 0,
  }) async {
    final started = DateTime.now();
    _logger?.call(
      DebugLogLevel.debug,
      'Editor.HTTP/request',
      'HTTP request sent: Editor.HTTP/request \u2014 '
          '$method ${uri.path}'
          '${requestBytes > 0 ? " (${requestBytes}B payload)" : ""}.',
    );
    try {
      final response = await operation();
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      _logger?.call(
        _levelForStatus(response.statusCode),
        'Editor.HTTP/response',
        'HTTP response received: Editor.HTTP/response \u2014 '
            '$method ${uri.path} \u2192 ${response.statusCode} '
            '(${elapsedMs}ms, ${response.bodyBytes.length}B).',
      );
      return response;
    } catch (error) {
      final elapsedMs = DateTime.now().difference(started).inMilliseconds;
      _logger?.call(
        DebugLogLevel.warning,
        'Editor.HTTP/request_failed',
        'HTTP request failed: Editor.HTTP/request_failed \u2014 '
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

  /// DEBUG for 2xx/3xx (happy path), INFO for 4xx (client error, still
  /// expected traffic like a 401 before login), WARNING for 5xx.
  static DebugLogLevel _levelForStatus(int status) {
    if (status >= 500) return DebugLogLevel.warning;
    if (status >= 400) return DebugLogLevel.info;
    return DebugLogLevel.debug;
  }

  Map<String, String> _headers({
    String? token,
    bool includeJsonContentType = false,
  }) {
    final headers = {'Accept': 'application/json'};
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Token $token';
    }
    return headers;
  }

  Future<http.Response> _get(Uri uri, {String? token}) {
    return _send(
      'GET',
      uri,
      () => _httpClient.get(uri, headers: _headers(token: token)),
    );
  }

  Future<http.Response> _post(
    Uri uri, {
    String? token,
    Map<String, dynamic>? payload,
  }) {
    final body = jsonEncode(payload ?? const {});
    return _send(
      'POST',
      uri,
      () => _httpClient.post(
        uri,
        headers: _headers(token: token, includeJsonContentType: true),
        body: body,
      ),
      requestBytes: body.length,
    );
  }

  Future<http.Response> _patch(
    Uri uri, {
    String? token,
    required Map<String, dynamic> payload,
  }) {
    final body = jsonEncode(payload);
    return _send(
      'PATCH',
      uri,
      () => _httpClient.patch(
        uri,
        headers: _headers(token: token, includeJsonContentType: true),
        body: body,
      ),
      requestBytes: body.length,
    );
  }

  Future<http.Response> _delete(Uri uri, {String? token}) {
    return _send(
      'DELETE',
      uri,
      () => _httpClient.delete(uri, headers: _headers(token: token)),
    );
  }
}
