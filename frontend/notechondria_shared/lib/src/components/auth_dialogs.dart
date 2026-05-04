import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_shell/url_strategy.dart'
    if (dart.library.html) '../app_shell/url_strategy_web.dart' as url_strategy;
import '../models/action_feedback.dart';
import '../utils/blur_dialog.dart';
import 'phased_status.dart';

/// Formats the login dialog's API-host subtitle. Accepts the full
/// `api_base_url` (may include `/api/v1`) and returns `Signing in to
/// <host>` so the user can verify they're hitting the right backend
/// before typing credentials.
String _apiHostSubtitle(String? apiBaseUrl) {
  final raw = (apiBaseUrl ?? '').trim();
  if (raw.isEmpty) return '';
  try {
    final parsed = Uri.parse(raw);
    final host = parsed.hasAuthority ? parsed.authority : raw;
    return 'Signing in to $host';
  } catch (_) {
    return 'Signing in to $raw';
  }
}

/// Compact auth hub. After the 0.1.103 cutover, the only in-app
/// auth surface is email + password Login; sign-up and password
/// reset both live on the Casdoor side. The hub renders three
/// CTAs in priority order:
///
/// 1. **Continue with Casdoor SSO** — OAuth code flow via
///    [AppShellOAuthMixin.launchOAuth]. Auto-redirects back. The
///    fast path. Shown only when `onCasdoorLogin != null`
///    (backend is in shadow mode otherwise).
/// 2. **Login via third party** — direct browser navigation to the
///    Casdoor org-login page (`casdoorOrgLoginUrl`). Shown only
///    when that URL is non-empty. Use this when the user wants to
///    pick a provider from Casdoor's hosted UI (Google / GitHub /
///    etc., configured on the Casdoor application's Providers tab).
/// 3. **Email / password fallback** — collapsed behind an expander
///    so it doesn't compete with the Casdoor CTAs. The legacy
///    `onLogin` callback still talks to the Notechondria backend
///    for un-migrated accounts. Sign-up and password reset are
///    intentionally absent — both are owned by Casdoor now.
class AuthHub extends StatelessWidget {
  const AuthHub({
    super.key,
    required this.onLogin,
    this.onCasdoorLogin,
    this.casdoorOrgLoginUrl,
    this.apiBaseUrl,
  });

  /// The currently-configured API base URL. The login dialog shows its
  /// host as a subtitle so the user can confirm which backend they're
  /// signing into before typing credentials.
  final String? apiBaseUrl;

  /// Submits an email + password pair to the legacy
  /// `/api/v1/auth/login/` endpoint. The only in-app credential path
  /// that survives the 0.1.103 cutover.
  final Future<ActionFeedback> Function(String email, String password) onLogin;

  /// Triggers the Casdoor SSO redirect (AppShellOAuthMixin's
  /// `launchOAuth('casdoor', intent: 'login')`). Null when the
  /// backend is in shadow mode (no `CASDOOR_*` env vars set).
  final VoidCallback? onCasdoorLogin;

  /// Casdoor org-login page URL, e.g.
  /// `https://auth.trance-0.com/login/notechondria`. Built from the
  /// `endpoint` + `organization` fields returned by
  /// `/api/v1/auth/casdoor/config/`. Backs both the "Login via third
  /// party" button and the "Sign up via Casdoor" link. When null,
  /// both surfaces collapse and the user only sees the OAuth pill +
  /// email/password fallback.
  final String? casdoorOrgLoginUrl;

  Future<void> _openDialog(BuildContext context, Widget dialog) {
    return showBlurDialog<void>(
      context: context,
      child: dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _AuthHubBody(
          apiBaseUrl: apiBaseUrl,
          onLogin: onLogin,
          onCasdoorLogin: onCasdoorLogin,
          casdoorOrgLoginUrl: casdoorOrgLoginUrl,
          openDialog: _openDialog,
        ),
      ),
    );
  }
}

/// Stateful body for [AuthHub]. Owns the "show legacy options"
/// expander state. When `onCasdoorLogin` is non-null, Casdoor is the
/// primary call-to-action and the legacy email/password + Google /
/// GitHub buttons collapse behind a "Use email / password instead"
/// expander so users with un-migrated accounts can still get in.
class _AuthHubBody extends StatefulWidget {
  const _AuthHubBody({
    required this.openDialog,
    required this.onLogin,
    this.onCasdoorLogin,
    this.casdoorOrgLoginUrl,
    this.apiBaseUrl,
  });

