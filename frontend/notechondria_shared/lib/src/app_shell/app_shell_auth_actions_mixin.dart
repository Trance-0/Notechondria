import 'package:flutter/widgets.dart';

import '../models/action_feedback.dart';
import 'auth_client.dart';

/// Authentication action helpers shared across editor / planner /
/// portal apps. Post-0.1.106 cleanup, the only in-app credential
/// surface is email + password Login (legacy accounts) — sign-up,
/// password reset, and email verification all live on the Casdoor
/// side at `auth.trance-0.com`.
///
/// `login` bounces through `applyAuthPayload` (supplied by the
/// subclass via `AppShellSessionMixin`) to swap the full session
/// bucket. No direct state mutation here, so no `refreshState()`
/// call is needed.
///
/// `logAppTag` — e.g. `'Editor'` / `'Planner'` / `'Portal'` — is
/// prefixed to every log-source string so the debug terminal shows
/// which app emitted each line.
mixin AppShellAuthActionsMixin<W extends StatefulWidget> on State<W> {
  AuthClient get authClient;

  /// App tag prefixed to every log `source`. Editor / planner /
  /// portal each override this with their short name. Used as
  /// `'$logAppTag.Auth/login'` etc.
  String get logAppTag;

  /// Full-session handoff called after a successful login response.
  Future<void> applyAuthPayload(Map<String, dynamic> payload);

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
}
