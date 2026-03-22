part of notechondria_frontend;

/// Settings module for account controls, theme, API endpoint, and diagnostics.
class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.profile,
    required this.settings,
    required this.onSave,
    required this.onLogout,
    required this.onRegister,
    required this.onVerify,
    required this.onLogin,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
    required this.calendarFeeds,
    required this.courses,
    required this.onToggleCalendarFeed,
    required this.onDeleteCalendarFeed,
    required this.uiLogs,
    this.apiBaseUrl,
    this.debugSnapshotListenable,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? settings;
  final Future<ActionFeedback> Function(
    String username,
    String email,
    String motto,
    String socialLink,
    String editorMode,
    String themePreset,
    String themeMode,
    String apiBaseUrl,
  ) onSave;
  final Future<void> Function() onLogout;
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
  final List<Map<String, dynamic>> calendarFeeds;
  final List<Map<String, dynamic>> courses;
  final Future<void> Function(Map<String, dynamic> feed, bool enabled)
      onToggleCalendarFeed;
  final Future<void> Function(Map<String, dynamic> feed) onDeleteCalendarFeed;
  final List<String> uiLogs;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _mottoController;
  late final TextEditingController _socialController;
  late final TextEditingController _apiBaseController;
  String _editorMode = 'P';
  String _themePreset = 'teal';
  String _themeMode = 'S';
  ActionFeedback? _saveFeedback;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.settings?['username']?.toString() ??
          widget.profile?['username']?.toString() ??
          '',
    );
    _emailController = TextEditingController(
      text: widget.settings?['email']?.toString() ??
          widget.profile?['email']?.toString() ??
          '',
    );
    _mottoController = TextEditingController(
      text: widget.settings?['motto']?.toString() ?? '',
    );
    _socialController = TextEditingController(
      text: widget.settings?['social_link']?.toString() ?? '',
    );
    _apiBaseController = TextEditingController(
      text: widget.settings?['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          'http://localhost:9080/api/v1',
    );
    _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
    _themePreset = widget.settings?['theme_preset']?.toString() ?? 'teal';
    _themeMode = widget.settings?['theme_mode']?.toString() ?? 'S';
  }

  @override
  void didUpdateWidget(covariant _SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _usernameController.text = widget.settings?['username']?.toString() ??
          widget.profile?['username']?.toString() ??
          '';
      _emailController.text = widget.settings?['email']?.toString() ??
          widget.profile?['email']?.toString() ??
          '';
      _mottoController.text = widget.settings?['motto']?.toString() ?? '';
      _socialController.text =
          widget.settings?['social_link']?.toString() ?? '';
      _apiBaseController.text = widget.settings?['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          'http://localhost:9080/api/v1';
      _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
      _themePreset = widget.settings?['theme_preset']?.toString() ?? 'teal';
      _themeMode = widget.settings?['theme_mode']?.toString() ?? 'S';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _mottoController.dispose();
    _socialController.dispose();
    _apiBaseController.dispose();
    super.dispose();
  }

  /// Persists the editable settings values and surfaces inline feedback.
  Future<void> _submitSettings() async {
    setState(() {
      _saving = true;
      _saveFeedback = null;
    });
    final feedback = await widget.onSave(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _mottoController.text.trim(),
      _socialController.text.trim(),
      _editorMode,
      _themePreset,
      _themeMode,
      _apiBaseController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _saveFeedback = feedback;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.profile == null || widget.settings == null) ...[
          const Text(
            'Use this tab to register, verify email, and log in. Course materials remain available without an account.',
          ),
          const SizedBox(height: 16),
          _AuthHub(
            onRegister: widget.onRegister,
            onVerify: widget.onVerify,
            onLogin: widget.onLogin,
            onRequestPasswordReset: widget.onRequestPasswordReset,
            onConfirmPasswordReset: widget.onConfirmPasswordReset,
          ),
        ] else ...[
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundImage:
                    (widget.profile?['image_url']?.toString() ?? '').isNotEmpty
                        ? NetworkImage(widget.profile!['image_url'].toString())
                        : null,
                child: (widget.profile?['image_url']?.toString() ?? '').isEmpty
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.profile?['username']?.toString() ??
                        widget.profile?['email']?.toString() ??
                        '',
                  ),
                  subtitle: const Text('Verified account'),
                ),
              ),
            ],
          ),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mottoController,
            decoration: const InputDecoration(
              labelText: 'Motto',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _socialController,
            decoration: const InputDecoration(
              labelText: 'Social link',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _editorMode,
            items: const [
              DropdownMenuItem(value: 'G', child: Text('GFM live preview')),
              DropdownMenuItem(value: 'B', child: Text('Blocks fallback')),
              DropdownMenuItem(value: 'P', child: Text('Plain text')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _editorMode = value;
                });
              }
            },
            decoration: const InputDecoration(
              labelText: 'Editor mode',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _themePreset,
                  items: _themePresetEntries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _themePreset = value);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Theme preset',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _themeMode,
                  items: const [
                    DropdownMenuItem(value: 'S', child: Text('System')),
                    DropdownMenuItem(value: 'L', child: Text('Light')),
                    DropdownMenuItem(value: 'D', child: Text('Dark')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _themeMode = value);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Theme mode',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiBaseController,
            decoration: const InputDecoration(
              labelText: 'API base URL',
              hintText: 'http://localhost:9080/api/v1',
              helperText: 'Full http:// or https:// endpoint for the REST API.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_saveFeedback != null) ...[
            _FeedbackText(feedback: _saveFeedback!),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _saving ? null : _submitSettings,
            child: Text(_saving ? 'Saving...' : 'Save settings'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: widget.onLogout,
            child: const Text('Logout'),
          ),
          const SizedBox(height: 24),
          Text('Calendars', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (widget.calendarFeeds.isEmpty)
            const Text('No imported or subscribed calendars yet.')
          else
            for (final feed in widget.calendarFeeds)
              Card(
                child: ListTile(
                  title: Text(feed['title']?.toString() ?? 'Calendar'),
                  subtitle: Text(
                    feed['source_kind']?.toString() == 'S'
                        ? 'Subscription'
                        : 'Imported iCal',
                  ),
                  leading: Switch(
                    value: feed['is_enabled'] == true,
                    onChanged: (value) =>
                        widget.onToggleCalendarFeed(feed, value),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => widget.onDeleteCalendarFeed(feed),
                  ),
                ),
              ),
        ],
        const SizedBox(height: 24),
        Text('API debug', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _ApiDebugCard(
          apiBaseUrl: widget.apiBaseUrl,
          snapshotListenable: widget.debugSnapshotListenable,
        ),
        const SizedBox(height: 24),
        Text('Frontend logs', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: SizedBox(
            height: 220,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final row in widget.uiLogs) SelectableText(row),
                if (widget.uiLogs.isEmpty)
                  const Text('No frontend logs captured yet.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact account action launcher used when the user is signed out.
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
      color: const Color(0xFFF6F0E6),
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
                      description:
                          'Sign in with your email and password. Admin username also works for the bootstrapped Django admin account.',
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

/// Reusable dialog for email/password forms such as sign up and login.
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
              decoration: InputDecoration(
                labelText: widget.emailLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
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

/// Dialog for email verification codes.
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

/// Dialog for password reset request and confirmation.
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

/// Shared inline feedback text used across settings dialogs.
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
