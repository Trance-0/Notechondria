import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final enabled = _remaining <= 0;
    return AlertDialog(
      title: Text(widget.title),
      content: Text(widget.message),
      actions: [
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
