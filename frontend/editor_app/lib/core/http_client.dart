part of notechondria_frontend;

/// Default HTTP implementation of the Notechondria REST client.
class HttpNotechondriaClient
    with HttpClientInternalsMixin
    implements NotechondriaClient {
  HttpNotechondriaClient({http.Client? httpClient, String? initialBaseUrl})
      : _httpClient = httpClient ?? http.Client(),
        _baseUrl = _normalizeBaseUrl(initialBaseUrl ?? _resolveBaseUrl());

  final http.Client _httpClient;
  String _baseUrl;
  @override
  final ValueNotifier<ApiDebugSnapshot?> debugSnapshot = ValueNotifier(null);
  @override
  final ValueNotifier<List<ApiDebugSnapshot>> debugHistory =
      ValueNotifier(const []);

  // HttpClientInternalsMixin wiring — read-only getters expose
  // private fields, plus the per-app log-tag prefix.
  @override
  http.Client get httpClient => _httpClient;
  @override
  void Function(DebugLogLevel level, String source, String message)?
      get logger => _logger;
  @override
  String get httpLogTagPrefix => 'Editor';

  /// Optional debug-log sink for per-request tracing. When set, every
  /// `send` call emits two DEBUG lines \u2014 one for the outbound
  /// request (method + path + body bytes) and one for the response
  /// (status + elapsed + body bytes) \u2014 which the app_shell then
  /// routes into the shared `DebugLogController`. `null` by default so
  /// the client stays self-contained for unit tests.
  void Function(DebugLogLevel level, String source, String message)? _logger;

  void setLogger(
    void Function(DebugLogLevel level, String source, String message) logger,
  ) {
    _logger = logger;
  }

  String get baseUrl => _baseUrl;

  /// Updates the client base URL while preserving `/api/v1` normalization.
  void updateBaseUrl(String raw) {
    _baseUrl = _normalizeBaseUrl(raw);
  }

  /// Probes a candidate backend URL with GET `<base>/handshake/` to confirm
  /// it's a Notechondria backend with a compatible API version. Callers
  /// should use this before persisting a user-entered API base URL in
  /// Settings, so a typo or a foreign server doesn't silently strand the
  /// user offline. Does NOT mutate `_baseUrl`.
  Future<HandshakeResult> verifyHandshake(String rawCandidateBaseUrl) async {
    final normalized = _normalizeBaseUrl(rawCandidateBaseUrl);
    final target = Uri.parse('$normalized/handshake/');
    try {
      final response = await _httpClient
          .get(target, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return HandshakeResult.failure(
          'Handshake got HTTP ${response.statusCode} from $target. '
          'Expected 200.',
        );
      }
      final dynamic parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic>) {
        return HandshakeResult.failure(
          'Handshake response was not JSON object. '
          'Is $target really a Notechondria backend?',
        );
      }
      final service = parsed['service']?.toString() ?? '';
      final apiVersion = parsed['api_version']?.toString() ?? '';
      if (service != 'notechondria-backend') {
        return HandshakeResult.failure(
          'Handshake service="$service" — expected "notechondria-backend". '
          'Refusing to switch to a non-Notechondria server.',
        );
      }
      if (apiVersion != 'v1') {
        return HandshakeResult.failure(
          'Backend api_version="$apiVersion" — this client only supports v1.',
        );
      }
      return HandshakeResult.success(
        service: service,
        apiVersion: apiVersion,
        version: parsed['version']?.toString() ?? 'unknown',
        capabilities: parsed['capabilities'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(parsed['capabilities'] as Map)
            : const <String, dynamic>{},
      );
    } on TimeoutException {
      return HandshakeResult.failure('Handshake timed out after 8s hitting $target.');
    } catch (error) {
      return HandshakeResult.failure('Handshake request failed: $error');
    }
  }

  static String _resolveBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    return _defaultApiBaseUrl();
  }

  static String _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('/api/v1')) {
      return value;
    }
    if (value.endsWith('/api')) {
      return '$value/v1';
    }
    return '$value/api/v1';
  }

  // Internal HTTP plumbing (`_uri`, `decode`, `send`, `_get`,
  // `_post`, `_patch`, `_delete`, `headers`, `shapedErrorMessage`,
  // `_stringifyErrors`, `_previewBody`, `_formatDecodeError`,
  // `_recordDebugSnapshot`) lives in
  // `core/http_client_internals.dart` as an extension on
  // `HttpNotechondriaClient` so this file stays closer to the
  // AGENTS.md \u00a71.5 1000-line cap.


  @override
  Future<Map<String, dynamic>> getFrontPage({String? token}) async {
    final uri = _uri('/front-page/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCourses({String? token}) async {
    final uri = _uri('/courses/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createCourse(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/courses/');
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateCourse(
    String token,
    int courseId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/courses/$courseId/');
    final response = await _patch(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<void> deleteCourse(String token, int courseId) async {
    final uri = _uri('/courses/$courseId/');
    final response = await _delete(uri, token: token);
    await decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<List<Map<String, dynamic>>> reorderCourses(
    String token,
    List<int> courseIds,
  ) async {
    final uri = _uri('/courses/reorder/');
    final response = await _post(
      uri,
      token: token,
      payload: {'course_ids': courseIds},
    );
    final data =
        await decode(response, uri: uri, method: 'POST') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getCourseDetail(int courseId,
      {String? token}) async {
    final uri = _uri('/courses/$courseId/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId,
      {String? token}) async {
    final uri = _uri('/courses/$courseId/notes/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getNoteDetail(int noteId, {String? token}) async {
    final uri = _uri('/notes/$noteId/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> getNoteByUuid(String uuid, {String? token}) async {
    final uri = _uri('/notes/uuid/$uuid/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> listNotes({
    String? token,
    String query = '',
    int offset = 0,
    int limit = 20,
    int? courseId,
    String scope = 'personal',
  }) async {
    final uri = _uri('/notes/').replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        'scope': scope,
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (courseId != null) 'course_id': '$courseId',
      },
    );
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> createNote(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/notes/');
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<void> deleteNote(String token, int noteId) async {
    final uri = _uri('/notes/$noteId/');
    final response = await _delete(uri, token: token);
    await decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<List<Map<String, dynamic>>> getDeletedNotes(String token) async {
    final uri = _uri('/notes/deleted/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> restoreDeletedNote(String token, int noteId) async {
    final uri = _uri('/notes/$noteId/restore/');
    final response = await _post(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> emptyDeletedNotes(String token) async {
    final uri = _uri('/notes/deleted/empty/');
    final response = await _delete(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'DELETE'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateNote(
    String token,
    int noteId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/notes/$noteId/');
    final response = await _patch(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getNoteHistory(
    String token,
    int noteId,
  ) async {
    final uri = _uri('/notes/$noteId/history/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> snapshotNote(
    String token,
    int noteId, {
    String reason = 'manual',
  }) async {
    final uri = _uri('/notes/$noteId/snapshot/');
    final response = await _post(
      uri,
      token: token,
      payload: {'reason': reason},
    );
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> restoreNoteVersion(
    String token,
    int noteId,
    int versionId,
  ) async {
    final uri = _uri('/notes/$noteId/restore/$versionId/');
    final response = await _post(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getActivity({String? token}) async {
    final uri = _uri('/activity/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getActivityWeek(
    String token, {
    String? startDate,
  }) async {
    final uri = _uri('/activity/week/').replace(
      queryParameters: {
        if (startDate != null && startDate.isNotEmpty) 'start_date': startDate,
      },
    );
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCalendarFeeds(String token) async {
    final uri = _uri('/calendar-feeds/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createCalendarFeed(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/calendar-feeds/');
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateCalendarFeed(
    String token,
    int feedId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/calendar-feeds/$feedId/');
    final response = await _patch(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<void> deleteCalendarFeed(String token, int feedId) async {
    final uri = _uri('/calendar-feeds/$feedId/');
    final response = await _delete(uri, token: token);
    await decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<Map<String, dynamic>> startNoteSession(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/note-sessions/');
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateNoteSession(
    String token,
    int sessionId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/note-sessions/$sessionId/');
    final response = await _patch(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<Map<String, dynamic>> subscribeCourse(String token, int courseId) async {
    final uri = _uri('/courses/$courseId/subscribe/');
    final response = await _post(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> unsubscribeCourse(
      String token, int courseId) async {
    final uri = _uri('/courses/$courseId/subscribe/');
    final response = await _delete(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'DELETE'),
    );
  }

  @override
  Future<Map<String, dynamic>> openCourse(String token, int courseId) async {
    final uri = _uri('/courses/$courseId/open/');
    final response = await _post(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> restoreTemplateCourses(String token) async {
    final uri = _uri('/admin/template-courses/restore/');
    final response = await _post(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = _uri('/auth/login/');
    final response = await _post(
      uri,
      payload: {'email': email, 'password': password},
    );
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> getCasdoorConfig() async {
    final uri = _uri('/auth/casdoor/config/');
    final response = await _get(uri);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> casdoorExchange(
    String code, {
    String state = '',
  }) async {
    final uri = _uri('/auth/casdoor/exchange/');
    final payload = <String, dynamic>{'code': code};
    if (state.isNotEmpty) payload['state'] = state;
    final response = await _post(uri, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> casdoorBind(String token, String code) async {
    final uri = _uri('/auth/casdoor/bind/');
    final response = await _post(uri, token: token, payload: {'code': code});
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> casdoorLinkBind({
    required String nonce,
    required String identifier,
    required String password,
  }) async {
    final uri = _uri('/auth/casdoor/link/bind/');
    final response = await _post(uri, payload: {
      'nonce': nonce,
      'username': identifier,
      'password': password,
    });
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> casdoorLinkCreate({
    required String nonce,
    required String password,
  }) async {
    final uri = _uri('/auth/casdoor/link/create/');
    final response = await _post(uri, payload: {
      'nonce': nonce,
      'password': password,
    });
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<void> casdoorUnlink(String token) async {
    final uri = _uri('/auth/casdoor/unlink/');
    final response = await _delete(uri, token: token);
    await decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<Map<String, dynamic>> checkSession(String token) async {
    final uri = _uri('/auth/session/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> rotateApiKey(String token) async {
    final uri = _uri('/auth/rotate-api-key/');
    final response = await send(
      'POST',
      uri,
      () => _httpClient.post(uri, headers: headers(token: token)),
    );
    return Map<String, dynamic>.from(await decode(response, uri: uri, method: 'POST'));
  }

  @override
  Future<Map<String, dynamic>> githubSyncStatus(String token) async {
    final uri = _uri('/integrations/github/status/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> githubSyncRepos(String token) async {
    final uri = _uri('/integrations/github/repos/');
    final response = await _get(uri, token: token);
    final body = await decode(response, uri: uri, method: 'GET');
    if (body is Map && body['repositories'] is List) {
      return [
        for (final r in body['repositories'] as List)
          Map<String, dynamic>.from(r as Map),
      ];
    }
    return const [];
  }

  @override
  Future<Map<String, dynamic>> githubSyncCallback(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/integrations/github/callback/');
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> githubSyncPush(
    String token, {
    bool includeAssets = false,
  }) async {
    final uri = _uri('/integrations/github/push/');
    final response = await _post(
      uri,
      token: token,
      payload: {'include_assets': includeAssets},
    );
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<void> githubSyncDisconnect(String token) async {
    final uri = _uri('/integrations/github/status/');
    final response = await _delete(uri, token: token);
    await decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<void> logout(String token) async {
    final uri = _uri('/auth/logout/');
    final response = await send(
      'POST',
      uri,
      () => _httpClient.post(uri, headers: headers(token: token)),
    );
    await decode(response, uri: uri, method: 'POST');
  }

  @override
  Future<Map<String, dynamic>> getSettings(String token) async {
    final uri = _uri('/settings/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/settings/');
    final response = await _patch(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'PATCH'),
    );
  }


  @override
  Future<Map<String, dynamic>> uploadAvatar(String token, XFile file) async {
    final uri = _uri('/settings/');
    final request = http.MultipartRequest('PATCH', uri)
      ..headers.addAll(headers(token: token))
      ..files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    final streamed = await send('PATCH', uri, () => request.send().then(http.Response.fromStream));
    return Map<String, dynamic>.from(
      await decode(streamed, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listNoteAttachments(
    String token,
    int noteId,
  ) async {
    final uri = _uri('/notes/$noteId/attachments/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> uploadNoteAttachment(
    String token,
    int noteId,
    XFile file,
  ) async {
    final uri = _uri('/notes/$noteId/attachments/');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers(token: token))
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    final streamed = await send(
        'POST', uri, () => request.send().then(http.Response.fromStream));
    return Map<String, dynamic>.from(
      await decode(streamed, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<void> deleteNoteAttachment(
    String token,
    int noteId,
    int attachmentId,
  ) async {
    final uri = _uri('/notes/$noteId/attachments/$attachmentId/');
    final response = await send(
      'DELETE',
      uri,
      () => _httpClient.delete(uri, headers: headers(token: token)),
    );
    await decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<List<Map<String, dynamic>>> listNoteAttachmentsByUuid(
    String token,
    String noteUuid,
  ) async {
    final uri = _uri('/notes/uuid/$noteUuid/attachments/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> uploadNoteAttachmentByUuid(
    String token,
    String noteUuid,
    XFile file,
  ) async {
    final uri = _uri('/notes/uuid/$noteUuid/attachments/');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers(token: token))
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    final streamed = await send(
        'POST', uri, () => request.send().then(http.Response.fromStream));
    return Map<String, dynamic>.from(
      await decode(streamed, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<void> deleteNoteAttachmentByUuid(
    String token,
    String noteUuid,
    int attachmentId,
  ) async {
    final uri = _uri('/notes/uuid/$noteUuid/attachments/$attachmentId/');
    final response = await send(
      'DELETE',
      uri,
      () => _httpClient.delete(uri, headers: headers(token: token)),
    );
    await decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<Map<String, dynamic>> uploadNoteCoverImage(
    String token,
    int noteId,
    XFile file,
  ) async {
    final uri = _uri('/notes/$noteId/cover/');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers(token: token))
      ..files.add(
        http.MultipartFile.fromBytes(
          'cover',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    final streamed = await send(
        'POST', uri, () => request.send().then(http.Response.fromStream));
    return Map<String, dynamic>.from(
      await decode(streamed, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> deleteNoteCoverImage(
    String token,
    int noteId,
  ) async {
    final uri = _uri('/notes/$noteId/cover/');
    final response = await send(
      'DELETE',
      uri,
      () => _httpClient.delete(uri, headers: headers(token: token)),
    );
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'DELETE'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getPlannerEvents(String token) async {
    final uri = _uri('/planner-events/');
    final response = await _get(uri, token: token);
    final data =
        await decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createPlannerEvent(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/planner-events/');
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> updatePlannerEvent(
    String token,
    int eventId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/planner-events/$eventId/');
    final response = await _patch(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'PATCH'),
    );
  }
}
