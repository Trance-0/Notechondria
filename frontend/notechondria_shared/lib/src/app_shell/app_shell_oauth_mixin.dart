import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/casdoor_link_challenge_dialog.dart';
import '../components/debug_log.dart';
import 'app_shell_auth_actions_mixin.dart';
import 'url_strategy.dart' if (dart.library.html) 'url_strategy_web.dart'
    as url_strategy;

/// OAuth launch + callback handler shared across editor / planner /
/// portal apps. Covers:
///
/// * `launchOAuth(provider, ...)` — stashes the invitation / intent
///   parameters in `SharedPreferences` and redirects the browser to
///   the Casdoor SSO authorize URL. Per-provider Google / GitHub
///   buttons were retired in favor of Casdoor's own provider proxy
///   (configure them on the Casdoor application's Providers tab).
/// * `handleOAuthCallback()` — on web, detects `?code=&state=` after
///   the Casdoor redirect, distinguishes bind-flow vs login-flow,
///   and hands the result to `applyAuthPayload` (login) / the
///   `casdoorBind` endpoint (bind).
///
/// The abstract `token` getter / `setToken` setter read + write the
/// app's session token (needed for the bind flow). `splashStatus`
/// lets the splash screen surface a `'Linking Casdoor account'` /
/// `'Completing sign-in via Casdoor'` label while the bootstrap
/// finishes.
mixin AppShellOAuthMixin<W extends StatefulWidget>
    on State<W>, AppShellAuthActionsMixin<W> {
  /// Current session token. `null` / `''` when anonymous. Setter
  /// only used by this mixin's bind-flow log check; actual token
  /// installation happens in `applyAuthPayload`.
  String? get token;

  /// `ValueNotifier` feeding the splash-screen label. Updated to
  /// surface provider-specific status during OAuth completion.
  ValueNotifier<String> get splashStatus;

  /// Per-app SharedPreferences namespace for the OAuth handoff keys,
  /// derived from `logAppTag` ('Editor' -> 'notechondria.editor.').
  /// Mirrors the 0.1.127 `_LocalAppStore` key namespacing: all three
  /// apps share one localStorage on same-origin web deploys, so
  /// unprefixed keys collide across apps.
  String get _oauthKeyPrefix => 'notechondria.${logAppTag.toLowerCase()}.';

  /// Emits a structured debug log line. Provided by
  /// `AppShellLogMixin` on the same state class.
  void log({
    required String message,
    DebugLogLevel level,
    String source,
    int? durationMs,
  });

  /// Default handler for the gitea-style Casdoor link-challenge
  /// flow (since 0.1.118). Pops a `CasdoorLinkChallengeDialog`,
  /// dispatches the user's chosen completion endpoint
  /// (`casdoorLinkBind` or `casdoorLinkCreate`), and runs the
  /// returned auth_payload through `applyAuthPayload` so the
  /// session installs exactly like the fast-path login.
  ///
  /// Apps can override this on `_AppShellState` if a different
  /// UX is wanted (e.g. routing to a full screen instead of a
  /// dialog), but the default is enough for editor / planner /
  /// portal — they all want the same dialog. Returns `true` on
  /// successful link, `false` on cancel or completion error.
  ///
  /// `payload` is the full exchange response: `link_challenge`,
  /// `expires_at`, `casdoor_identity`, `suggested_username`. The
  /// Casdoor JWT is held server-side on the LinkChallenge row
  /// and replayed back in the eventual auth_payload — the SPA
  /// never sees it before the link decision.
  Future<bool> onCasdoorLinkChallenge(Map<String, dynamic> payload) async {
    final nonce = payload['link_challenge']?.toString() ?? '';
    if (nonce.isEmpty || !mounted) return false;
    final identityRaw = payload['casdoor_identity'];
    final identity = <String, String>{};
    if (identityRaw is Map) {
      identityRaw.forEach((k, v) {
        identity[k.toString()] = v?.toString() ?? '';
      });
    }
    final suggestedUsername =
        payload['suggested_username']?.toString() ?? identity['username'] ?? '';
    final decision = await showDialog<CasdoorLinkChallengeDecision>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CasdoorLinkChallengeDialog(
        casdoorIdentity: identity,
        suggestedUsername: suggestedUsername,
      ),
    );
    if (decision == null) {
      log(
        level: DebugLogLevel.info,
        source: '$logAppTag.Auth/casdoor.link_challenge',
        message: 'Casdoor link challenge cancelled by user: '
            '$logAppTag.Auth/casdoor.link_challenge — '
            'no bind/create decision applied; the challenge will '
            'expire on the server side within 10 minutes.',
      );
      return false;
    }
    try {
      final Map<String, dynamic> authPayload = decision.intent == 'bind'
          ? await authClient.casdoorLinkBind(
              nonce: nonce,
              identifier: decision.identifier,
              password: decision.password,
            )
          : await authClient.casdoorLinkCreate(
              nonce: nonce,
              password: decision.password,
            );
      await applyAuthPayload(authPayload);
      log(
        level: DebugLogLevel.info,
        source: '$logAppTag.Auth/casdoor.link_challenge',
        message: 'Casdoor link challenge resolved: '
            '$logAppTag.Auth/casdoor.link_challenge — '
            'intent=${decision.intent} succeeded; session installed.',
      );
      return true;
    } catch (error) {
      final msg = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: '$logAppTag.Auth/casdoor.link_challenge',
        message: 'Casdoor link challenge failed: '
            '$logAppTag.Auth/casdoor.link_challenge — '
            'intent=${decision.intent} aborted: $msg.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Casdoor link challenge failed: '
              '$logAppTag.Auth/casdoor.link_challenge — $msg',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> launchOAuth(
    String provider, {
    String invitationCode = '',
    String intent = 'register',
  }) async {
    try {
      // Casdoor is the only third-party auth surface — Google /
      // GitHub now ride through Casdoor's own provider proxy. The
      // Casdoor app issues its own JWT, so the callback path uses
      // POST /auth/casdoor/exchange/ rather than the per-provider
      // login endpoints.
      if (provider != 'casdoor') {
        log(
          level: DebugLogLevel.error,
          source: '$logAppTag.Auth/oauth.launch',
          message:
              'Cannot start $provider sign-in: $logAppTag.Auth/oauth.launch — '
              'only the casdoor provider is supported. Configure Google / '
              'GitHub on the Casdoor application\'s Providers tab.',
        );
        return;
      }
      final config = await authClient.getCasdoorConfig();
      if (config['configured'] != true) {
        log(
          level: DebugLogLevel.warning,
          source: '$logAppTag.Auth/oauth.launch',
          message:
              'Cannot start Casdoor sign-in: $logAppTag.Auth/oauth.launch — '
              'backend reports CASDOOR_* env vars are not configured.',
        );
        return;
      }
      final clientId = config['client_id']?.toString() ?? '';
      final signinUrl = config['signin_url']?.toString() ?? '';
      if (clientId.isEmpty || signinUrl.isEmpty) {
        log(
          level: DebugLogLevel.error,
          source: '$logAppTag.Auth/oauth.launch',
          message:
              'Cannot start Casdoor sign-in: $logAppTag.Auth/oauth.launch — '
              'client_id or signin_url missing in /auth/casdoor/config/.',
        );
        return;
      }
      // The current page origin doubles as the redirect URI;
      // Casdoor must have it pre-registered in the application
      // settings on the admin UI. Drop the query string AND the hash
      // fragment: since the apps adopted hash routing (`#/settings`
      // etc., 0.1.179/0.1.186) `Uri.base` carries a fragment, and a
      // redirect_uri containing it fails Casdoor's exact-match
      // validation — the IdP then never redirects back with a code,
      // which broke login with no backend log at all.
      final origin =
          Uri.base.removeFragment().replace(queryParameters: {}).toString();
      log(
        level: DebugLogLevel.info,
        source: '$logAppTag.Auth/oauth.launch',
        message: 'Casdoor sign-in starting: $logAppTag.Auth/oauth.launch — '
            'redirect_uri=$origin intent=$intent.',
      );
      final prefs = await SharedPreferences.getInstance();
      // 0.1.127: keys are app-namespaced. On GitHub Pages all three
      // apps share one browser origin (one localStorage), so the old
      // unprefixed keys let an OAuth flow launched in one app collide
      // with a flow launched in another — a bind intent stashed by
      // planner could complete an editor login with bind semantics.
      final keyPrefix = _oauthKeyPrefix;
      await prefs.setString('${keyPrefix}oauth_redirect_uri', origin);
      await prefs.setString(
          '${keyPrefix}oauth_invitation_code', invitationCode);
      await prefs.setString('${keyPrefix}oauth_intent', intent);
      final base = Uri.parse(signinUrl);
      final authUrl = base.replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': origin,
        'response_type': 'code',
        'scope': 'openid profile email',
        'state': 'casdoor',
      }).toString();
      url_strategy.browserRedirect(authUrl);
    } catch (error) {
      log(
        level: DebugLogLevel.error,
        source: '$logAppTag.Auth/oauth.launch',
        message:
            'OAuth sign-in could not start: $logAppTag.Auth/oauth.launch — '
            '${error.toString().replaceFirst("Exception: ", "")}.',
      );
    }
  }

  /// Check [Uri.base] for an OAuth callback `?code=&state=` and
  /// complete login. Returns `true` if an OAuth callback was handled.
  Future<bool> handleOAuthCallback() async {
    if (!kIsWeb) return false;
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty) return false;
    // Casdoor is the only supported state. Stale `?state=google` /
    // `?state=github` query strings (e.g. bookmarked redirects from
    // the pre-migration era) are ignored so they don't trigger a
    // failed login on a deep-link cold start.
    if (state != 'casdoor') {
      return false;
    }
    log(
      level: DebugLogLevel.info,
      source: '$logAppTag.Auth/casdoor.callback',
      message: 'Casdoor callback received: $logAppTag.Auth/casdoor.callback — '
          'authorization code present, starting exchange.',
    );

    // Clean the URL so a page refresh doesn't re-process the code.
    // Preserve the fragment — it may carry a note deep-link
    // (`#/notes/<uuid>`) that the editor's `_parseNoteUuidFromUrl`
    // reads right after `handleOAuthCallback` returns. Dropping the
    // fragment here used to send the user to the home view after a
    // share-link → OAuth → open-note round trip.
    final cleanUrl = uri.replace(queryParameters: {}).toString();
    url_strategy.browserReplaceState(cleanUrl);

    final prefs = await SharedPreferences.getInstance();
    final keyPrefix = _oauthKeyPrefix;
    // Legacy unprefixed fallback covers a flow launched by a
    // pre-0.1.127 build that completes after this deploy lands.
    final intent = prefs.getString('${keyPrefix}oauth_intent') ??
        prefs.getString('oauth_intent') ??
        'register';
    for (final suffix in const [
      'oauth_redirect_uri',
      'oauth_invitation_code',
      'oauth_intent',
    ]) {
      await prefs.remove('$keyPrefix$suffix');
      await prefs.remove(suffix); // clear any legacy leftover too
    }

    splashStatus.value = intent == 'bind'
        ? 'Linking Casdoor account'
        : 'Completing sign-in via Casdoor';

    // The login path goes through the public exchange endpoint
    // (returns a fresh auth_payload + new Session row); the bind
    // path goes through the authenticated bind endpoint (links sub
    // to the *current* user without minting a new identity). Bind
    // without a token is a sign-out race — bail out with a clear
    // message instead of silently falling through.
    if (intent == 'bind') {
      final currentToken = token;
      if (currentToken == null || currentToken.isEmpty) {
        log(
          level: DebugLogLevel.warning,
          source: '$logAppTag.Auth/casdoor.bind',
          message: 'Casdoor account linking aborted: '
              '$logAppTag.Auth/casdoor.bind — session token missing at '
              'OAuth callback (user signed out between click and redirect).',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Casdoor account linking aborted: '
                '$logAppTag.Auth/casdoor.bind — your session expired '
                'before the provider redirected back. Sign in first, '
                'then try linking the account again.',
              ),
            ),
          );
        }
        return false;
      }
      try {
        await authClient.casdoorBind(currentToken, code);
        log(
          level: DebugLogLevel.info,
          source: '$logAppTag.Auth/casdoor.bind',
          message: 'Linked Casdoor account: $logAppTag.Auth/casdoor.bind — '
              'server accepted the bind token.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Casdoor account linked: $logAppTag.Auth/casdoor.bind — '
                'ready to sign in with Casdoor next time.',
              ),
            ),
          );
        }
        return true;
      } catch (error) {
        final msg = error.toString().replaceFirst('Exception: ', '');
        log(
          level: DebugLogLevel.error,
          source: '$logAppTag.Auth/casdoor.bind',
          message: 'Casdoor account linking failed: '
              '$logAppTag.Auth/casdoor.bind — $msg.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Casdoor account linking failed: '
                '$logAppTag.Auth/casdoor.bind — $msg.',
              ),
            ),
          );
        }
        return false;
      }
    }

    try {
      final result = await authClient.casdoorExchange(code, state: state!);
      // Two response shapes since 0.1.118:
      //   1. Standard auth_payload (`token` + `user`) — the Casdoor
      //      sub is already linked to a Notechondria account.
      //   2. Link challenge (`link_challenge` + `casdoor_identity` +
      //      `suggested_username`) — a fresh Casdoor identity needs
      //      the user to choose between binding to an existing
      //      legacy account or creating a new one with a chosen
      //      password (gitea-style).
      final linkChallenge = result['link_challenge']?.toString() ?? '';
      if (linkChallenge.isNotEmpty) {
        log(
          level: DebugLogLevel.info,
          source: '$logAppTag.Auth/casdoor.link_challenge',
          message: 'Casdoor sign-in needs an account-link decision: '
              '$logAppTag.Auth/casdoor.link_challenge — '
              "Casdoor identity '${result['casdoor_identity']?.toString() ?? '<unknown>'}' "
              'is not yet bound to a Notechondria account; the SPA '
              'must show the bind/create choice dialog.',
        );
        return await onCasdoorLinkChallenge(result);
      }
      await applyAuthPayload(result);
      log(
        level: DebugLogLevel.info,
        source: '$logAppTag.Auth/casdoor.callback',
        message: 'Signed in via Casdoor: $logAppTag.Auth/casdoor.callback — '
            'server accepted the authorization code.',
      );
      return true;
    } catch (error) {
      final msg = error.toString().replaceFirst('Exception: ', '');
      log(
        level: DebugLogLevel.error,
        source: '$logAppTag.Auth/casdoor.callback',
        message:
            'Casdoor sign-in failed: $logAppTag.Auth/casdoor.callback — $msg.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Casdoor sign-in failed: $logAppTag.Auth/casdoor.callback — $msg.',
            ),
          ),
        );
      }
      return false;
    }
  }
}
