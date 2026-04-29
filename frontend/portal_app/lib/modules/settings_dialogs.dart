part of notechondria_frontend;

/// Password and email change dialogs for `_SettingsPageState`. These
/// are extracted into a separate part file so `settings.dart` stays
/// closer to the AGENTS.md §1.5 1000-line ceiling.
extension _SettingsPageDialogsX on _SettingsPageState {
  void _openChangePasswordDialog(BuildContext context) {
    final identityCodeCtrl = TextEditingController();
    final currentPwCtrl = TextEditingController();
    final newPwCtrl = TextEditingController();
    final confirmPwCtrl = TextEditingController();
    String? error;
    String? maskedEmail;
    bool submitting = false;
    bool identityVerified = false;
    showBlurDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(identityVerified ? 'Change password' : 'Verify your identity'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!identityVerified) ...[
                  if (maskedEmail == null)
                    const Text('A verification code will be sent to your current email.'),
                  if (maskedEmail != null) ...[
                    Text('A code was sent to $maskedEmail. Enter it below.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: identityCodeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '6-digit identity code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
                if (identityVerified) ...[
                  TextField(
                    controller: currentPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password',
                      helperText: 'Min 8 chars, uppercase + lowercase + digit/special.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: const TextStyle(
                          color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            if (!identityVerified && maskedEmail == null)
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        setDialogState(() {
                          submitting = true;
                          error = null;
                        });
                        try {
                          final result = await widget.onSendIdentityCode!();
                          setDialogState(() {
                            submitting = false;
                            maskedEmail =
                                result['masked_email']?.toString() ?? '***';
                          });
                        } catch (e) {
                          setDialogState(() {
                            submitting = false;
                            error = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: Text(submitting ? 'Sending...' : 'Send code'),
              ),
            if (!identityVerified && maskedEmail != null)
              FilledButton(
                onPressed: submitting
                    ? null
                    : () {
                        if (identityCodeCtrl.text.trim().isEmpty) {
                          setDialogState(
                              () => error = 'Enter the verification code.');
                          return;
                        }
                        setDialogState(() {
                          identityVerified = true;
                          error = null;
                        });
                      },
                child: const Text('Verify'),
              ),
            if (identityVerified)
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        if (newPwCtrl.text != confirmPwCtrl.text) {
                          setDialogState(
                              () => error = 'Passwords do not match.');
                          return;
                        }
                        if (newPwCtrl.text.length < 8) {
                          setDialogState(() =>
                              error = 'Password must be at least 8 characters.');
                          return;
                        }
                        setDialogState(() {
                          submitting = true;
                          error = null;
                        });
                        try {
                          await widget.onChangePassword!(
                            currentPwCtrl.text,
                            newPwCtrl.text,
                            identityCodeCtrl.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password changed.')),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            submitting = false;
                            error = e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: Text(submitting ? 'Saving...' : 'Change password'),
              ),
          ],
        ),
      ),
    ).then((_) {
      identityCodeCtrl.dispose();
      currentPwCtrl.dispose();
      newPwCtrl.dispose();
      confirmPwCtrl.dispose();
    });
  }

  void _openChangeEmailDialog(BuildContext context) {
    final identityCodeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String? error;
    String? successMessage;
    String? maskedEmail;
    bool submitting = false;
    bool identityVerified = false;
    bool codeSent = false;
    showBlurDialog<void>(
      context: context,
      child: StatefulBuilder(
        builder: (ctx, setDialogState) {
          final String title;
          if (!identityVerified) {
            title = 'Verify your identity';
          } else if (!codeSent) {
            title = 'Change email';
          } else {
            title = 'Confirm new email';
          }
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!identityVerified) ...[
                    if (maskedEmail == null)
                      const Text(
                          'A verification code will be sent to your current email.'),
                    if (maskedEmail != null) ...[
                      Text('A code was sent to $maskedEmail. Enter it below.'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: identityCodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '6-digit identity code',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                  if (identityVerified && !codeSent) ...[
                    const Text('Enter your new email address.'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'New email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (identityVerified && codeSent) ...[
                    Text('A code was sent to ${emailCtrl.text}. Enter it below.'),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '6-digit code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: const TextStyle(
                            color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                  ],
                  if (successMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(successMessage!,
                        style: const TextStyle(
                            color: Color(0xFF166534), fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              if (!identityVerified && maskedEmail == null)
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() {
                            submitting = true;
                            error = null;
                          });
                          try {
                            final result = await widget.onSendIdentityCode!();
                            setDialogState(() {
                              submitting = false;
                              maskedEmail =
                                  result['masked_email']?.toString() ?? '***';
                            });
                          } catch (e) {
                            setDialogState(() {
                              submitting = false;
                              error =
                                  e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: Text(submitting ? 'Sending...' : 'Send code'),
                ),
              if (!identityVerified && maskedEmail != null)
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () {
                          if (identityCodeCtrl.text.trim().isEmpty) {
                            setDialogState(
                                () => error = 'Enter the verification code.');
                            return;
                          }
                          setDialogState(() {
                            identityVerified = true;
                            error = null;
                          });
                        },
                  child: const Text('Verify'),
                ),
              if (identityVerified && !codeSent)
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (emailCtrl.text.trim().isEmpty) {
                            setDialogState(
                                () => error = 'Enter a new email address.');
                            return;
                          }
                          setDialogState(() {
                            submitting = true;
                            error = null;
                          });
                          try {
                            final result = await widget.onChangeEmailRequest!(
                              emailCtrl.text.trim(),
                              identityCodeCtrl.text.trim(),
                            );
                            setDialogState(() {
                              submitting = false;
                              codeSent = true;
                              successMessage = result['message']?.toString();
                            });
                          } catch (e) {
                            setDialogState(() {
                              submitting = false;
                              error =
                                  e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: Text(submitting ? 'Sending...' : 'Send code'),
                ),
              if (identityVerified && codeSent)
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (codeCtrl.text.trim().isEmpty) {
                            setDialogState(
                                () => error = 'Enter the verification code.');
                            return;
                          }
                          setDialogState(() {
                            submitting = true;
                            error = null;
                            successMessage = null;
                          });
                          try {
                            await widget.onChangeEmailConfirm!(
                              emailCtrl.text.trim(),
                              codeCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Email updated.')),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              submitting = false;
                              error =
                                  e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: Text(submitting ? 'Verifying...' : 'Confirm'),
                ),
            ],
          );
        },
      ),
    ).then((_) {
      identityCodeCtrl.dispose();
      emailCtrl.dispose();
      codeCtrl.dispose();
    });
  }
}
