part of notechondria_frontend;

/// OAuth + session-restore + deep-link handlers. Every method routes
/// state mutations through `_refresh()` since extensions can't call
/// `setState` directly. Bind-flow, login-flow, and deep-link dialog
/// wiring all live here; `_applyAuthPayload` stays on `_AppShellState`
/// because it orchestrates post-login state across every bucket (see
/// the Authentication section of `app_shell.dart`). Extracted from
/// `app_shell.dart` so that file stays closer to the AGENTS.md §1.5
/// 1000-line ceiling.
extension _AppShellAuthFlowsX on _AppShellState {
  Future<void> _launchOAuth(String provider, {String invitationCode = '', String intent = 'register'}) async {
    try {
      final config = await widget.client.getOAuthConfig();
      final providerConfig = Map<String, dynamic>.from(
        config[provider] as Map? ?? {},
      );
      final clientId = providerConfig['client_id']?.toString() ?? '';
      final redirectUri = providerConfig['redirect_uri']?.toString() ?? '';
      if (clientId.isEmpty) {
        _log(
          level: DebugLogLevel.error,
          source: 'Editor.Auth/oauth.launch',
          message:
              'Cannot start $provider sign-in: Editor.Auth/oauth.launch \u2014 '
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
      _log(
        level: DebugLogLevel.error,
        source: 'Editor.Auth/oauth.launch',
        message:
            'OAuth sign-in could not start: Editor.Auth/oauth.launch \u2014 '
            '${error.toString().replaceFirst("Exception: ", "")}.',
      );
    }
  }

  /// Check [Uri.base] for an OAuth callback `?code=&state=` and complete login.
  /// Returns true if an OAuth callback was handled.
  Future<bool> _handleOAuthCallback() async {
    if (!kIsWeb) return false;
    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || code.isEmpty) return false;
    if (state != 'google' && state != 'github') return false;

    // Clean the URL so a page refresh doesn't re-process the code.
    final cleanUrl = uri.removeFragment().replace(queryParameters: {}).toString();
    url_strategy.browserReplaceState(cleanUrl);

    final prefs = await SharedPreferences.getInstance();
    final redirectUri = prefs.getString('oauth_redirect_uri') ?? '';
    final invitationCode = prefs.getString('oauth_invitation_code') ?? '';
    final intent = prefs.getString('oauth_intent') ?? 'register';
    await prefs.remove('oauth_redirect_uri');
    await prefs.remove('oauth_invitation_code');
    await prefs.remove('oauth_intent');

    // Surface provider-specific status on the splash so the user knows
    // which third-party flow is completing. The splash widget
    // cross-fades between these strings as the bootstrap advances.
    final providerLabel = state == 'google' ? 'Google' : 'GitHub';
    _splashStatus.value = intent == 'bind'
        ? 'Linking $providerLabel account'
        : 'Completing sign-in via $providerLabel';

    // Bind flow: user should already be authenticated. We handle three
    // cases distinctly so the user gets a coherent error:
    //   - bind + token      -> call /auth/bind/<provider>/ (authenticated).
    //   - bind + no token   -> the session expired between clicking the
    //                          button and the OAuth callback; don't fall
    //                          through to the login endpoint (it would
    //                          reject intent=bind with a 400 that looks
    //                          like a backend bug). Tell the user to
    //                          sign in again and retry.
    if (intent == 'bind') {
      if (_token == null || _token!.isEmpty) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Editor.Auth/bind',
          message:
              'Account linking aborted: Editor.Auth/bind \u2014 session token '
              'missing at OAuth callback (user signed out between click and '
              'redirect).',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account linking aborted: Editor.Auth/bind \u2014 your session '
                'expired before the provider redirected back. Sign in first, '
                'then try linking the account again.',
              ),
            ),
          );
        }
        return false;
      }
      try {
        if (state == 'google') {
          await widget.client.bindGoogle(_token!, code, redirectUri: redirectUri);
        } else {
          await widget.client.bindGithub(_token!, code, redirectUri: redirectUri);
        }
        final provider = state == 'google' ? 'Google' : 'GitHub';
        _log(
          level: DebugLogLevel.info,
          source: 'Editor.Auth/bind',
          message:
              'Linked $provider account: Editor.Auth/bind \u2014 '
              'server accepted the bind token.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$provider account linked: Editor.Auth/bind \u2014 '
                'ready to sign in with $provider next time.',
              ),
            ),
          );
        }
        return true;
      } catch (error) {
        final msg = error.toString().replaceFirst('Exception: ', '');
        _log(
          level: DebugLogLevel.error,
          source: 'Editor.Auth/bind',
          message:
              'Account linking failed: Editor.Auth/bind \u2014 $msg.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Account linking failed: Editor.Auth/bind \u2014 $msg.',
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
        result = await widget.client.loginWithGoogle(code, redirectUri: redirectUri, invitationCode: invitationCode, intent: intent);
      } else {
        result = await widget.client.loginWithGithub(code, redirectUri: redirectUri, invitationCode: invitationCode, intent: intent);
      }
      await _applyAuthPayload(result);
      final providerLabel = state == 'google' ? 'Google' : 'GitHub';
      _log(
        level: DebugLogLevel.info,
        source: 'Editor.Auth/oauth.callback',
        message:
            'Signed in via $providerLabel: Editor.Auth/oauth.callback \u2014 '
            'server accepted the authorization code.',
      );
      return true;
    } catch (error) {
      final msg = error.toString().replaceFirst('Exception: ', '');
      // Preserved sentinel substrings: "not_registered" and "No account found"
      // feed the registration-prompt branch below.
      if (msg.contains('not_registered') || msg.contains('No account found')) {
        _log(
          level: DebugLogLevel.warning,
          source: 'Editor.Auth/oauth.callback',
          message:
              'OAuth sign-in rejected: Editor.Auth/oauth.callback \u2014 '
              'No account found for this identity (server replied '
              'not_registered). Register first.',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'OAuth sign-in rejected: Editor.Auth/oauth.callback \u2014 '
                'No account found for this identity. Please register first.',
              ),
            ),
          );
        }
      } else {
        _log(
          level: DebugLogLevel.error,
          source: 'Editor.Auth/oauth.callback',
          message:
              'OAuth sign-in failed: Editor.Auth/oauth.callback \u2014 $msg.',
        );
      }
      return false;
    }
  }

  /// Fetch a note by UUID and open it in the viewer/editor.
  Future<void> _openNoteByUuid(String uuid) async {
    _isLoading = true;
    _refresh();
    try {
      final detail = await widget.client.getNoteByUuid(uuid, token: _token);
      _selectedNote = detail;
      _selectedIndex = 1;
      _isLoading = false;
      _refresh();
      _replaceNoteUrl(uuid);
      // Open the note viewer/editor dialog after the frame renders.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showNoteDialogForDeepLink(detail);
        });
      }
    } catch (error) {
      _errorMessage = 'Could not load note: ${error.toString().replaceFirst('Exception: ', '')}';
      _isLoading = false;
      _refresh();
    }
  }

  void _showNoteDialogForDeepLink(Map<String, dynamic> detail) {
    final canEdit = detail['can_edit'] == true;
    if (canEdit) {
      // Owner: open in editor.
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _NoteEditorDialog(
          note: detail,
          courses: [..._localCourses, ..._courses],
          editorMode: _settings?['editor_mode']?.toString() ?? 'P',
          onSave: _saveNote,
          onSnapshot: _snapshotNote,
          onGetHistory: _getNoteHistory,
          onRestoreVersion: _restoreNoteVersion,
          onLogEvent: _appendUiLog,
          onUploadAttachment: _uploadNoteAttachment,
        ),
      );
    } else {
      // Non-owner: read-only viewer.
      showDialog<void>(
        context: context,
        builder: (context) => _NoteViewerDialog(
          note: detail,
          onEdit: null,
          onExport: () => _exportNote(detail),
          onDelete: null,
        ),
      );
    }
  }

  /// Restores a persisted auth session if one exists. Validates the token
  /// against the backend via `/auth/session/`; if the token is stale the
  /// persisted session is cleared.
  Future<void> _restoreSession() async {
    final session = await _LocalAppStore.loadSession();
    if (session == null) return;
    final token = session['token']?.toString() ?? '';
    if (token.isEmpty) return;
    try {
      final check = await widget.client.checkSession(token);
      if (check['authenticated'] == true) {
        await _applyAuthPayload(check);
        return;
      }
    } catch (_) {
      // Token invalid or network down — fall through and clear.
    }
    await _LocalAppStore.clearSession();
  }
}