  final String? apiBaseUrl;
  final Future<void> Function(BuildContext, Widget) openDialog;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  final VoidCallback? onCasdoorLogin;
  final String? casdoorOrgLoginUrl;

  @override
  State<_AuthHubBody> createState() => _AuthHubBodyState();
}

class _AuthHubBodyState extends State<_AuthHubBody> {
  bool _showLegacy = false;

  void _openLogin(BuildContext context) {
    widget.openDialog(
      context,
      EmailPasswordDialog(
        title: 'Login',
        description: _apiHostSubtitle(widget.apiBaseUrl),
        submitLabel: 'Login',
        emailLabel: 'Email or username',
        onSubmit: widget.onLogin,
      ),
    );
  }

  void _openCasdoorBrowserLogin() {
    final url = widget.casdoorOrgLoginUrl;
    if (url == null || url.isEmpty) return;
    url_strategy.browserRedirect(url);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final casdoorPrimary = widget.onCasdoorLogin != null;
    final casdoorBrowserUrl = widget.casdoorOrgLoginUrl ?? '';
    final hasBrowserLogin = casdoorBrowserUrl.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Account', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          casdoorPrimary
              ? 'Sign in via the Notechondria SSO. Account creation '
                  'and password reset are handled on the Casdoor side; '
                  'use the link below to register or contact the '
                  'administrator if your password needs to be reset.'
              : 'Sign in with your existing account. Account creation '
                  'and password resets have moved to the Casdoor SSO; '
                  'contact the administrator if you cannot sign in.',
        ),
        const SizedBox(height: 16),
        if (casdoorPrimary) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: widget.onCasdoorLogin,
              icon: const Icon(Icons.shield_outlined, size: 20),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Continue with Casdoor SSO'),
              ),
            ),
          ),
        ],
        if (hasBrowserLogin) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openCasdoorBrowserLogin,
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Login via third party'),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openCasdoorBrowserLogin,
              icon: const Icon(Icons.person_add_alt_outlined, size: 18),
              label: const Text('No account? Sign up via Casdoor'),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showLegacy = !_showLegacy),
            icon: Icon(
              _showLegacy ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(
              _showLegacy
                  ? 'Hide email / password fallback'
                  : 'Use email / password instead',
            ),
          ),
        ),
        if (_showLegacy) ...[
          const Divider(),
          OutlinedButton(
            onPressed: () => _openLogin(context),
            child: const Text('Login'),
          ),
          const SizedBox(height: 6),
          Text(
            'Forgot password? Contact the administrator to reset it. '
            'Self-service password reset has moved to Casdoor for '
            'accounts that have been migrated.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class EmailPasswordDialog extends StatefulWidget {
  const EmailPasswordDialog({
    super.key,
    required this.title,
    required this.description,
    required this.submitLabel,
    required this.onSubmit,
    this.emailLabel = 'Email',
  });

  final String title;
  final String description;
  final String submitLabel;
  final Future<ActionFeedback> Function(String email, String password) onSubmit;
  final String emailLabel;

  @override
  State<EmailPasswordDialog> createState() => _EmailPasswordDialogState();
}

class _EmailPasswordDialogState extends State<EmailPasswordDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // Phased progress for the submit Future. We can't observe the backend
  // directly (onSubmit is a single Future handed to us), so we advance
  // the label on client-visible boundaries (before await, right after
  // await returns) and on a soft 2-second fallback that names the wait
  // as "Waiting for backend response" once the network call drags.
  final ValueNotifier<String> _phase = ValueNotifier<String>('');
  Timer? _phaseFallback;
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _phaseFallback?.cancel();
    _phase.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    // Seed the first phase synchronously so the user sees a label the
    // instant they tap the button. The second phase is scheduled for
    // ~2s in — if the network call returns sooner, we cancel the bump.
    _phase.value = 'Sending request to backend';
    _phaseFallback?.cancel();
    _phaseFallback = Timer(const Duration(seconds: 2), () {
      if (mounted && _submitting) {
        _phase.value = 'Waiting for backend response';
      }
    });
    final ActionFeedback feedback;
    try {
      feedback =
          await widget.onSubmit(_emailController.text, _passwordController.text);
    } finally {
      _phaseFallback?.cancel();
      _phaseFallback = null;
    }
    if (!mounted) {
      return;
    }
    _phase.value = 'Applying response';
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    _phase.value = '';
    if (!feedback.isError && widget.title == 'Login') {
      // Signal the browser that this autofill context finished successfully.
      // Chrome needs a brief delay between finishAutofillContext and the DOM
      // removal (dialog close) to capture the credentials and show the
      // "Save password?" prompt.
      TextInput.finishAutofillContext();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description.isNotEmpty) ...[
              Text(widget.description),
              const SizedBox(height: 16),
            ],
            AutofillGroup(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _emailController,
                    autofillHints: const [AutofillHints.username],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: widget.emailLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submitting ? null : _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            if (_submitting) ...[
              const SizedBox(height: 16),
              // Replaces the spinner with a phased status line that
              // names the current async step and counts the seconds
              // spent on it. The 2-second soft fallback above flips
              // the label from "Sending request to backend" to
              // "Waiting for backend response" so the user can tell
              // which half of the wait they're in.
              Center(child: PhasedStatusIndicator(phase: _phase)),
            ],
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              FeedbackText(feedback: _feedback!),
            ],
          ],
        ),
      ),
      actions: [
        // Always enabled so the user can abort an in-flight login
        // (network hang, slow cold-start backend, typo realised
        // mid-submit). Popping the dialog makes the in-flight
        // onSubmit's result a no-op because _submit guards on
        // `mounted` after the await returns.
        TextButton(
          onPressed: () {
            _phaseFallback?.cancel();
            _phaseFallback = null;
            Navigator.of(context).pop();
          },
          child: Text(_submitting ? 'Cancel' : 'Close'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Working...' : widget.submitLabel),
        ),
      ],
    );
  }
}

