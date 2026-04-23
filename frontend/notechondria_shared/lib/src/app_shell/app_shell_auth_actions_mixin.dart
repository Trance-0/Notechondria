import 'package:flutter/widgets.dart';

import '../models/action_feedback.dart';
import 'auth_client.dart';

/// Authentication action helpers shared across editor / planner /
/// portal apps. Each method wraps an `authClient` call and returns
/// `ActionFeedback` suitable for the settings / login panels.
///
/// `verify` and `login` bounce through `applyAuthPayload` (supplied
/// by the subclass via `AppShellSessionMixin`, landing in a later
/// step) to swap the full session bucket. No direct state mutation
/// here, so no `refreshState()` call is needed.
///
/// `logAppTag` — e.g. `'Editor'` / `'Planner'` / `'Portal'` — is
/// prefixed to every log-source string so the debug terminal shows
/// which app emitted each line. The sub-tags (`Auth/register`,
/// `Auth/login`, ...) are fixed across all apps.
///
/// Usage:
///   class _AppShellState extends State<AppShell>
///       with AppShellLogMixin<AppShell>,
///            AppShellAuthActionsMixin<AppShell> {
///     @override
///     AuthClient get authClient => widget.client;
///     @override
///     String get logAppTag => 'Editor';
///     @override
///     Future<void> applyAuthPayload(Map<String, dynamic> payload) {
///       // full-session handoff; lives on _AppShellState until the
///       // session mixin lands.
///     }
///   }
mixin AppShellAuthActionsMixin<W extends StatefulWidget> on State<W> {
  AuthClient get authClient;

  /// App tag prefixed to every log `source`. Editor / planner /
  /// portal each override this with their short name. Used as
  /// `'$logAppTag.Auth/register'` etc.
  String get logAppTag;

  /// Full-session handoff called after a successful login or
  /// verification response. The implementation lives on
  /// `_AppShellState` (or will move into `AppShellSessionMixin` in a
  /// later step); here we just await it.
  Future<void> applyAuthPayload(Map<String, dynamic> payload);

  Future<ActionFeedback> register(
    String username,
    String email,
    String password, {
    String invitationCode = '',
  }) async {
    try {
      final result = await authClient.register(
        username,
        email,
        password,
        invitationCode: invitationCode,
      );
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Registration queued: $logAppTag.Auth/register — $serverMessage'
              : 'Registration queued: $logAppTag.Auth/register — '
                  'verification email sent to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message:
              'Registration rejected: $logAppTag.Auth/register — $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> verify(String email, String code) async {
    try {
      final result = await authClient.verifyEmail(email, code);
      await applyAuthPayload(result);
      return ActionFeedback(
          message:
              'Signed in: $logAppTag.Auth/verify — email verified and '
              'session issued.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message:
              'Email verification failed: $logAppTag.Auth/verify — $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> resendVerification(String email) async {
    try {
      final result = await authClient.resendVerification(email);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Verification code resent: '
                  '$logAppTag.Auth/resend_verification — $serverMessage'
              : 'Verification code resent: '
                  '$logAppTag.Auth/resend_verification — delivery '
                  'queued to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Verification code not resent: '
              '$logAppTag.Auth/resend_verification — $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> login(String email, String password) async {
    try {
      final result = await authClient.login(email, password);
      await applyAuthPayload(result);
      return ActionFeedback(
          message: 'Signed in: $logAppTag.Auth/login — '
              'server accepted credentials.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Sign-in rejected: $logAppTag.Auth/login — $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> requestPasswordReset(String email) async {
    try {
      final result = await authClient.requestPasswordReset(email);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Password reset email queued: '
                  '$logAppTag.Auth/password.reset.request — $serverMessage'
              : 'Password reset email queued: '
                  '$logAppTag.Auth/password.reset.request — sent to $email.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Password reset email not sent: '
              '$logAppTag.Auth/password.reset.request — $cause',
          isError: true);
    }
  }

  Future<ActionFeedback> confirmPasswordReset(
      String email, String code, String password) async {
    try {
      final result =
          await authClient.confirmPasswordReset(email, code, password);
      final serverMessage = result['message']?.toString();
      return ActionFeedback(
          message: serverMessage != null && serverMessage.isNotEmpty
              ? 'Password updated: '
                  '$logAppTag.Auth/password.reset.confirm — $serverMessage'
              : 'Password updated: '
                  '$logAppTag.Auth/password.reset.confirm — '
                  'server accepted reset code.');
    } catch (error) {
      final cause = error.toString().replaceFirst('Exception: ', '');
      return ActionFeedback(
          message: 'Password not updated: '
              '$logAppTag.Auth/password.reset.confirm — $cause',
          isError: true);
    }
  }
}
