part of notechondria_frontend;

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.profile,
    required this.settings,
    required this.localSettings,
    required this.localStats,
    required this.deletedNotes,
    required this.onSave,
    required this.onLogout,
    required this.onRegister,
    required this.onValidateInvitation,
    required this.onVerify,
    required this.onResendVerification,
    required this.onLogin,
    required this.onRequestPasswordReset,
    required this.onConfirmPasswordReset,
    this.onGoogleLogin,
    this.onGithubLogin,
    required this.onRestoreDeletedNote,
    required this.onEmptyDeletedNotes,
    required this.onCopyLogs,
    required this.onUploadAvatar,
    required this.onSyncLocalData,
    required this.onPullCloudData,
    required this.onClearLocalCache,
    required this.onClearLocalData,
    required this.onRestoreTemplateCourses,
    required this.localDraftCount,
    required this.localCourseCount,
    required this.uiLogs,
    this.apiBaseUrl,
    this.debugSnapshotListenable,
    this.debugHistoryListenable,
  });

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic> localSettings;
  final Map<String, dynamic> localStats;
  final List<Map<String, dynamic>> deletedNotes;
  final Future<ActionFeedback> Function(
    String username,
    String email,
    String motto,
    String socialLink,
    String editorMode,
    String themePreset,
    String themeMode,
    String apiBaseUrl,
    double deadlineTimeWeight,
    double deadlineImportanceWeight,
  ) onSave;
  final Future<void> Function() onLogout;
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
  final Future<void> Function(Map<String, dynamic> note) onRestoreDeletedNote;
  final Future<void> Function() onEmptyDeletedNotes;
  final Future<void> Function() onCopyLogs;
  final Future<ActionFeedback> Function() onUploadAvatar;
  final Future<ActionFeedback> Function({bool showMessage}) onSyncLocalData;
  final Future<ActionFeedback> Function() onPullCloudData;
  final Future<ActionFeedback> Function() onClearLocalCache;
  final Future<ActionFeedback> Function() onClearLocalData;
  final Future<ActionFeedback> Function() onRestoreTemplateCourses;
  final int localDraftCount;
  final int localCourseCount;
  final List<String> uiLogs;
  final String? apiBaseUrl;
  final ValueListenable<ApiDebugSnapshot?>? debugSnapshotListenable;
  final ValueListenable<List<ApiDebugSnapshot>>? debugHistoryListenable;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late final TextEditingController _usernameController;
  late final TextEditingController _emailController;
  late final TextEditingController _mottoController;
  late final TextEditingController _socialController;
  late final TextEditingController _apiBaseController;
  late final TextEditingController _deadlineTimeWeightController;
  late final TextEditingController _deadlineImportanceWeightController;
  String _editorMode = 'P';
  String _themePreset = 'teal';
  String _themeMode = 'S';
  ActionFeedback? _saveFeedback;
  bool _saving = false;
  bool _uploadingAvatar = false;

  bool get _isAuthenticated => widget.profile != null && widget.settings != null;

  bool get _isAdmin =>
      widget.profile?['is_superuser'] == true ||
      widget.settings?['is_superuser'] == true;

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
    _mottoController =
        TextEditingController(text: widget.settings?['motto']?.toString() ?? '');
    _socialController = TextEditingController(
      text: widget.settings?['social_link']?.toString() ?? '',
    );
    _apiBaseController = TextEditingController(
      text: widget.localSettings['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          _defaultApiBaseUrl(),
    );
    _deadlineTimeWeightController = TextEditingController(
      text: (widget.localSettings['deadline_time_weight'] ?? 1.0).toString(),
    );
    _deadlineImportanceWeightController = TextEditingController(
      text: (widget.localSettings['deadline_importance_weight'] ?? 1.0).toString(),
    );
    _editorMode = widget.settings?['editor_mode']?.toString() ?? 'P';
    _themePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
    _themeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
  }

  @override
  void didUpdateWidget(covariant _SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings || oldWidget.profile != widget.profile) {
      _usernameController.text = widget.settings?['username']?.toString() ??
          widget.profile?['username']?.toString() ??
          '';
      _emailController.text = widget.settings?['email']?.toString() ??
          widget.profile?['email']?.toString() ??
          '';
      _mottoController.text = widget.settings?['motto']?.toString() ?? '';
      _socialController.text = widget.settings?['social_link']?.toString() ?? '';
      _editorMode = widget.settings?['editor_mode']?.toString() ?? _editorMode;
    }
    if (oldWidget.localSettings != widget.localSettings) {
      _apiBaseController.text = widget.localSettings['api_base_url']?.toString() ??
          widget.apiBaseUrl ??
          _defaultApiBaseUrl();
      _deadlineTimeWeightController.text =
          (widget.localSettings['deadline_time_weight'] ?? 1.0).toString();
      _deadlineImportanceWeightController.text =
          (widget.localSettings['deadline_importance_weight'] ?? 1.0).toString();
      _themePreset = widget.localSettings['theme_preset']?.toString() ?? 'teal';
      _themeMode = widget.localSettings['theme_mode']?.toString() ?? 'S';
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _mottoController.dispose();
    _socialController.dispose();
    _apiBaseController.dispose();
    _deadlineTimeWeightController.dispose();
    _deadlineImportanceWeightController.dispose();
    super.dispose();
  }

  Future<void> _submitSettings() async {
    setState(() {
      _saving = true;
      _saveFeedback = null;
    });
    final deadlineTimeWeight =
        double.tryParse(_deadlineTimeWeightController.text.trim()) ?? 1.0;
    final deadlineImportanceWeight =
        double.tryParse(_deadlineImportanceWeightController.text.trim()) ?? 1.0;
    final feedback = await widget.onSave(
      _usernameController.text.trim(),
      _emailController.text.trim(),
      _mottoController.text.trim(),
      _socialController.text.trim(),
      _editorMode,
      _themePreset,
      _themeMode,
      _apiBaseController.text.trim(),
      deadlineTimeWeight,
      deadlineImportanceWeight,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      _saveFeedback = feedback;
    });
  }

  Future<void> _handleAvatarUpload() async {
    setState(() {
      _uploadingAvatar = true;
      _saveFeedback = null;
    });
    final feedback = await widget.onUploadAvatar();
    if (!mounted) {
      return;
    }
    setState(() {
      _uploadingAvatar = false;
      _saveFeedback = feedback;
    });
  }

  Future<void> _runMaintenanceAction(
    Future<ActionFeedback> Function() action,
  ) async {
    setState(() {
      _saveFeedback = null;
    });
    final feedback = await action();
    if (!mounted) {
      return;
    }
    setState(() {
      _saveFeedback = feedback;
    });
  }

  Future<void> _openRecycleBinDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recycle bin'),
        content: SizedBox(
          width: 560,
          child: widget.deletedNotes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Recycle bin is empty.'),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          await widget.onEmptyDeletedNotes();
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        child: const Text('Empty recycle bin'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 320,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final note in widget.deletedNotes)
                            Card(
                              child: ListTile(
                                title: Text(
                                  note['title']?.toString() ?? 'Untitled note',
                                ),
                                subtitle: Text(
                                  note['description']?.toString() ??
                                      note['excerpt']?.toString() ??
                                      '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: TextButton(
                                  onPressed: () async {
                                    await widget.onRestoreDeletedNote(note);
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: const Text('Restore'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Planner settings',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'This app keeps planner-focused controls only: login/sync, deadline-ordering preferences, and debug output.',
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Login and sync',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (!_isAuthenticated) ...[
                  const Text(
                    'Sign in to sync course plans, module discussion roots, and planner deadlines. Local planner data remains usable while signed out.',
                  ),
                  const SizedBox(height: 12),
                  _AuthHub(
                    onRegister: widget.onRegister,
                    onValidateInvitation: widget.onValidateInvitation,
                    onVerify: widget.onVerify,
                    onResendVerification: widget.onResendVerification,
                    onLogin: widget.onLogin,
                    onRequestPasswordReset: widget.onRequestPasswordReset,
                    onConfirmPasswordReset: widget.onConfirmPasswordReset,
                    onGoogleLogin: widget.onGoogleLogin,
                    onGithubLogin: widget.onGithubLogin,
                  ),
                ] else ...[
                  Text(
                    'Signed in as ${widget.profile?['email']?.toString() ?? widget.profile?['username']?.toString() ?? 'user'}.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _runMaintenanceAction(
                          () => widget.onSyncLocalData(showMessage: false),
                        ),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text('Push local → cloud'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _runMaintenanceAction(widget.onPullCloudData),
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('Pull cloud → local'),
                      ),
                      OutlinedButton(
                        onPressed: widget.onLogout,
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planner preferences',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _themePreset,
                        items: _themePresetEntries.entries
                            .map((entry) => DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _deadlineTimeWeightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Deadline time weight (a)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _deadlineImportanceWeightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Deadline importance weight (b)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Deadlines sort by (a × time pressure) × (b × importance). Importance uses the existing event weight.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiBaseController,
                  decoration: const InputDecoration(
                    labelText: 'API base URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (_saveFeedback != null) ...[
                  _FeedbackText(feedback: _saveFeedback!),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _saving ? null : _submitSettings,
                  child: Text(_saving ? 'Saving...' : 'Save planner settings'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Debug log',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.localDraftCount} local note(s), ${widget.localCourseCount} local course(s).',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.onCopyLogs,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('Copy logs'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 260,
                  child: widget.uiLogs.isEmpty
                      ? const Center(child: Text('No frontend logs captured yet.'))
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: widget.uiLogs.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: SelectableText(
                              widget.uiLogs[index],
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontFamily: 'monospace'),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

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
  });

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
                          'Enter the verification code sent to your email.',
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

/// Multi-step registration wizard.
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
  int _step = 0;
  final _invitationController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  ActionFeedback? _feedback;
  bool _submitting = false;
  String _validatedInvitationCode = '';
  bool _emailRegistered = false;
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
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _validateInvitation() async {
    final code = _invitationController.text.trim();
    setState(() { _submitting = true; _feedback = null; });
    try {
      final result = await widget.onValidateInvitation(code);
      if (!mounted) return;
      final required = result['required'] == true;
      final valid = result['valid'] == true;
      if (!required) {
        setState(() { _submitting = false; _validatedInvitationCode = ''; _step = 1; });
        return;
      }
      if (valid) {
        setState(() { _submitting = false; _validatedInvitationCode = code; _step = 1; });
      } else {
        setState(() {
          _submitting = false;
          _feedback = const ActionFeedback(message: 'Invalid or expired invitation code.', isError: true);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _feedback = ActionFeedback(message: e.toString().replaceFirst('Exception: ', ''), isError: true);
      });
    }
  }

  String? _validateEmailForm() {
    if (_usernameController.text.trim().isEmpty) return 'Username is required.';
    if (_emailController.text.trim().isEmpty) return 'Email is required.';
    final pw = _passwordController.text;
    if (pw.length < 8) return 'Password must be at least 8 characters.';
    if (!pw.contains(RegExp(r'[A-Z]')) || !pw.contains(RegExp(r'[a-z]')) || !pw.contains(RegExp(r'[^a-zA-Z]'))) {
      return 'Password needs uppercase, lowercase, and a digit or special character.';
    }
    if (pw != _confirmPasswordController.text) return 'Passwords do not match.';
    return null;
  }

  Future<void> _submitEmailRegistration() async {
    final error = _validateEmailForm();
    if (error != null) { setState(() { _feedback = ActionFeedback(message: error, isError: true); }); return; }
    setState(() { _submitting = true; _feedback = null; });
    final feedback = await widget.onRegister(
      _usernameController.text.trim(), _emailController.text.trim(), _passwordController.text,
      invitationCode: _validatedInvitationCode,
    );
    if (!mounted) return;
    setState(() { _submitting = false; _feedback = feedback; if (!feedback.isError) _emailRegistered = true; });
    if (!feedback.isError) _startCooldown();
  }

  Future<void> _resendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() { _submitting = true; _feedback = null; });
    final feedback = await widget.onResendVerification(email);
    if (!mounted) return;
    setState(() { _submitting = false; _feedback = feedback; });
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
              if (_feedback != null) ...[const SizedBox(height: 12), _FeedbackText(feedback: _feedback!)],
            ],
          ),
        ),
      ),
      actions: _buildActions(),
    );
  }

  String get _stepTitle {
    switch (_step) {
      case 0: return 'Invitation code';
      case 1: return 'Choose sign-up method';
      case 2: return _emailRegistered ? 'Verify your email' : 'Create account';
      default: return 'Sign up';
    }
  }

  Widget _buildInvitationStep() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Enter an invitation code to continue registration.'),
      const SizedBox(height: 16),
      TextField(
        controller: _invitationController, textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submitting ? null : _validateInvitation(),
        decoration: const InputDecoration(labelText: 'Invitation code', border: OutlineInputBorder()),
      ),
    ]);
  }

  Widget _buildMethodStep() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('How would you like to register?'),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: () => setState(() { _step = 2; _feedback = null; }),
        icon: const Icon(Icons.email_outlined), label: const Text('Register with email'),
      )),
      if (widget.onGoogleLogin != null) ...[const SizedBox(height: 10), SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () { widget.onGoogleLogin!(_validatedInvitationCode); Navigator.of(context).pop(); },
        icon: const Icon(Icons.g_mobiledata, size: 22), label: const Text('Continue with Google'),
      ))],
      if (widget.onGithubLogin != null) ...[const SizedBox(height: 10), SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: () { widget.onGithubLogin!(_validatedInvitationCode); Navigator.of(context).pop(); },
        icon: const Icon(Icons.code, size: 18), label: const Text('Continue with GitHub'),
      ))],
    ]);
  }

  Widget _buildEmailFormStep() {
    if (_emailRegistered) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('A 6-digit verification code was sent to ${_emailController.text.trim()}. '
            'Enter it on the "Verify email" dialog to activate your account.'),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: TextButton(
          onPressed: _submitting || _resendCooldown > 0 ? null : _resendCode,
          child: Text(_resendCooldown > 0 ? 'Resend code (${_resendCooldown}s)' : 'Resend code'),
        )),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('A verification code will be sent to your email after registration.'),
      const SizedBox(height: 16),
      TextField(controller: _usernameController, textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Username', helperText: 'Letters, numbers, hyphens, underscores.', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _passwordController, obscureText: true, textInputAction: TextInputAction.next,
        decoration: const InputDecoration(labelText: 'Password', helperText: 'Min 8 chars, uppercase + lowercase + digit/special.', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _confirmPasswordController, obscureText: true, textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submitting ? null : _submitEmailRegistration(),
        decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder())),
    ]);
  }

  List<Widget> _buildActions() {
    switch (_step) {
      case 0: return [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(onPressed: _submitting ? null : _validateInvitation, child: Text(_submitting ? 'Checking...' : 'Confirm')),
      ];
      case 1: return [
        TextButton(onPressed: () => setState(() { _step = 0; _feedback = null; }), child: const Text('Back')),
      ];
      case 2:
        if (_emailRegistered) return [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))];
        return [
          TextButton(onPressed: _submitting ? null : () => setState(() { _step = 1; _feedback = null; }), child: const Text('Back')),
          FilledButton(onPressed: _submitting ? null : _submitEmailRegistration, child: Text(_submitting ? 'Creating...' : 'Register')),
        ];
      default: return [];
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