class EmailCodeDialog extends StatefulWidget {
  const EmailCodeDialog({
    super.key,
    required this.title,
    required this.description,
    required this.submitLabel,
    required this.onSubmit,
    this.onResend,
  });

  final String title;
  final String description;
  final String submitLabel;
  final Future<ActionFeedback> Function(String email, String code) onSubmit;
  final Future<ActionFeedback> Function(String email)? onResend;

  @override
  State<EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<EmailCodeDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _resend() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() {
        _feedback = const ActionFeedback(
          message: 'Verification code not resent: '
              'Shared.AuthDialog/verify.resend \u2014 '
              'email field is empty; enter an email to resend to.',
          isError: true,
        );
      });
      return;
    }
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await widget.onResend!(email);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    if (!feedback.isError) _startCooldown();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback =
        await widget.onSubmit(_emailController.text, _codeController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    if (!feedback.isError) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.description),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitting ? null : _submit(),
              decoration: const InputDecoration(
                labelText: '6-digit code',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.onResend != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed:
                      _submitting || _resendCooldown > 0 ? null : _resend,
                  child: Text(
                    _resendCooldown > 0
                        ? 'Resend code (${_resendCooldown}s)'
                        : 'Resend code',
                  ),
                ),
              ),
            ],
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              FeedbackText(feedback: _feedback!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Working...' : widget.submitLabel),
        ),
      ],
    );
  }
}

class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog({
    super.key,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
  });

  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(
    String email,
    String code,
    String password,
  ) onConfirmPasswordReset;

  @override
  State<PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<ActionFeedback> Function() action, {
    bool closeOnSuccess = false,
  }) async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    if (closeOnSuccess && !feedback.isError) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forgot password'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request a 6-digit reset code, then set a new password.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _submitting
                    ? null
                    : () => _run(
                          () => widget
                              .onRequestPasswordReset(_emailController.text),
                        ),
                child: Text(_submitting ? 'Working...' : 'Send reset code'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '6-digit reset code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                FeedbackText(feedback: _feedback!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _submitting
              ? null
              : () {
                  if (_passwordController.text !=
                      _confirmPasswordController.text) {
                    setState(() {
                      _feedback = const ActionFeedback(
                        message: 'Password not updated: '
                            'Shared.AuthDialog/password.reset.confirm \u2014 '
                            'new password and confirmation do not match.',
                        isError: true,
                      );
                    });
                    return;
                  }
                  _run(
                    () => widget.onConfirmPasswordReset(
                      _emailController.text,
                      _codeController.text,
                      _passwordController.text,
                    ),
                    closeOnSuccess: true,
                  );
                },
          child: Text(_submitting ? 'Working...' : 'Update password'),
        ),
      ],
    );
  }
}

/// Inline feedback text for form submissions.
class FeedbackText extends StatelessWidget {
  const FeedbackText({super.key, required this.feedback});

  final ActionFeedback feedback;

  @override
  Widget build(BuildContext context) {
    return Text(
      feedback.message,
      style: TextStyle(
        color: feedback.isError
            ? const Color(0xFFB91C1C)
            : const Color(0xFF166534),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
