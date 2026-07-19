part of notechondria_frontend;

/// Defines the frontend contract for all Notechondria REST operations.
abstract class NotechondriaClient implements AuthClient {
  /// Probe a candidate backend's `/handshake/` to confirm it is a
  /// Notechondria backend and read its metadata (including the
  /// media-storage architecture label shown on the storage card).
  Future<HandshakeResult> verifyHandshake(String rawCandidateBaseUrl);
  Future<Map<String, dynamic>> getFrontPage({String? token});
  Future<List<Map<String, dynamic>>> getCourses({String? token});
  Future<Map<String, dynamic>> createCourse(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> getCourseDetail(int courseId, {String? token});

  /// Owner-only course metadata update (`PATCH /courses/<id>/`): title,
  /// description, icon, and `color_hue` (0-359 or null = theme default).
  Future<Map<String, dynamic>> updateCourse(
    String token,
    int courseId,
    Map<String, dynamic> payload,
  );

  /// Binds a course to a GitHub repo (`PUT /courses/<id>/git/`,
  /// owner-only; one repo per course by design).
  Future<Map<String, dynamic>> setCourseGit(
    String token,
    int courseId,
    Map<String, dynamic> payload,
  );

  /// Imports the bound repo's markdown into the course
  /// (`POST /courses/<id>/git/import/`, idempotent).
  Future<Map<String, dynamic>> importCourseGit(String token, int courseId);
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId,
      {String? token});

  /// Paged course-notes (`?limit=&offset=`) → `{results, total, offset,
  /// limit, has_more}`. The unpaged [getCourseNotes] stays for callers
  /// that genuinely need the full set (e.g. in-course link resolution).
  Future<Map<String, dynamic>> getCourseNotesPage(
    int courseId, {
    String? token,
    int limit = 10,
    int offset = 0,
  });
  Future<Map<String, dynamic>> getNoteDetail(int noteId, {String? token});

  /// Fetch a note by its public UUID (`/notes/uuid/<uuid>/`) — the routed
  /// note-URL entry point. Anonymous requests read public notes; a token
  /// additionally reads owned and subscribed-course notes.
  Future<Map<String, dynamic>> getNoteDetailByUuid(String noteUuid,
      {String? token});
  Future<Map<String, dynamic>> listNotes({
    String? token,
    String query = '',
    int offset = 0,
    int limit = 20,
    String? scope,
    String? sort,
    String? window,
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
    int? days,
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
  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> checkSession(String token);
  Future<Map<String, dynamic>> rotateApiKey(String token);

  /// Casdoor link / unlink — see docs/integrations/casdoor-migration.md.
  /// `getCasdoorConfig` and `casdoorExchange` are inherited from
  /// `AuthClient`; the per-user link operations live here because
  /// they need an authenticated session.
  Future<Map<String, dynamic>> casdoorBind(String token, String code);
  Future<void> casdoorUnlink(String token);

  /// Experimental GitHub data-sync. See
  /// `docs/integrations/github-sync.md` for the full flow.
  Future<Map<String, dynamic>> githubSyncStatus(String token);
  Future<List<Map<String, dynamic>>> githubSyncRepos(String token);
  Future<Map<String, dynamic>> githubSyncCallback(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> githubSyncPush(
    String token, {
    bool includeAssets,
  });
  Future<void> githubSyncDisconnect(String token);

  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> uploadAvatar(String token, XFile file);
  Future<Map<String, dynamic>> uploadNoteCoverImage(
    String token,
    int noteId,
    XFile file,
  );
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
    this.storageLabel = '',
    this.minFrontendVersion = '',
  });

  factory HandshakeResult.success({
    required String service,
    required String apiVersion,
    required String version,
    required Map<String, dynamic> capabilities,
    String storageLabel = '',
    String minFrontendVersion = '',
  }) =>
      HandshakeResult._(
        ok: true,
        error: null,
        service: service,
        apiVersion: apiVersion,
        version: version,
        capabilities: capabilities,
        storageLabel: storageLabel,
        minFrontendVersion: minFrontendVersion,
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

  /// Human label for the backend's media-storage architecture
  /// (e.g. "Cloudflare R2" / "Local disk"), from the handshake
  /// `storage.label` field. Empty when the backend predates it.
  final String storageLabel;

  /// Lowest frontend build the backend still supports, from the
  /// handshake `min_frontend_version` field. Empty = no floor.
  final String minFrontendVersion;
}
