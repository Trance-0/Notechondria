import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Copyable feedback (0.1.199): every warning, error, and info message the
/// apps show must be selectable and offer a visible, keyboard-reachable
/// Copy action that puts the full AGENTS.md §1.8 message on the clipboard.
///
/// A page-level `SelectionArea` does not reach these surfaces: SnackBars
/// are painted by the ScaffoldMessenger outside the page body, and dialogs
/// are separate routes. Hence the message widgets themselves render
/// `SelectableText` plus [CopyMessageButton] (inline / dialog text) or go
/// through [showCopyableSnackBar] (SnackBars).

/// Writes [message] to the system clipboard. Returns null on success, or
/// the triggering cause when the platform rejected the write (e.g. the
/// browser denied clipboard access).
Future<String?> writeMessageToClipboard(String message) async {
  try {
    await Clipboard.setData(ClipboardData(text: message));
    return null;
  } catch (error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? error.runtimeType.toString() : text;
  }
}

/// Copies [message] and reports the outcome in a short SnackBar on the
/// nearest [ScaffoldMessenger] ("Message copied to clipboard." or the
/// §1.8 copy-failure message). Returns whether the copy succeeded.
///
/// Use it from surfaces that are not covered by a modal barrier (a
/// SnackBar action, a page). Inside dialogs prefer [CopyMessageButton],
/// which reports in place.
Future<bool> copyMessageToClipboard(BuildContext context, String message) {
  return _copyAndReport(
    ScaffoldMessenger.maybeOf(context),
    AppLocalizations.of(context),
    message,
  );
}

Future<bool> _copyAndReport(
  ScaffoldMessengerState? messenger,
  AppLocalizations l10n,
  String message,
) async {
  final failure = await writeMessageToClipboard(message);
  messenger?.showSnackBar(SnackBar(
    content: SelectableMessageText(
      failure == null
          ? l10n.feedbackMessageCopied
          : l10n.feedbackCopyFailed(failure),
    ),
    duration: const Duration(seconds: 2),
    persist: false,
  ));
  return failure == null;
}

/// Shows [message] in a SnackBar whose text is selectable and which has a
/// Copy action (copies the full message) and a close icon. Errors stay
/// longer (10s) than other messages (6s). `persist: false` keeps the
/// auto-dismiss: a SnackBar with an action persists by default on this
/// SDK.
void showCopyableSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final l10n = AppLocalizations.of(context);
  messenger.showSnackBar(SnackBar(
    content: SelectableMessageText(message),
    duration: Duration(seconds: isError ? 10 : 6),
    persist: false,
    showCloseIcon: true,
    action: SnackBarAction(
      label: l10n.commonCopy,
      onPressed: () => _copyAndReport(messenger, l10n, message),
    ),
  ));
}

/// Selectable message text that assistive technology can still read.
///
/// On web a bare `SelectableText` reaches the semantics tree as an empty,
/// disabled text field (no value, no label), so a screen reader would skip
/// the message. This gives the message to the semantics tree as its own
/// labeled node instead; mouse selection and copy are unaffected. Package
/// internal (not exported).
class SelectableMessageText extends StatelessWidget {
  const SelectableMessageText(
    this.message, {
    super.key,
    this.style,
    this.textAlign,
  });

  final String message;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: message,
      excludeSemantics: true,
      child: SelectableText(message, style: style, textAlign: textAlign),
    );
  }
}

/// Icon button that copies [message] to the clipboard. Its tooltip (also
/// its semantic label) is "Copy message"; after a copy it switches in
/// place to a check icon with "Message copied to clipboard.", or to an
/// error icon whose tooltip carries the §1.8 copy-failure message. No
/// timer resets it, so tests have no pending timers.
class CopyMessageButton extends StatefulWidget {
  const CopyMessageButton({
    super.key,
    required this.message,
    this.compact = false,
    this.color,
  });

  /// Full text placed on the clipboard.
  final String message;

  /// Smaller icon and tighter hit box for inline feedback rows.
  final bool compact;
  final Color? color;

  @override
  State<CopyMessageButton> createState() => _CopyMessageButtonState();
}

class _CopyMessageButtonState extends State<CopyMessageButton> {
  // null = idle, true = copied, false = the platform rejected the write.
  bool? _copied;
  String _failure = '';

  @override
  void didUpdateWidget(CopyMessageButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      _copied = null;
      _failure = '';
    }
  }

  Future<void> _copy() async {
    final failure = await writeMessageToClipboard(widget.message);
    if (!mounted) return;
    setState(() {
      _copied = failure == null;
      _failure = failure ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final copied = _copied;
    final tooltip = copied == null
        ? l10n.feedbackCopyMessage
        : copied
            ? l10n.feedbackMessageCopied
            : l10n.feedbackCopyFailed(_failure);
    final icon = copied == null
        ? Icons.copy_outlined
        : copied
            ? Icons.check
            : Icons.error_outline;
    return IconButton(
      tooltip: tooltip,
      onPressed: _copy,
      color: widget.color,
      iconSize: widget.compact ? 18 : 22,
      visualDensity: widget.compact ? VisualDensity.compact : null,
      icon: Icon(icon),
    );
  }
}
