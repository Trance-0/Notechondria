part of notechondria_frontend;

/// Defines the frontend contract for all Notechondria REST operations.
abstract class NotechondriaClient implements AuthClient {
  Future<List<Map<String, dynamic>>> getCourses({String? token});
  Future<Map<String, dynamic>> createCourse(
    String token,
    Map<String, dynamic> payload,
  );
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
  Future<Map<String, dynamic>> restoreTemplateCourses(String token);
  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password, {
    String invitationCode = '',
  });
  Future<Map<String, dynamic>> validateInvitation(String invitationCode);
  Future<Map<String, dynamic>> verifyEmail(String email, String code);
  Future<Map<String, dynamic>> resendVerification(String email);
  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> loginWithGoogle(String code, {String redirectUri = '', String invitationCode = '', String intent = 'register'});
  Future<Map<String, dynamic>> loginWithGithub(String code, {String redirectUri = '', String invitationCode = '', String intent = 'register'});
  Future<Map<String, dynamic>> getOAuthConfig();
  Future<List<Map<String, dynamic>>> listSocialAccounts(String token);
  Future<void> unlinkSocialAccount(String token, String provider);
  Future<Map<String, dynamic>> bindGoogle(String token, String code, {String redirectUri = ''});
  Future<Map<String, dynamic>> bindGithub(String token, String code, {String redirectUri = ''});
  Future<Map<String, dynamic>> requestPasswordReset(String email);
  Future<Map<String, dynamic>> confirmPasswordReset(
    String email,
    String code,
    String password,
  );
  Future<Map<String, dynamic>> checkSession(String token);
  // listSessions + revokeSession are inherited from shared AuthClient;
  // don't re-declare here.
  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  );

  /// Experimental GitHub data-sync. See
  /// `docs/integrations/github-sync.md` for the full flow.
  Future<Map<String, dynamic>> githubSyncStatus(String token);
  Future<List<Map<String, dynamic>>> githubSyncRepos(String token);
  Future<Map<String, dynamic>> githubSyncCallback(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> githubSyncPush(String token);
  Future<void> githubSyncDisconnect(String token);

  Future<Map<String, dynamic>> uploadAvatar(String token, XFile file);
  /// Upload a cover image for the given note. Backend returns the
  /// updated note summary including the new `cover_image_url`. Owner-
  /// only on the backend (403 from non-owners).
  Future<Map<String, dynamic>> uploadNoteCoverImage(
    String token,
    int noteId,
    XFile file,
  );
  /// Clear the cover image for the given note. Returns the updated
  /// note summary (now with `cover_image_url == ''`).
  Future<Map<String, dynamic>> deleteNoteCoverImage(
    String token,
    int noteId,
  );
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

/// Outcome of a backend handshake probe. See
/// `HttpNotechondriaClient.verifyHandshake` for how this is populated.
class HandshakeResult {
  const HandshakeResult._({
    required this.ok,
    required this.error,
    required this.service,
    required this.apiVersion,
    required this.version,
    required this.capabilities,
  });

  factory HandshakeResult.success({
    required String service,
    required String apiVersion,
    required String version,
    required Map<String, dynamic> capabilities,
  }) =>
      HandshakeResult._(
        ok: true,
        error: null,
        service: service,
        apiVersion: apiVersion,
        version: version,
        capabilities: capabilities,
      );

  factory HandshakeResult.failure(String message) => HandshakeResult._(
        ok: false,
        error: message,
        service: '',
        apiVersion: '',
        version: '',
        capabilities: const <String, dynamic>{},
      );

  final bool ok;
  final String? error;
  final String service;
  final String apiVersion;
  final String version;
  final Map<String, dynamic> capabilities;
}

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

  /// Optional debug-log sink for per-request tracing. See editor_app
  /// `HttpNotechondriaClient` for the full contract.
  void Function(DebugLogLevel level, String source, String message)? _logger;

  // HttpClientInternalsMixin wiring.
  @override
  http.Client get httpClient => _httpClient;
  @override
  void Function(DebugLogLevel level, String source, String message)?
      get logger => _logger;
  @override
  String get httpLogTagPrefix => 'Planner';

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
  // `_post`, `_patch`, `_delete`, `headers`,
  // `shapedErrorMessage`, `_stringifyErrors`, `_previewBody`,
  // `_formatDecodeError`, `_recordDebugSnapshot`) lives in
  // `core/http_client_internals.dart` as an extension on
  // `HttpNotechondriaClient` so this file stays closer to the
  // AGENTS.md \u00a71.5 1000-line cap.


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
  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password, {
    String invitationCode = '',
  }) async {
    final uri = _uri('/auth/register/');
    final payload = <String, dynamic>{
      'username': username,
      'email': email,
      'password': password,
    };
    if (invitationCode.isNotEmpty) {
      payload['invitation_code'] = invitationCode;
    }
    final response = await _post(uri, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> validateInvitation(String invitationCode) async {
    final uri = _uri('/auth/validate-invitation/');
    final response = await _post(
      uri,
      payload: {'invitation_code': invitationCode},
    );
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> verifyEmail(String email, String code) async {
    final uri = _uri('/auth/verify-email/');
    final response = await _post(
      uri,
      payload: {'email': email, 'code': code},
    );
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> resendVerification(String email) async {
    final uri = _uri('/auth/resend-verification/');
    final response = await _post(uri, payload: {'email': email});
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
  Future<Map<String, dynamic>> loginWithGoogle(String code, {String redirectUri = '', String invitationCode = '', String intent = 'register'}) async {
    final uri = _uri('/auth/google/');
    final payload = <String, dynamic>{'code': code, 'intent': intent};
    if (redirectUri.isNotEmpty) payload['redirect_uri'] = redirectUri;
    if (invitationCode.isNotEmpty) payload['invitation_code'] = invitationCode;
    final response = await _post(uri, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> loginWithGithub(String code, {String redirectUri = '', String invitationCode = '', String intent = 'register'}) async {
    final uri = _uri('/auth/github/');
    final payload = <String, dynamic>{'code': code, 'intent': intent};
    if (redirectUri.isNotEmpty) payload['redirect_uri'] = redirectUri;
    if (invitationCode.isNotEmpty) payload['invitation_code'] = invitationCode;
    final response = await _post(uri, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> getOAuthConfig() async {
    final uri = _uri('/auth/oauth-config/');
    final response = await _get(uri);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listSocialAccounts(String token) async {
    final uri = _uri('/auth/social-accounts/');
    final response = await _get(uri, token: token);
    final decoded = await decode(response, uri: uri, method: 'GET');
    return List<Map<String, dynamic>>.from(
      (decoded as List).map((e) => Map<String, dynamic>.from(e)),
    );
  }

  @override
  Future<void> unlinkSocialAccount(String token, String provider) async {
    final uri = _uri('/auth/social-accounts/$provider/');
    final response = await _httpClient.delete(uri, headers: {'Authorization': 'Token $token'});
    if (response.statusCode != 204) {
      await decode(response, uri: uri, method: 'DELETE');
    }
  }

  @override
  Future<Map<String, dynamic>> bindGoogle(String token, String code, {String redirectUri = ''}) async {
    final uri = _uri('/auth/bind/google/');
    final payload = <String, dynamic>{'code': code};
    if (redirectUri.isNotEmpty) payload['redirect_uri'] = redirectUri;
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> bindGithub(String token, String code, {String redirectUri = ''}) async {
    final uri = _uri('/auth/bind/github/');
    final payload = <String, dynamic>{'code': code};
    if (redirectUri.isNotEmpty) payload['redirect_uri'] = redirectUri;
    final response = await _post(uri, token: token, payload: payload);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    final uri = _uri('/auth/password-reset/');
    final response = await _post(uri, payload: {'email': email});
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
  }

  @override
  Future<Map<String, dynamic>> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) async {
    final uri = _uri('/auth/password-reset/confirm/');
    final response = await _post(
      uri,
      payload: {'email': email, 'code': code, 'password': password},
    );
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'POST'),
    );
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
  Future<Map<String, dynamic>> listSessions(String token) async {
    final uri = _uri('/auth/sessions/');
    final response = await _get(uri, token: token);
    return Map<String, dynamic>.from(
      await decode(response, uri: uri, method: 'GET'),
    );
  }

  @override
  Future<void> revokeSession(String token, int sessionId) async {
    final uri = _uri('/auth/sessions/$sessionId/');
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
  Future<Map<String, dynamic>> githubSyncPush(String token) async {
    final uri = _uri('/integrations/github/push/');
    final response = await _post(uri, token: token, payload: const {});
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
