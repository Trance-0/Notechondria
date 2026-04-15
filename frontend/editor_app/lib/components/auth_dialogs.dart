part of notechondria_frontend;

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

/// Compact auth hub with sign-up, verify, login, and password-reset dialogs.
class _AuthHub extends StatelessWidget {
  const _AuthHub({
    required this.onRegister,
    required this.onValidateInvitation,
    required this.onVerify,
    required this.onResendVerification,
    required this.onLogin,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
    this.onGoogleLogin,
    this.onGithubLogin,
    this.onGoogleLoginOnly,
    this.onGithubLoginOnly,
    this.apiBaseUrl,
  });

  /// The currently-configured API base URL. The login dialog shows its
  /// host as a subtitle so the user can confirm which backend they're
  /// signing into before typing credentials.
  final String? apiBaseUrl;

  final Future<ActionFeedback> Function(
    String username,
    String email,
    String password, {
    String invitationCode,
  }) onRegister;
  final Future<Map<String, dynamic>> Function(String code) onValidateInvitation;
  final Future<ActionFeedback> Function(String email, String code) onVerify;
  final Future<ActionFeedback> Function(String email) onResendVerification;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(
    String email,
    String code,
    String password,
  ) onConfirmPasswordReset;
  final void Function(String invitationCode)? onGoogleLogin;
  final void Function(String invitationCode)? onGithubLogin;
  final VoidCallback? onGoogleLoginOnly;
  final VoidCallback? onGithubLoginOnly;

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
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Sign up, verify your email, log in, or reset your password.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => _openDialog(
                    context,
                    _RegistrationWizard(
                      onValidateInvitation: onValidateInvitation,
                      onRegister: onRegister,
                      onResendVerification: onResendVerification,
                      onGoogleLogin: onGoogleLogin,
                      onGithubLogin: onGithubLogin,
                    ),
                  ),
                  child: const Text('Sign up'),
                ),
                OutlinedButton(
                  onPressed: () => _openDialog(
                    context,
                    _EmailCodeDialog(
                      title: 'Verify email',
                      description:
                          'Enter the 6-digit verification code sent to your email.',
                      submitLabel: 'Verify',
                      onSubmit: onVerify,
                      onResend: onResendVerification,
                    ),
                  ),
                  child: const Text('Verify email'),
                ),
                OutlinedButton(
                  onPressed: () => _openDialog(
                    context,
                    _EmailPasswordDialog(
                      title: 'Login',
                      description: _apiHostSubtitle(apiBaseUrl),
                      submitLabel: 'Login',
                      emailLabel: 'Email or username',
                      onSubmit: onLogin,
                    ),
                  ),
                  child: const Text('Login'),
                ),
                TextButton(
                  onPressed: () => _openDialog(
                    context,
                    _PasswordResetDialog(
                      onRequestPasswordReset: onRequestPasswordReset,
                      onConfirmPasswordReset: onConfirmPasswordReset,
                    ),
                  ),
                  child: const Text('Forgot password'),
                ),
              ],
            ),
            if (onGoogleLoginOnly != null || onGithubLoginOnly != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),
              Text('Or sign in with', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (onGoogleLoginOnly != null)
                    OutlinedButton.icon(
                      onPressed: onGoogleLoginOnly,
                      icon: const Icon(Icons.g_mobiledata, size: 20),
                      label: const Text('Google'),
                    ),
                  if (onGithubLoginOnly != null)
                    OutlinedButton.icon(
                      onPressed: onGithubLoginOnly,
                      icon: const Icon(Icons.code, size: 20),
                      label: const Text('GitHub'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Multi-step registration wizard.
///
/// Step 0 – Invitation code (skipped automatically when no codes exist).
/// Step 1 – Choose registration method: Email, Google, or GitHub.
/// Step 2 – Email registration form (username, email + verify, password).
class _RegistrationWizard extends StatefulWidget {
  const _RegistrationWizard({
    required this.onValidateInvitation,
    required this.onRegister,
    required this.onResendVerification,
    this.onGoogleLogin,
    this.onGithubLogin,
  });

  final Future<Map<String, dynamic>> Function(String code) onValidateInvitation;
  final Future<ActionFeedback> Function(
    String username,
    String email,
    String password, {
    String invitationCode,
  }) onRegister;
  final Future<ActionFeedback> Function(String email) onResendVerification;
  final void Function(String invitationCode)? onGoogleLogin;
  final void Function(String invitationCode)? onGithubLogin;

  @override
  State<_RegistrationWizard> createState() => _RegistrationWizardState();
}

class _RegistrationWizardState extends State<_RegistrationWizard> {
  int _step = 0; // 0=invitation, 1=method, 2=email form
  final _invitationController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _verifyCodeController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;
  String _validatedInvitationCode = '';
  bool _emailRegistered = false; // true after register succeeds, show verify
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _invitationController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _verifyCodeController.dispose();
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

  Future<void> _validateInvitation() async {
    final code = _invitationController.text.trim();
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    try {
      final result = await widget.onValidateInvitation(code);
      if (!mounted) return;
      final required = result['required'] == true;
      final valid = result['valid'] == true;
      if (!required) {
        // No invitation codes in system — skip straight to method selection.
        setState(() {
          _submitting = false;
          _validatedInvitationCode = '';
          _step = 1;
        });
        return;
      }
      if (valid) {
        setState(() {
          _submitting = false;
          _validatedInvitationCode = code;
          _step = 1;
        });
      } else {
        setState(() {
          _submitting = false;
          _feedback = const ActionFeedback(
            message: 'Invalid or expired invitation code.',
            isError: true,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _feedback = ActionFeedback(
          message: e.toString().replaceFirst('Exception: ', ''),
          isError: true,
        );
      });
    }
  }

  String? _validateEmailForm() {
    if (_usernameController.text.trim().isEmpty) {
      return 'Username is required.';
    }
    if (_emailController.text.trim().isEmpty) {
      return 'Email is required.';
    }
    final pw = _passwordController.text;
    if (pw.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    final hasUpper = pw.contains(RegExp(r'[A-Z]'));
    final hasLower = pw.contains(RegExp(r'[a-z]'));
    final hasDigitOrSpecial = pw.contains(RegExp(r'[^a-zA-Z]'));
    if (!hasUpper || !hasLower || !hasDigitOrSpecial) {
      return 'Password needs uppercase, lowercase, and a digit or special character.';
    }
    if (pw != _confirmPasswordController.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _submitEmailRegistration() async {
    final error = _validateEmailForm();
    if (error != null) {
      setState(() {
        _feedback = ActionFeedback(message: error, isError: true);
      });
      return;
    }
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await widget.onRegister(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _passwordController.text,
      invitationCode: _validatedInvitationCode,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _feedback = feedback;
      if (!feedback.isError) {
        _emailRegistered = true;
      }
    });
    if (!feedback.isError) _startCooldown();
  }

  Future<void> _resendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback = await widget.onResendVerification(email);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
    if (!feedback.isError) _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_stepTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_step == 0) _buildInvitationStep(),
              if (_step == 1) _buildMethodStep(),
              if (_step == 2) _buildEmailFormStep(),
              if (_feedback != null) ...[
                const SizedBox(height: 12),
                _FeedbackText(feedback: _feedback!),
              ],
            ],
          ),
        ),
      ),
      actions: _buildActions(),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Invitation code';
      case 1:
        return 'Choose sign-up method';
      case 2:
        return _emailRegistered ? 'Verify your email' : 'Create account';
      default:
        return 'Sign up';
    }
  }

  Widget _buildInvitationStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Enter an invitation code to continue registration.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _invitationController,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitting ? null : _validateInvitation(),
          decoration: const InputDecoration(
            labelText: 'Invitation code',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('How would you like to register?'),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => setState(() {
              _step = 2;
              _feedback = null;
            }),
            icon: const Icon(Icons.email_outlined),
            label: const Text('Register with email'),
          ),
        ),
        if (widget.onGoogleLogin != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                widget.onGoogleLogin!(_validatedInvitationCode);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.g_mobiledata, size: 22),
              label: const Text('Continue with Google'),
            ),
          ),
        ],
        if (widget.onGithubLogin != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                widget.onGithubLogin!(_validatedInvitationCode);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.code, size: 18),
              label: const Text('Continue with GitHub'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmailFormStep() {
    if (_emailRegistered) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A 6-digit verification code was sent to ${_emailController.text.trim()}. '
            'Enter it on the "Verify email" dialog to activate your account.',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed:
                  _submitting || _resendCooldown > 0 ? null : _resendCode,
              child: Text(
                _resendCooldown > 0
                    ? 'Resend code (${_resendCooldown}s)'
                    : 'Resend code',
              ),
            ),
          ),
        ],
      );
    }
    return AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A verification code will be sent to your email after registration.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            autofillHints: const [AutofillHints.newUsername],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Username',
              helperText: 'Letters, numbers, hyphens, underscores.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Password',
              helperText: 'Min 8 chars, uppercase + lowercase + digit/special.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) =>
                _submitting ? null : _submitEmailRegistration(),
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    switch (_step) {
      case 0:
        return [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: _submitting ? null : _validateInvitation,
            child: Text(_submitting ? 'Checking...' : 'Confirm'),
          ),
        ];
      case 1:
        return [
          TextButton(
            onPressed: () => setState(() {
              _step = 0;
              _feedback = null;
            }),
            child: const Text('Back'),
          ),
        ];
      case 2:
        if (_emailRegistered) {
          return [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ];
        }
        return [
          TextButton(
            onPressed: _submitting
                ? null
                : () => setState(() {
                      _step = 1;
                      _feedback = null;
                    }),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: _submitting ? null : _submitEmailRegistration,
            child: Text(_submitting ? 'Creating...' : 'Register'),
          ),
        ];
      default:
        return [];
    }
  }
}

class _EmailPasswordDialog extends StatefulWidget {
  const _EmailPasswordDialog({
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
  State<_EmailPasswordDialog> createState() => _EmailPasswordDialogState();
}

class _EmailPasswordDialogState extends State<_EmailPasswordDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _feedback = null;
    });
    final feedback =
        await widget.onSubmit(_emailController.text, _passwordController.text);
    if (!mounted) {
      return;
    }
    setState(() {
      _submitting = false;
      _feedback = feedback;
    });
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
              const Center(child: CircularProgressIndicator()),
            ],
            if (_feedback != null) ...[
              const SizedBox(height: 12),
              _FeedbackText(feedback: _feedback!),
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

class _EmailCodeDialog extends StatefulWidget {
  const _EmailCodeDialog({
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
  State<_EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<_EmailCodeDialog> {
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
          message: 'Enter your email first.',
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
              _FeedbackText(feedback: _feedback!),
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

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog({
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
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
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
                _FeedbackText(feedback: _feedback!),
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
                        message: 'Passwords do not match.',
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
class _FeedbackText extends StatelessWidget {
  const _FeedbackText({required this.feedback});

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
