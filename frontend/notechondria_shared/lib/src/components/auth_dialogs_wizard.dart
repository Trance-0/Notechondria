import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/action_feedback.dart';
import 'auth_dialogs.dart';
import '../utils/blur_dialog.dart';
import 'phased_status.dart';

/// Multi-step registration wizard.
///
/// Step 0 - Invitation code (skipped automatically when no codes exist).
/// Step 1 - Choose registration method (currently email only; Casdoor SSO
///          replaces the legacy Google / GitHub buttons and is offered
///          from the parent AuthHub directly).
/// Step 2 - Email registration form (username, email + verify, password).
class RegistrationWizard extends StatefulWidget {
  const RegistrationWizard({
    super.key,
    required this.onValidateInvitation,
    required this.onRegister,
    required this.onResendVerification,
  });

  final Future<Map<String, dynamic>> Function(String code) onValidateInvitation;
  final Future<ActionFeedback> Function(
    String username,
    String email,
    String password, {
    String invitationCode,
  }) onRegister;
  final Future<ActionFeedback> Function(String email) onResendVerification;

  @override
  State<RegistrationWizard> createState() => _RegistrationWizardState();
}

class _RegistrationWizardState extends State<RegistrationWizard> {
  int _step = 0;
  final _invitationController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _verifyCodeController = TextEditingController();
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
            message: 'Registration blocked: '
                'Shared.AuthDialog/register.validate_invitation \u2014 '
                'invitation code is invalid or expired.',
            isError: true,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _feedback = ActionFeedback(
          message: 'Registration blocked: '
              'Shared.AuthDialog/register.validate_invitation \u2014 '
              '${e.toString().replaceFirst('Exception: ', '')}',
          isError: true,
        );
      });
    }
  }

  String? _validateEmailForm() {
    if (_usernameController.text.trim().isEmpty) {
      return 'Registration rejected: '
          'Shared.AuthDialog/register.validate_form \u2014 '
          'username is required.';
    }
    if (_emailController.text.trim().isEmpty) {
      return 'Registration rejected: '
          'Shared.AuthDialog/register.validate_form \u2014 '
          'email is required.';
    }
    final pw = _passwordController.text;
    if (pw.length < 8) {
      return 'Registration rejected: '
          'Shared.AuthDialog/register.validate_form \u2014 '
          'password must be at least 8 characters.';
    }
    final hasUpper = pw.contains(RegExp(r'[A-Z]'));
    final hasLower = pw.contains(RegExp(r'[a-z]'));
    final hasDigitOrSpecial = pw.contains(RegExp(r'[^a-zA-Z]'));
    if (!hasUpper || !hasLower || !hasDigitOrSpecial) {
      return 'Registration rejected: '
          'Shared.AuthDialog/register.validate_form \u2014 '
          'password must contain uppercase, lowercase, and a digit or '
          'special character.';
    }
    if (pw != _confirmPasswordController.text) {
      return 'Registration rejected: '
          'Shared.AuthDialog/register.validate_form \u2014 '
          'passwords do not match.';
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
                FeedbackText(feedback: _feedback!),
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
