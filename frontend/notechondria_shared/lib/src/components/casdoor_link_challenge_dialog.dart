import 'package:flutter/material.dart';

/// Result of the gitea-style Casdoor link-challenge dialog (since
/// 0.1.118). Returned via `Navigator.pop` so the caller in
/// `_AppShellState.onCasdoorLinkChallenge` can dispatch the right
/// completion endpoint:
///
/// - [bind]: caller POSTs `casdoorLinkBind(nonce, identifier,
///   password)` against the user-supplied legacy credentials.
/// - [create]: caller POSTs `casdoorLinkCreate(nonce, password)`
///   with the user-chosen new password.
///
/// `null` when the user cancelled the dialog — caller should treat
/// that as "no decision made; abort the OAuth flow without
/// surfacing an error".
class CasdoorLinkChallengeDecision {
  CasdoorLinkChallengeDecision.bind({
    required this.identifier,
    required this.password,
  })  : intent = 'bind',
        confirmPassword = '';
  CasdoorLinkChallengeDecision.create({
    required this.password,
    required this.confirmPassword,
  })  : intent = 'create',
        identifier = '';

  final String intent; // 'bind' | 'create'
  final String identifier;
  final String password;
  final String confirmPassword;
}

/// Bind-vs-create choice dialog after a Casdoor sign-in returns a
/// link challenge instead of an auth payload. Renders the Casdoor
/// identity captured server-side (email + display name) so the
/// user can confirm which third-party identity is about to be
/// bound or used to create a fresh account, then collects the
/// credentials needed for the chosen completion endpoint.
///
/// The dialog itself never carries the Casdoor JWT — that lives
/// server-side on the LinkChallenge row keyed by the nonce. The
/// caller (`onCasdoorLinkChallenge` on `_AppShellState`) passes
/// the nonce and casdoor_identity through; this widget only
/// handles UI + form validation.
class CasdoorLinkChallengeDialog extends StatefulWidget {
  const CasdoorLinkChallengeDialog({
    super.key,
    required this.casdoorIdentity,
    required this.suggestedUsername,
  });

  /// `casdoor_identity` block from the exchange response —
  /// contains `username`, `email`, and `display_name`.
  final Map<String, String> casdoorIdentity;

  /// Pre-fill suggestion for the bind form's identifier field.
  /// Backend derives this from the Casdoor username claim, falling
  /// back to the email's local-part. The user can override.
  final String suggestedUsername;

  @override
  State<CasdoorLinkChallengeDialog> createState() =>
      _CasdoorLinkChallengeDialogState();
}

enum _DialogStage { choose, bind, create }

class _CasdoorLinkChallengeDialogState
    extends State<CasdoorLinkChallengeDialog> {
  _DialogStage _stage = _DialogStage.choose;
  late final TextEditingController _identifier =
      TextEditingController(text: widget.suggestedUsername);
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  String? _formError;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String get _email => widget.casdoorIdentity['email'] ?? '';
  String get _displayName =>
      widget.casdoorIdentity['display_name'] ??
      widget.casdoorIdentity['username'] ??
      '';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield_outlined),
          SizedBox(width: 8),
          Text('Link Casdoor identity'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Casdoor signed you in as:',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_displayName.isNotEmpty)
                      Text(
                        _displayName,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    if (_email.isNotEmpty)
                      Text(
                        _email,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_stage == _DialogStage.choose) _buildChoosePane(context),
            if (_stage == _DialogStage.bind) _buildBindPane(context),
            if (_stage == _DialogStage.create) _buildCreatePane(context),
          ],
        ),
      ),
      actions: _buildActions(context),
    );
  }

  Widget _buildChoosePane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'This Casdoor identity is not yet linked to a Notechondria '
          'account. Choose how you want to proceed:',
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _stage = _DialogStage.bind),
          icon: const Icon(Icons.link),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Bind to my existing account'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'You already have a Notechondria account. Sign in once with '
          'your legacy username/email + password to link this Casdoor '
          'identity to it. After linking, future Casdoor sign-ins '
          'land on the same account.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _stage = _DialogStage.create),
          icon: const Icon(Icons.person_add_alt_outlined),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text('Create a new Notechondria account'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'No prior Notechondria account. Pick a password — your new '
          'account will be created with the username and email shown '
          'above. The same password works for the email/password '
          'fallback path when Casdoor is unreachable.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildBindPane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in to your existing Notechondria account once so we '
          'can link it to this Casdoor identity. Username or email + '
          'the password you set previously.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _identifier,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Notechondria username or email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Notechondria password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 8),
          Text(
            _formError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _buildCreatePane(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pick a password for your new Notechondria account. Casdoor '
          'will keep handling SSO; the password is for the legacy '
          'email/password fallback (when auth.trance-0.com is '
          'unreachable).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmPassword,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Confirm password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_formError != null) ...[
          const SizedBox(height: 8),
          Text(
            _formError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_stage == _DialogStage.choose) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => setState(() {
          _stage = _DialogStage.choose;
          _formError = null;
        }),
        child: const Text('Back'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(null),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(
          _stage == _DialogStage.bind ? 'Bind account' : 'Create account',
        ),
      ),
    ];
  }

  void _submit() {
    if (_stage == _DialogStage.bind) {
      final id = _identifier.text.trim();
      final pw = _password.text;
      if (id.isEmpty || pw.isEmpty) {
        setState(() => _formError =
            'Both username/email and password are required to bind.');
        return;
      }
      Navigator.of(context).pop(
        CasdoorLinkChallengeDecision.bind(identifier: id, password: pw),
      );
      return;
    }
    if (_stage == _DialogStage.create) {
      final pw = _password.text;
      final cf = _confirmPassword.text;
      if (pw.length < 8) {
        setState(() => _formError = 'Pick a password of 8 characters or more.');
        return;
      }
      if (pw != cf) {
        setState(() => _formError =
            'Passwords do not match. Re-type the same password in both '
                'fields.');
        return;
      }
      Navigator.of(context).pop(
        CasdoorLinkChallengeDecision.create(
          password: pw,
          confirmPassword: cf,
        ),
      );
    }
  }
}
