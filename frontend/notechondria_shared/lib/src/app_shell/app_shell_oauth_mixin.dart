import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/debug_log.dart';
import 'app_shell_auth_actions_mixin.dart';
import 'url_strategy.dart'
    if (dart.library.html) 'url_strategy_web.dart' as url_strategy;

/// OAuth launch + callback handler shared across editor / planner /
/// portal apps. Covers:
///
/// * `launchOAuth(provider, ...)` — stashes the invitation / intent
///   parameters in `SharedPreferences` and redirects the browser to
///   Google or GitHub's authorize URL.
/// * `handleOAuthCallback()` — on web, detects `?code=&state=` after
///   the provider redirect, distinguishes bind-flow vs login-flow,
///   and hands the result to `applyAuthPayload` (bind) /
///   the registered `applyAuthPayload` (login) from
///   `AppShellAuthActionsMixin`.
///
/// The abstract `token` getter / `setToken` setter read + write the
/// app's session token (needed for the bind flow). `splashStatus`
/// lets the splash screen cross-fade between provider-specific
/// labels (`'Linking Google account'` / `'Completing sign-in via
/// GitHub'` / ...). `deepLinkReplaceQuery` is a small hook the
/// subclass overrides if it needs to preserve a note UUID in the URL
/// fragment while the OAuth query is stripped.
mixin AppShellOAuthMixin<W extends StatefulWidget>
    on State<W>, AppShellAuthActionsMixin<W> {
  /// Current session token. `null` / `''` when anonymous. Setter
  /// only used by this mixin's bind-flow log check; actual token
  /// installation happens in `applyAuthPayload`.
  String? get token;

  /// `ValueNotifier` feeding the splash-screen label. Updated to
  /// surface provider-specific status during OAuth completion.
  ValueNotifier<String> get splashStatus;

  /// Emits a structured debug log line. Provided by
  /// `AppShellLogMixin` on the same state class.
  void log({
    required String message,
    DebugLogLevel level,
    String source,
    int? durationMs,
  });

  Future<void> launchOAuth(
    String provider, {
    String invitationCode = '',
    String intent = 'register',
  }) async {
    try {
      // Casdoor goes through a separate /auth/casdoor/config/
      // endpoint instead of the per-provider /auth/oauth-config/
      // bundle. The Casdoor app issues its own JWT, so the
      // callback path uses POST /auth/casdoor/exchange/ rather
      // than the per-provider login endpoints.
      if (provider == 'casdoor') {
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
        // settings on the admin UI. Drop any existing query string
        // so the round-trip's `?code=&state=` is the only thing
        // present when handleOAuthCallback wakes back up.
        final origin = Uri.base.replace(queryParameters: {}).toString();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('oauth_redirect_uri', origin);
        await prefs.setString('oauth_invitation_code', invitationCode);
        await prefs.setString('oauth_intent', intent);
        final base = Uri.parse(signinUrl);
        final authUrl = base.replace(queryParameters: {
          'client_id': clientId,
          'redirect_uri': origin,
          'response_type': 'code',
          'scope': 'openid profile email',
          'state': 'casdoor',
        }).toString();
        url_strategy.browserRedirect(authUrl);
        return;
      }
      final config = await authClient.getOAuthConfig();
      final providerConfig = Map<String, dynamic>.from(
        config[provider] as Map? ?? {},
      );
      final clientId = providerConfig['client_id']?.toString() ?? '';
      final redirectUri = providerConfig['redirect_uri']?.toString() ?? '';
      if (clientId.isEmpty) {
        log(
          level: DebugLogLevel.error,
          source: '$logAppTag.Auth/oauth.launch',
          message:
              'Cannot start $provider sign-in: $logAppTag.Auth/oauth.launch — '
              'client_id missing in OAuth config for $provider.',
        );
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('oauth_redirect_uri', redirectUri);
      await prefs.setString('oauth_invitation_code', invitationCode);
      await prefs.setString('oauth_intent', intent);

      final String authUrl;
      if (provider == 'google') {
        authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': 'openid email profile',
          'state': 'google',
          'access_type': 'offline',
          'prompt': 'select_account',
        }).toString();
      } else {
        authUrl = Uri.https('github.com', '/login/oauth/authorize', {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'scope': 'user:email',
          'state': 'github',
        }).toString();
      }
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
    if (state != 'google' && state != 'github' && state != 'casdoor') {
      return false;
    }

    // Clean the URL so a page refresh doesn't re-process the code.
    // Preserve the fragment — it may carry a note deep-link
    // (`#/notes/<uuid>`) that the editor's `_parseNoteUuidFromUrl`
    // reads right after `handleOAuthCallback` returns. Dropping the
    // fragment here used to send the user to the home view after a
    // share-link → OAuth → open-note round trip.
    final cleanUrl = uri
        .replace(queryParameters: {})
        .toString();
    url_strategy.browserReplaceState(cleanUrl);

    final prefs = await SharedPreferences.getInstance();
    final redirectUri = prefs.getString('oauth_redirect_uri') ?? '';
    final invitationCode = prefs.getString('oauth_invitation_code') ?? '';
    final intent = prefs.getString('oauth_intent') ?? 'register';
    await prefs.remove('oauth_redirect_uri');
    await prefs.remove('oauth_invitation_code');
    await prefs.remove('oauth_intent');

    // Surface provider-specific status on the splash so the user
    // knows which third-party flow is completing. The splash widget
    // cross-fades between these strings as the bootstrap advances.
    final String providerLabel;
    if (state == 'google') {
      providerLabel = 'Google';
    } else if (state == 'github') {
      providerLabel = 'GitHub';
    } else {
      providerLabel = 'Casdoor';
    }
    splashStatus.value = intent == 'bind'
        ? 'Linking $providerLabel account'
        : 'Completing sign-in via $providerLabel';

    // Casdoor short-circuit. The login path goes through the public
    // exchange endpoint (returns a fresh auth_payload + new Session
    // row); the bind path goes through the authenticated bind
    // endpoint (links sub to the *current* user without minting a
    // new identity). Bind without a token is a sign-out race —
    // bail out with a clear message instead of falling through to
    // the legacy provider branches below.
    if (state == 'casdoor') {
      if (intent == 'bind') {
        final currentToken = token;
        if (currentToken == null || currentToken.isEmpty) {
          log(
            level: DebugLogLevel.warning,
            source: '$logAppTag.Auth/casdoor.bind',
            message:
                'Casdoor account linking aborted: '
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
            message:
                'Linked Casdoor account: $logAppTag.Auth/casdoor.bind — '
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
            message:
                'Casdoor account linking failed: '
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
        await applyAuthPayload(result);
        log(
          level: DebugLogLevel.info,
          source: '$logAppTag.Auth/casdoor.callback',
          message:
              'Signed in via Casdoor: $logAppTag.Auth/casdoor.callback — '
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

    // Bind flow: user should already be authenticated. We handle
    // three cases distinctly so the user gets a coherent error:
    //   - bind + token      -> call /auth/bind/<provider>/ (authed).
    //   - bind + no token   -> session expired between clicking the
    //                          button and the OAuth callback; don't
    //                          fall through to the login endpoint
    //                          (it would reject intent=bind with a
    //                          400 that looks like a backend bug).
    if (intent == 'bind') {
      final currentToken = token;
      if (currentToken == null || currentToken.isEmpty) {
        log(
          level: DebugLogLevel.warning,
          source: '$logAppTag.Auth/bind',
          message:
              'Account linking aborted: $logAppTag.Auth/bind — session token '
              'missing at OAuth callback (user signed out between click and '
              'redirect).',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Account linking aborted: $logAppTag.Auth/bind — your '
                'session expired before the provider redirected back. '
                'Sign in first, then try linking the account again.',
              ),
            ),
          );
        }
        return false;
      }
      try {
        if (state == 'google') {
          await authClient.bindGoogle(currentToken, code,
              redirectUri: redirectUri);
        } else {
          await authClient.bindGithub(currentToken, code,
              redirectUri: redirectUri);
        }
        log(
          level: DebugLogLevel.info,
          source: '$logAppTag.Auth/bind',
          message:
              'Linked $providerLabel account: $logAppTag.Auth/bind — '
              'server accepted the bind token.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$providerLabel account linked: $logAppTag.Auth/bind — '
                'ready to sign in with $providerLabel next time.',
              ),
            ),
          );
        }
        return true;
      } catch (error) {
        final msg = error.toString().replaceFirst('Exception: ', '');
        log(
          level: DebugLogLevel.error,
          source: '$logAppTag.Auth/bind',
          message:
              'Account linking failed: $logAppTag.Auth/bind — $msg.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Account linking failed: $logAppTag.Auth/bind — $msg.',
              ),
            ),
          );
        }
        return false;
      }
    }

    try {
      final Map<String, dynamic> result;
      if (state == 'google') {
        result = await authClient.loginWithGoogle(
          code,
          redirectUri: redirectUri,
          invitationCode: invitationCode,
          intent: intent,
        );
      } else {
        result = await authClient.loginWithGithub(
          code,
          redirectUri: redirectUri,
          invitationCode: invitationCode,
          intent: intent,
        );
      }
      await applyAuthPayload(result);
      log(
        level: DebugLogLevel.info,
        source: '$logAppTag.Auth/oauth.callback',
        message:
            'Signed in via $providerLabel: '
            '$logAppTag.Auth/oauth.callback — server accepted the '
            'authorization code.',
      );
      return true;
    } catch (error) {
      final msg = error.toString().replaceFirst('Exception: ', '');
      // Preserved sentinels: "not_registered" and "No account found"
      // drive the registration-prompt branch in the UI.
      if (msg.contains('not_registered') || msg.contains('No account found')) {
        log(
          level: DebugLogLevel.warning,
          source: '$logAppTag.Auth/oauth.callback',
          message:
              'OAuth sign-in rejected: $logAppTag.Auth/oauth.callback — '
              'No account found for this identity (server replied '
              'not_registered). Register first.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'OAuth sign-in rejected: $logAppTag.Auth/oauth.callback '
                '— No account found for this identity. Please register '
                'first.',
              ),
            ),
          );
        }
      } else {
        log(
          level: DebugLogLevel.error,
          source: '$logAppTag.Auth/oauth.callback',
          message:
              'OAuth sign-in failed: $logAppTag.Auth/oauth.callback — $msg.',
        );
      }
      return false;
    }
  }
}
