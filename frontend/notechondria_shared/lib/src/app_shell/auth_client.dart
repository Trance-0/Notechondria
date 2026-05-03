/// Subset of `NotechondriaClient` needed by `AppShellAuthActionsMixin`
/// and `AppShellOAuthMixin`. Each app's `NotechondriaClient` extends /
/// implements this so the shared mixins can call the auth endpoints
/// without depending on the full per-app client contract (which
/// diverges on note / course / attachment surfaces).
abstract class AuthClient {
  Future<Map<String, dynamic>> register(
    String username,
    String email,
    String password, {
    String invitationCode,
  });
  Future<Map<String, dynamic>> verifyEmail(String email, String code);
  Future<Map<String, dynamic>> resendVerification(String email);
  Future<Map<String, dynamic>> login(String email, String password);
  Future<Map<String, dynamic>> requestPasswordReset(String email);
  Future<Map<String, dynamic>> confirmPasswordReset(
    String email,
    String code,
    String password,
  );
  Future<Map<String, dynamic>> loginWithGoogle(
    String code, {
    String redirectUri,
    String invitationCode,
    String intent,
  });
  Future<Map<String, dynamic>> loginWithGithub(
    String code, {
    String redirectUri,
    String invitationCode,
    String intent,
  });
  Future<Map<String, dynamic>> bindGoogle(
    String token,
    String code, {
    String redirectUri,
  });
  Future<Map<String, dynamic>> bindGithub(
    String token,
    String code, {
    String redirectUri,
  });
  Future<Map<String, dynamic>> getOAuthConfig();

  /// `GET /api/v1/auth/casdoor/config/`. Returns
  /// `{configured: bool, endpoint, client_id, organization,
  /// application, signin_url}`. When the backend is in shadow mode
  /// (no `CASDOOR_*` env vars set), returns `{configured: false}`
  /// with no other fields, so the SPA falls through to the legacy
  /// auth surface. Public — no token required.
  Future<Map<String, dynamic>> getCasdoorConfig();

  /// `POST /api/v1/auth/casdoor/exchange/`. Accepts a Casdoor
  /// authorization code from the SSO redirect, returns the standard
  /// `auth_payload` shape (`token`, `session`, `user`, ...) so the
  /// existing `applyAuthPayload` machinery on each app's
  /// `_AppShellState` keeps working unchanged. Public — no token
  /// required.
  Future<Map<String, dynamic>> casdoorExchange(String code, {String state});

  Future<Map<String, dynamic>> checkSession(String token);

  /// GET /api/v1/auth/sessions/ — multi-device manager listing
  /// (0.1.65 backend). Response: `{sessions: [{id, device_label,
  /// user_agent, ip_hash_prefix, created_at, last_seen_at,
  /// is_current}, ...], current_session_id}`.
  Future<Map<String, dynamic>> listSessions(String token);

  /// DELETE /api/v1/auth/sessions/<id>/ — revoke a specific session.
  /// Owner-scoped (404 on cross-user attempts). Revoking the
  /// current session effectively signs THIS device out.
  Future<void> revokeSession(String token, int sessionId);

  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  );
}
