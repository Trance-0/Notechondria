import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.shield_outlined),
          const SizedBox(width: 8),
          Text(l10n.linkTitle),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.linkSignedInAs,
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.linkChooseIntro),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _stage = _DialogStage.bind),
          icon: const Icon(Icons.link),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l10n.linkBindButton),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.linkBindDesc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => setState(() => _stage = _DialogStage.create),
          icon: const Icon(Icons.person_add_alt_outlined),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(l10n.linkCreateButton),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.linkCreateDesc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildBindPane(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.linkBindPaneDesc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _identifier,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.linkUsernameOrEmailLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.linkPasswordLabel,
            border: const OutlineInputBorder(),
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
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.linkCreatePaneDesc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.linkNewPasswordLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmPassword,
          obscureText: true,
          decoration: InputDecoration(
            labelText: l10n.linkConfirmPasswordLabel,
            border: const OutlineInputBorder(),
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
    final l10n = AppLocalizations.of(context);
    if (_stage == _DialogStage.choose) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l10n.commonCancel),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => setState(() {
          _stage = _DialogStage.choose;
          _formError = null;
        }),
        child: Text(l10n.commonBack),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(null),
        child: Text(l10n.commonCancel),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(
          _stage == _DialogStage.bind
              ? l10n.linkBindAction
              : l10n.linkCreateAction,
        ),
      ),
    ];
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    if (_stage == _DialogStage.bind) {
      final id = _identifier.text.trim();
      final pw = _password.text;
      if (id.isEmpty || pw.isEmpty) {
        setState(() => _formError = l10n.linkErrBindRequired);
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
        setState(() => _formError = l10n.linkErrPasswordShort);
        return;
      }
      if (pw != cf) {
        setState(() => _formError = l10n.linkErrPasswordMismatch);
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
