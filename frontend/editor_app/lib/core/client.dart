part of notechondria_frontend;

/// Defines the frontend contract for all Notechondria REST operations.
/// Implements `AuthClient` so the shared `AppShellAuthActionsMixin`
/// and `AppShellOAuthMixin` can drive the auth endpoints.
abstract class NotechondriaClient implements AuthClient {
  Future<Map<String, dynamic>> getFrontPage({String? token});
  Future<List<Map<String, dynamic>>> getCourses({String? token});
  Future<Map<String, dynamic>> createCourse(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> updateCourse(
    String token,
    int courseId,
    Map<String, dynamic> payload,
  );
  Future<void> deleteCourse(String token, int courseId);
  /// Persists the sidebar drag-reorder by POSTing the ordered course id list.
  /// Returns the refreshed course list with new `sort_order` values applied.
  Future<List<Map<String, dynamic>>> reorderCourses(
    String token,
    List<int> courseIds,
  );
  Future<Map<String, dynamic>> getCourseDetail(int courseId, {String? token});
  Future<List<Map<String, dynamic>>> getCourseNotes(int courseId, {String? token});
  Future<Map<String, dynamic>> getNoteDetail(int noteId, {String? token});
  Future<Map<String, dynamic>> getNoteByUuid(String uuid, {String? token});
  Future<Map<String, dynamic>> listNotes({
    String? token,
    String query = '',
    int offset = 0,
    int limit = 20,
    int? courseId,
    /// Search scope: 'personal' = own notes only (default).
    /// 'all' = own notes + public notes from any user.
    String scope = 'personal',
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
  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> rotateApiKey(String token);

  /// `GET /api/v1/integrations/github/status/`. Returns the raw
  /// payload for the experimental data-sync card.
  Future<Map<String, dynamic>> githubSyncStatus(String token);

  /// `GET /api/v1/integrations/github/repos/`. Lists repositories
  /// visible to the user's GitHub App installation.
  Future<List<Map<String, dynamic>>> githubSyncRepos(String token);

  /// `POST /api/v1/integrations/github/callback/`. Persists or
  /// updates the integration row.
  Future<Map<String, dynamic>> githubSyncCallback(
    String token,
    Map<String, dynamic> payload,
  );

  /// `POST /api/v1/integrations/github/push/`. Materializes user
  /// data into the chosen repo. Returns `{commit_sha: ...}`. When
  /// ``includeAssets`` is true the backend also inlines avatar /
  /// cover / attachment bytes under ``assets/``.
  Future<Map<String, dynamic>> githubSyncPush(
    String token, {
    bool includeAssets,
  });

  /// `DELETE /api/v1/integrations/github/status/`. Drops the local
  /// integration row; the GitHub App stays installed until the user
  /// removes it from their GitHub settings.
  Future<void> githubSyncDisconnect(String token);

  Future<Map<String, dynamic>> checkSession(String token);
  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  );
  Future<Map<String, dynamic>> uploadAvatar(String token, XFile file);
  Future<List<Map<String, dynamic>>> listNoteAttachments(
    String token,
    int noteId,
  );
  Future<Map<String, dynamic>> uploadNoteAttachment(
    String token,
    int noteId,
    XFile file,
  );
  Future<void> deleteNoteAttachment(
    String token,
    int noteId,
    int attachmentId,
  );
  /// UUID-based variants. Look up the note by its server UUID instead of
  /// integer PK, aligning with the frontend's `local://<note-uuid>/<filename>`
  /// scheme so sync code can operate without passing integer ids.
  Future<List<Map<String, dynamic>>> listNoteAttachmentsByUuid(
    String token,
    String noteUuid,
  );
  Future<Map<String, dynamic>> uploadNoteAttachmentByUuid(
    String token,
    String noteUuid,
    XFile file,
  );
  Future<void> deleteNoteAttachmentByUuid(
    String token,
    String noteUuid,
    int attachmentId,
  );
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

