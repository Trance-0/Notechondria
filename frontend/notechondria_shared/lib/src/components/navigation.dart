import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'copyable_feedback.dart';

/// Confirmation dialog that disables its destructive button for [delaySeconds]
/// to give the user a chance to reconsider. Used for clear-data and delete-
/// category style operations.
class ConfirmWithDelayDialog extends StatefulWidget {
  const ConfirmWithDelayDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmLabel = 'Delete',
    this.delaySeconds = 3,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final int delaySeconds;

  @override
  State<ConfirmWithDelayDialog> createState() => _ConfirmWithDelayDialogState();
}

class _ConfirmWithDelayDialogState extends State<ConfirmWithDelayDialog> {
  late int _remaining;
  Timer? _timer;
  // null = not copied yet, true = copied, false = clipboard write failed.
  bool? _copied;
  String _copyFailure = '';

  @override
  void initState() {
    super.initState();
    _remaining = widget.delaySeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _remaining -= 1;
        if (_remaining <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copyMessage() async {
    final failure = await writeMessageToClipboard(widget.message);
    if (!mounted) return;
    setState(() {
      _copied = failure == null;
      _copyFailure = failure ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _remaining <= 0;
    final l10n = AppLocalizations.of(context);
    final copied = _copied;
    return AlertDialog(
      title: Text(widget.title),
      // Selectable + a Copy action (0.1.199): the dialog is its own route,
      // so the page's SelectionArea does not cover it.
      content: SelectableMessageText(widget.message),
      actions: [
        Tooltip(
          message: copied == false
              ? l10n.feedbackCopyFailed(_copyFailure)
              : l10n.feedbackCopyMessage,
          child: TextButton.icon(
            onPressed: _copyMessage,
            icon: Icon(copied == null
                ? Icons.copy_outlined
                : copied
                    ? Icons.check
                    : Icons.error_outline),
            label: Text(copied == true
                ? l10n.feedbackMessageCopied
                : l10n.commonCopy),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: enabled ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          child: Text(
            enabled
                ? widget.confirmLabel
                : '${widget.confirmLabel} ($_remaining)',
          ),
        ),
      ],
    );
  }
}

/// Sidebar navigation row used by the wide desktop layout.
class SidebarItem extends StatelessWidget {
  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selectedBackground = colorScheme.primaryContainer;
    final selectedForeground = colorScheme.onPrimaryContainer;
    final idleForeground = colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? selectedBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? selectedForeground : idleForeground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? selectedForeground : idleForeground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
