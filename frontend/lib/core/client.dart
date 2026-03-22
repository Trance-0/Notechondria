part of notechondria_frontend;

/// Reports user-facing success or failure feedback for an async action.
class ActionFeedback {
  const ActionFeedback({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}

/// Captures the last API response shape for frontend debugging surfaces.
class ApiDebugSnapshot {
  const ApiDebugSnapshot({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.contentType,
    required this.bodyPreview,
    required this.looksLikeHtml,
    this.note,
  });

  final String method;
  final String url;
  final int statusCode;
  final String contentType;
  final String bodyPreview;
  final bool looksLikeHtml;
  final String? note;
}

/// Defines the frontend contract for all Notechondria REST operations.
abstract class NotechondriaClient {
  Future<Map<String, dynamic>> getFrontPage({String? token});
  Future<List<Map<String, dynamic>>> getCourses({String? token});
  Future<Map<String, dynamic>> getCourseDetail(int courseId, {String? token});
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId, {String? token});
  Future<Map<String, dynamic>> getNoteDetail(int noteId, {String? token});
  Future<Map<String, dynamic>> listNotes({
    String? token,
    String query = '',
    int offset = 0,
    int limit = 20,
  });
  Future<Map<String, dynamic>> createNote(
    String token,
    Map<String, dynamic> payload,
  );
  Future<void> deleteNote(String token, int noteId);
  Future<List<Map<String, dynamic>>> getDeletedNotes(String token);
  Future<Map<String, dynamic>> restoreDeletedNote(String token, int noteId);
  Future<Map<String, dynamic>> emptyDeletedNotes(String token);
  Future<Map<String, dynamic>> updateNote(
    String token,
    int noteId,
    Map<String, dynamic> payload,
  );
  Future<List<Map<String, dynamic>>> getNoteHistory(String token, int noteId);
  Future<Map<String, dynamic>> snapshotNote(
    String token,
    int noteId, {
    String reason = 'manual',
  });
  Future<Map<String, dynamic>> restoreNoteVersion(
    String token,
    int noteId,
    int versionId,
  );
  Future<List<Map<String, dynamic>>> getActivity({String? token});
  Future<Map<String, dynamic>> getActivityWeek(
    String token, {
    String? startDate,
  });
  Future<List<Map<String, dynamic>>> getCalendarFeeds(String token);
  Future<Map<String, dynamic>> createCalendarFeed(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> updateCalendarFeed(
    String token,
    int feedId,
    Map<String, dynamic> payload,
  );
  Future<void> deleteCalendarFeed(String token, int feedId);
  Future<Map<String, dynamic>> startNoteSession(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> updateNoteSession(
    String token,
    int sessionId,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> subscribeCourse(String token, int courseId);
  Future<Map<String, dynamic>> unsubscribeCourse(String token, int courseId);
  Future<Map<String, dynamic>> openCourse(String token, int courseId);
  Future<Map<String, dynamic>> register(String email, String password);
  Future<Map<String, dynamic>> verifyEmail(String email, String code);
  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> requestPasswordReset(String email);
  Future<Map<String, dynamic>> confirmPasswordReset(
    String email,
    String code,
    String password,
  );
  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> uploadAvatar(String token, XFile file);
  Future<List<Map<String, dynamic>>> getPlannerEvents(String token);
  Future<Map<String, dynamic>> createPlannerEvent(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> updatePlannerEvent(
    String token,
    int eventId,
    Map<String, dynamic> payload,
  );
}

/// Default HTTP implementation of the Notechondria REST client.
class HttpNotechondriaClient implements NotechondriaClient {
  HttpNotechondriaClient({http.Client? httpClient, String? initialBaseUrl})
      : _httpClient = httpClient ?? http.Client(),
        _baseUrl = _normalizeBaseUrl(initialBaseUrl ?? _resolveBaseUrl());

  final http.Client _httpClient;
  String _baseUrl;
  final ValueNotifier<ApiDebugSnapshot?> debugSnapshot = ValueNotifier(null);

  String get baseUrl => _baseUrl;

  /// Updates the client base URL while preserving `/api/v1` normalization.
  void updateBaseUrl(String raw) {
    _baseUrl = _normalizeBaseUrl(raw);
  }

  static String _resolveBaseUrl() {
    const configured = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }
    if (kIsWeb && Uri.base.scheme.startsWith('http')) {
      final isLocalHost =
          Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1';
      if (!isLocalHost) {
        return Uri.base.origin;
      }
    }
    return 'http://localhost:9080';
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
      debugSnapshot.value = ApiDebugSnapshot(
        method: method,
        url: uri.toString(),
        statusCode: response.statusCode,
        contentType: contentType,
        bodyPreview: _previewBody(body),
        looksLikeHtml: looksLikeHtml,
        note: looksLikeHtml
            ? 'The response body looks like HTML, not JSON.'
            : 'The response body is not valid JSON.',
      );
      throw Exception(_formatDecodeError(uri, response, looksLikeHtml));
    }
    debugSnapshot.value = ApiDebugSnapshot(
      method: method,
      url: uri.toString(),
      statusCode: response.statusCode,
      contentType: contentType,
      bodyPreview: _previewBody(body),
      looksLikeHtml: looksLikeHtml,
    );
    if (response.statusCode >= 400) {
      throw Exception(_stringifyErrors(data));
    }
    return data;
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

  @override
  Future<Map<String, dynamic>> getFrontPage({String? token}) async {
    final uri = _uri('/front-page/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCourses({String? token}) async {
    final uri = _uri('/courses/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    final data =
        await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getCourseDetail(int courseId,
      {String? token}) async {
    final uri = _uri('/courses/$courseId/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId,
      {String? token}) async {
    final uri = _uri('/courses/$courseId/notes/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    final data =
        await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> getNoteDetail(int noteId, {String? token}) async {
    final uri = _uri('/notes/$noteId/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> listNotes({
    String? token,
    String query = '',
    int offset = 0,
    int limit = 20,
  }) async {
    final uri = _uri('/notes/').replace(
      queryParameters: {
        'limit': '$limit',
        'offset': '$offset',
        if (query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> createNote(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/notes/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<void> deleteNote(String token, int noteId) async {
    final uri = _uri('/notes/$noteId/');
    final response =
        await _httpClient.delete(uri, headers: _headers(token: token));
    await _decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<List<Map<String, dynamic>>> getDeletedNotes(String token) async {
    final uri = _uri('/notes/deleted/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    final data =
        await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> restoreDeletedNote(String token, int noteId) async {
    final uri = _uri('/notes/$noteId/restore/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode({}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> emptyDeletedNotes(String token) async {
    final uri = _uri('/notes/deleted/empty/');
    final response =
        await _httpClient.delete(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'DELETE'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateNote(
    String token,
    int noteId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/notes/$noteId/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getNoteHistory(
    String token,
    int noteId,
  ) async {
    final uri = _uri('/notes/$noteId/history/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    final data =
        await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> snapshotNote(
    String token,
    int noteId, {
    String reason = 'manual',
  }) async {
    final uri = _uri('/notes/$noteId/snapshot/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode({'reason': reason}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> restoreNoteVersion(
    String token,
    int noteId,
    int versionId,
  ) async {
    final uri = _uri('/notes/$noteId/restore/$versionId/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode({}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getActivity({String? token}) async {
    final uri = _uri('/activity/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    final data =
        await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
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
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getCalendarFeeds(String token) async {
    final uri = _uri('/calendar-feeds/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    final data =
        await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createCalendarFeed(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/calendar-feeds/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateCalendarFeed(
    String token,
    int feedId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/calendar-feeds/$feedId/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<void> deleteCalendarFeed(String token, int feedId) async {
    final uri = _uri('/calendar-feeds/$feedId/');
    final response =
        await _httpClient.delete(uri, headers: _headers(token: token));
    await _decode(response, uri: uri, method: 'DELETE');
  }

  @override
  Future<Map<String, dynamic>> startNoteSession(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/note-sessions/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateNoteSession(
    String token,
    int sessionId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/note-sessions/$sessionId/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<Map<String, dynamic>> subscribeCourse(String token, int courseId) async {
    final uri = _uri('/courses/$courseId/subscribe/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode({}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> unsubscribeCourse(
      String token, int courseId) async {
    final uri = _uri('/courses/$courseId/subscribe/');
    final response =
        await _httpClient.delete(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'DELETE'),
    );
  }

  @override
  Future<Map<String, dynamic>> openCourse(String token, int courseId) async {
    final uri = _uri('/courses/$courseId/open/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode({}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> register(String email, String password) async {
    final uri = _uri('/auth/register/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final uri = _uri('/auth/verify-email/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'code': code}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = _uri('/auth/login/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final uri = _uri('/auth/password-reset/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) async {
    final uri = _uri('/auth/password-reset/confirm/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(includeJsonContentType: true),
      body: jsonEncode({'email': email, 'code': code, 'password': password}),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<void> logout(String token) async {
    final uri = _uri('/auth/logout/');
    final response =
        await _httpClient.post(uri, headers: _headers(token: token));
    await _decode(response, uri: uri, method: 'POST');
  }

  @override
  Future<Map<String, dynamic>> getSettings(String token) async {
    final uri = _uri('/settings/');
    final response =
        await _httpClient.get(uri, headers: _headers(token: token));
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/settings/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<Map<String, dynamic>> uploadAvatar(String token, XFile file) async {
    final uri = _uri('/settings/');
    final request = http.MultipartRequest('PATCH', uri)
      ..headers.addAll(_headers(token: token))
      ..files.add(
        http.MultipartFile.fromBytes(
          'avatar',
          await file.readAsBytes(),
          filename: file.name,
        ),
      );
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'PATCH'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getPlannerEvents(String token) async {
    final uri = _uri('/planner-events/');
    final response = await _httpClient.get(
      uri,
      headers: _headers(token: token),
    );
    final data =
        await _decode(response, uri: uri, method: 'GET') as List<dynamic>;
    return data.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<Map<String, dynamic>> createPlannerEvent(
    String token,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/planner-events/');
    final response = await _httpClient.post(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> updatePlannerEvent(
    String token,
    int eventId,
    Map<String, dynamic> payload,
  ) async {
    final uri = _uri('/planner-events/$eventId/');
    final response = await _httpClient.patch(
      uri,
      headers: _headers(token: token, includeJsonContentType: true),
      body: jsonEncode(payload),
    );
    return Map<String, dynamic>.from(
      await _decode(response, uri: uri, method: 'PATCH'),
    );
  }
}
