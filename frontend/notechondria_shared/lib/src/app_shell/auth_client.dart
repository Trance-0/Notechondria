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
  Future<Map<String, dynamic>> checkSession(String token);
  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  );
}
