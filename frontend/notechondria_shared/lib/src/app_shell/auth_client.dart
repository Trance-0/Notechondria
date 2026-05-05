/// Subset of `NotechondriaClient` needed by `AppShellAuthActionsMixin`
/// and `AppShellOAuthMixin`. Each app's `NotechondriaClient` extends /
/// implements this so the shared mixins can call the auth endpoints
/// without depending on the full per-app client contract (which
/// diverges on note / course / attachment surfaces).
///
/// Post-0.1.106 cleanup: signup, password reset, email verification,
/// and per-device session management are all owned by Casdoor at
/// `auth.trance-0.com`. The Notechondria backend exposes only the
/// Casdoor exchange / bind / unlink endpoints + an authenticated
/// settings probe.
abstract class AuthClient {
  Future<Map<String, dynamic>> login(String email, String password);

  /// `GET /api/v1/auth/casdoor/config/`. Returns
  /// `{configured: bool, endpoint, client_id, organization,
  /// application, signin_url}`. When the backend is in shadow mode
  /// (no `CASDOOR_*` env vars set), returns `{configured: false}`
  /// with no other fields. Public — no token required.
  Future<Map<String, dynamic>> getCasdoorConfig();

  /// `POST /api/v1/auth/casdoor/exchange/`. Accepts a Casdoor
  /// authorization code from the SSO redirect, returns the standard
  /// `auth_payload` shape (`token`, `user`, ...). Public — no token
  /// required.
  Future<Map<String, dynamic>> casdoorExchange(String code, {String state});

  /// `POST /api/v1/auth/casdoor/bind/`. Authenticated bind path —
  /// links the Casdoor `sub` from the freshly-exchanged token to the
  /// CURRENT signed-in user (instead of resolving identity via the
  /// email-iexact / auto-provision branches). 409 when the same sub
  /// is already linked to a different account.
  Future<Map<String, dynamic>> casdoorBind(String token, String code);

  /// `POST /api/v1/auth/casdoor/link/bind/`. Completion path for the
  /// gitea-style link-challenge flow (since 0.1.118): when
  /// [casdoorExchange] returns a `link_challenge` instead of an
  /// auth_payload, the user picks "bind existing account", supplies
  /// their legacy username/email + password, and the backend stamps
  /// `Creator.casdoor_sub = challenge.sub` after authenticating
  /// against the legacy hasher. Returns the standard `auth_payload`
  /// on success. Public — the nonce itself is the authentication
  /// (one-shot, expires in 10 min).
  Future<Map<String, dynamic>> casdoorLinkBind({
    required String nonce,
    required String identifier,
    required String password,
  });

  /// `POST /api/v1/auth/casdoor/link/create/`. Completion path for
  /// the gitea-style link-challenge flow (since 0.1.118): when the
  /// user picks "create new account", they supply a fresh password;
  /// the backend creates a new User with username + email drawn
  /// from the JWT claims captured on the LinkChallenge. Returns the
  /// standard `auth_payload` on success. 409 when a legacy account
  /// already exists for the Casdoor email — caller should redirect
  /// the user to [casdoorLinkBind] instead.
  Future<Map<String, dynamic>> casdoorLinkCreate({
    required String nonce,
    required String password,
  });

  /// `DELETE /api/v1/auth/casdoor/unlink/`. Idempotent. Drops the
  /// Casdoor link on the current user's Creator without logging the
  /// session out.
  Future<void> casdoorUnlink(String token);

  Future<Map<String, dynamic>> checkSession(String token);

  Future<void> logout(String token);
  Future<Map<String, dynamic>> getSettings(String token);
  Future<Map<String, dynamic>> updateSettings(
    String token,
    Map<String, dynamic> payload,
  );
}
