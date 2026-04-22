part of notechondria_frontend;

/// Authentication action helpers. Each method wraps a `widget.client`
/// call and returns `ActionFeedback` for the settings/login panels.
/// `_verify` and `_login` bounce through `_applyAuthPayload` (stays on
/// `_AppShellState`) to swap the full session bucket. No direct state
/// mutation here, so no `_refresh()` call is needed. Extracted from
/// `app_shell.dart` so that file stays closer to the AGENTS.md §1.5
/// 1000-line ceiling.
extension _AppShellAuthActionsX on _AppShellState {
  Future<ActionFeedback> _register(
    String username,
    String email,
    String password, {
    String invitationCode = '',
  }) async {
    try {
      final result = await widget.client.register(
        username,
        email,
        password,
        invitationCode: invitationCode,
      );
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Registration queued: Editor.Auth/register \u2014 $serverMessage'
              : 'Registration queued: Editor.Auth/register \u2014 '
                  'verification email sent to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message:
              'Registration rejected: Editor.Auth/register \u2014 $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> _verify(String email, String code) async {
    try {
      final result = await widget.client.verifyEmail(email, code);
      await _applyAuthPayload(result);
      return const ActionFeedback(
          message:
              'Signed in: Editor.Auth/verify \u2014 email verified and '
              'session issued.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Email verification failed: Editor.Auth/verify \u2014 $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> _resendVerification(String email) async {
    try {
      final result = await widget.client.resendVerification(email);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Verification code resent: '
                  'Editor.Auth/resend_verification \u2014 $serverMessage'
              : 'Verification code resent: '
                  'Editor.Auth/resend_verification \u2014 delivery queued '
                  'to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Verification code not resent: '
              'Editor.Auth/resend_verification \u2014 $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> _login(String email, String password) async {
    try {
      final result = await widget.client.login(email, password);
      await _applyAuthPayload(result);
      return const ActionFeedback(
          message: 'Signed in: Editor.Auth/login \u2014 '
              'server accepted credentials.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Sign-in rejected: Editor.Auth/login \u2014 $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> _requestPasswordReset(String email) async {
    try {
      final result = await widget.client.requestPasswordReset(email);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Password reset email queued: '
                  'Editor.Auth/password.reset.request \u2014 $serverMessage'
              : 'Password reset email queued: '
                  'Editor.Auth/password.reset.request \u2014 sent to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Password reset email not sent: '
              'Editor.Auth/password.reset.request \u2014 $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> _confirmPasswordReset(
      String email, String code, String password) async {
    try {
      final result =
          await widget.client.confirmPasswordReset(email, code, password);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Password updated: '
                  'Editor.Auth/password.reset.confirm \u2014 $serverMessage'
              : 'Password updated: '
                  'Editor.Auth/password.reset.confirm \u2014 '
                  'server accepted reset code.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Password not updated: '
              'Editor.Auth/password.reset.confirm \u2014 $cause',
          isError: true);
    }
  }
}
