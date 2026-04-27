part of notechondria_frontend;

/// Per-app HTTP plumbing for `HttpNotechondriaClient`.
///
/// Most of this file's prior contents — `_send`, `_decode`,
/// `_headers`, `_shapedErrorMessage` plus their internal helpers
/// (`_stringifyErrors`, `_previewBody`, `_formatDecodeError`,
/// `_recordDebugSnapshot`, `_levelForStatus`) — moved into the
/// shared `HttpClientInternalsMixin` (notechondria_shared 0.1.81).
/// Call sites use `send` / `decode` / `headers` / `shapedErrorMessage`
/// (no leading underscore) on the same `HttpNotechondriaClient`
/// instance.
///
/// What stays per-app:
///   - `_uri(path)` — needs the private `_baseUrl` field, which
///     varies per app instance and stays inside the host class.
///   - `_get` / `_post` / `_patch` / `_delete` — verb wrappers
///     called at hundreds of sites in `http_client.dart`. They
///     internally call `send(...)` from the shared mixin. Renaming
///     them would churn 600+ call sites repo-wide for marginal
///     dedup; deferred.
extension HttpNotechondriaClientInternalsX on HttpNotechondriaClient {
  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalizedPath');
  }

  Future<http.Response> _get(Uri uri, {String? token}) {
    return send(
      'GET',
      uri,
      () => _httpClient.get(uri, headers: headers(token: token)),
    );
  }

  Future<http.Response> _post(
    Uri uri, {
    String? token,
    Map<String, dynamic>? payload,
  }) {
    final body = jsonEncode(payload ?? const {});
    return send(
      'POST',
      uri,
      () => _httpClient.post(
        uri,
        headers: headers(token: token, includeJsonContentType: true),
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
    return send(
      'PATCH',
      uri,
      () => _httpClient.patch(
        uri,
        headers: headers(token: token, includeJsonContentType: true),
        body: body,
      ),
      requestBytes: body.length,
    );
  }

  Future<http.Response> _delete(Uri uri, {String? token}) {
    return send(
      'DELETE',
      uri,
      () => _httpClient.delete(uri, headers: headers(token: token)),
    );
  }
}
