part of notechondria_frontend;

/// Compact auth hub with sign-up, verify, login, and password-reset dialogs.
class _AuthHub extends StatelessWidget {
  const _AuthHub({
    required this.onRegister,
    required this.onVerify,
    required this.onLogin,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
  });

  final Future<ActionFeedback> Function(String email, String password)
      onRegister;
  final Future<ActionFeedback> Function(String email, String code) onVerify;
  final Future<ActionFeedback> Function(String email, String password) onLogin;
  final Future<ActionFeedback> Function(String email) onRequestPasswordReset;
  final Future<ActionFeedback> Function(
    String email,
    String code,
    String password,
  ) onConfirmPasswordReset;

  Future<void> _openDialog(BuildContext context, Widget dialog) {
    return showDialog<void>(
      context: context,
      builder: (context) => dialog,
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
              'Use small dialogs for sign up, verification, login, and password reset.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => _openDialog(
                    context,
                    _EmailPasswordDialog(
                      title: 'Sign up',
                      description:
                          'Create an account with email and password. Verification code arrives by email or server log fallback.',
                      submitLabel: 'Create account',
                      onSubmit: onRegister,
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
                          'Enter the verification code sent to your email.',
                      submitLabel: 'Verify',
                      onSubmit: onVerify,
                    ),
                  ),
                  child: const Text('Verify email'),
                ),
                OutlinedButton(
                  onPressed: () => _openDialog(
                    context,
                    _EmailPasswordDialog(
                      title: 'Login',
                      // Empty description: the previous helper text about
                      // admin usernames was redundant and hogged mobile
                      // screen space, leaving no room for the soft keyboard.
                      description: '',
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
          ],
        ),
      ),
    );
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
      // Signals the platform/browser that this autofill context finished
      // successfully, which is what triggers Chrome's "Save password?" prompt
      // on web. Without this the dialog pops before the browser associates
      // the submission with the credential form, so the prompt never fires.
      TextInput.finishAutofillContext();
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
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
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
  });

  final String title;
  final String description;
  final String submitLabel;
  final Future<ActionFeedback> Function(String email, String code) onSubmit;

  @override
  State<_EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<_EmailCodeDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
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
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Code',
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
  ActionFeedback? _feedback;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Request a reset code, then set a new password in the same dialog.',
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
              decoration: const InputDecoration(
                labelText: 'Reset code',
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
          onPressed: _submitting
              ? null
              : () => _run(
                    () => widget.onConfirmPasswordReset(
                      _emailController.text,
                      _codeController.text,
                      _passwordController.text,
                    ),
                    closeOnSuccess: true,
                  ),
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
