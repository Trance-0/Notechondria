import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'folder_messages.dart';
import 'local_folder_boot.dart';

// Routing by storage mode (modes and migration 2.8): in folder mode every
// request through the app client is answered in the page, whatever its
// host, except the one "Check for updates" handshake (rule 3).

/// An `http.Client` that answers some requests in the page.
/// `HttpClientInternalsMixin.send` asks it, so the startup budget applies
/// only to requests that go to the network (main 2.7).
abstract class LocalRoutingClient {
  bool routesLocally(String method, Uri uri);
}

const Symbol _versionCheckKey = #notechondriaCloudVersionCheck;

/// Runs [body] as the manual "Check for updates" of the status card (Q9).
/// Only a body-less `GET <apiBaseUrl>/handshake/` issued inside it may
/// leave the page; any other request made inside it is still answered in
/// the page (2.8 rule 3).
Future<T> runCloudVersionCheck<T>(
        String apiBaseUrl, Future<T> Function() body) =>
    runZoned(body,
        zoneValues: {_versionCheckKey: normalizeApiBaseUrl(apiBaseUrl)});

/// The saved API base of the running version check, or null outside one.
String? get currentCloudVersionCheckBase =>
    Zone.current[_versionCheckKey] as String?;

/// `<scheme>://<host>[:port]<prefix>/api/v1`, as the apps normalize it.
String normalizeApiBaseUrl(String raw) {
  var base = raw.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return base.endsWith('/api/v1') ? base : '$base/api/v1';
}

bool _isLoopbackHost(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

/// 2.8 rule 3: a GET with no body and no query, whose path ends with
/// `/api/v1/handshake/`, over https (or http to a loopback host), whose
/// scheme, host, port, and path prefix equal [savedApiBase].
bool isVersionCheckPassthrough(String method, Uri url,
    {required int bodyLength, required String? savedApiBase}) {
  if (savedApiBase == null || method.toUpperCase() != 'GET') return false;
  if (bodyLength != 0 || url.hasQuery || url.hasFragment) return false;
  if (url.userInfo.isNotEmpty) return false;
  const suffix = '/handshake/';
  if (!url.path.endsWith('/api/v1$suffix')) return false;
  final secure = url.scheme == 'https' ||
      (url.scheme == 'http' && _isLoopbackHost(url.host));
  if (!secure) return false;
  final saved = Uri.tryParse(savedApiBase);
  if (saved == null || saved.hasQuery || saved.userInfo.isNotEmpty) {
    return false;
  }
  final prefix = url.path.substring(0, url.path.length - suffix.length + 1);
  return saved.scheme == url.scheme &&
      saved.host == url.host &&
      saved.port == url.port &&
      '${saved.path}/' == prefix;
}

/// The app's `http.Client` (main 2.5): [StorageMode.browserOrCloud] goes to
/// the inner client unchanged; [StorageMode.folder] goes to [local], the
/// `LocalFolderTransport`, except the passthrough.
class StorageModeClient extends http.BaseClient implements LocalRoutingClient {
  StorageModeClient({
    required StorageMode Function() mode,
    required http.Client local,
    http.Client? inner,
  })  : _mode = mode,
        _local = local,
        _inner = inner ?? http.Client();

  final StorageMode Function() _mode;
  final http.Client _local;
  final http.Client _inner;

  bool get _folder => _mode() == StorageMode.folder;

  @override
  bool routesLocally(String method, Uri uri) =>
      _folder &&
      !isVersionCheckPassthrough(method, uri,
          bodyLength: 0, savedApiBase: currentCloudVersionCheckBase);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!_folder) return _inner.send(request);
    final bodyLength = request is http.Request
        ? request.bodyBytes.length
        : (request.contentLength ?? -1);
    if (isVersionCheckPassthrough(request.method, request.url,
        bodyLength: bodyLength, savedApiBase: currentCloudVersionCheckBase)) {
      // Rebuilt with only Accept: no Authorization, no other header.
      final bare = http.Request('GET', request.url)
        ..headers['Accept'] = 'application/json';
      return _inner.send(bare);
    }
    return _local.send(request);
  }

  @override
  void close() {
    _local.close();
    _inner.close();
  }
}

/// Result of [checkCloudVersion]; [message] is the 1.8 log line.
class CloudVersionCheck {
  const CloudVersionCheck({
    required this.ok,
    required this.message,
    this.version,
    this.minFrontendVersion,
  });

  final bool ok;
  final String message;
  final String? version;
  final String? minFrontendVersion;
}

/// "Check for updates" (Q9): one unauthenticated `GET /handshake/` to the
/// saved cloud URL through [client] (the app's `StorageModeClient`), read
/// only for `version` and `min_frontend_version`, with the 8 s handshake
/// bound of the apps.
Future<CloudVersionCheck> checkCloudVersion({
  required http.Client client,
  required String apiBaseUrl,
  Duration timeout = const Duration(seconds: 8),
}) {
  final base = normalizeApiBaseUrl(apiBaseUrl);
  final uri = Uri.parse('$base/handshake/');
  final host = '${uri.scheme}://${uri.authority}';
  CloudVersionCheck failed(String cause) => CloudVersionCheck(
      ok: false,
      message: scrubSessionSentinels(
          LocalFolderMessages.versionCheckFailed(host, cause)));
  return runCloudVersionCheck(base, () async {
    try {
      final response = await client
          .get(uri, headers: {'Accept': 'application/json'}).timeout(timeout);
      if (response.statusCode != 200) {
        return failed('HTTP ${response.statusCode}');
      }
      final body = jsonDecode(response.body);
      if (body is! Map) return failed('the answer is not a JSON object');
      final version = '${body['version'] ?? 'unknown'}';
      return CloudVersionCheck(
        ok: true,
        message: LocalFolderMessages.versionChecked(host, version),
        version: version,
        minFrontendVersion: body['min_frontend_version']?.toString(),
      );
    } on TimeoutException {
      return failed('no answer within ${timeout.inSeconds} s');
    } on FormatException {
      return failed('the answer is not JSON');
    } catch (error) {
      return failed('$error');
    }
  });
}
