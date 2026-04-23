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
  Future<Map<String, dynamic>> sendIdentityCode(String token);
  Future<Map<String, dynamic>> rotateApiKey(String token);
  Future<Map<String, dynamic>> changePassword(String token, String currentPassword, String newPassword, String identityCode);
  Future<Map<String, dynamic>> changeEmailRequest(String token, String newEmail, String identityCode);
  Future<Map<String, dynamic>> changeEmailConfirm(String token, String newEmail, String code);
  Future<Map<String, dynamic>> checkSession(String token);
  // listSessions + revokeSession are inherited from shared AuthClient.
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

