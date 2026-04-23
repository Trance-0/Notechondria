import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Per-phase countdown widget: replaces a spinner with a text label
/// that names the current async step and appends the elapsed seconds
/// the caller has been waiting on that step. The goal is that the
/// user can tell *which* step is stuck, not just that *something* is
/// stuck.
///
/// Usage pattern:
///
/// ```dart
/// final phase = ValueNotifier<String>('Validating input');
/// // in the async worker:
/// phase.value = 'Sending request to backend';
/// final response = await client.login(...);
/// phase.value = 'Decoding response';
/// await _applyAuthPayload(response);
/// phase.value = 'Persisting session';
/// ```
///
/// The widget listens to [phase], resets its elapsed-seconds counter
/// every time the phase label changes (so each step has its own
/// countdown), and repaints every 200 ms so the seconds update
/// smoothly. When [phase.value] is empty, the widget renders nothing
/// — useful for "idle" states.
class PhasedStatusIndicator extends StatefulWidget {
  const PhasedStatusIndicator({
    super.key,
    required this.phase,
    this.style,
    this.leading,
    this.showSpinner = true,
  });

  /// Current phase label. Hand this to the async worker and let it
  /// mutate the value as the work progresses. An empty string hides
  /// the widget completely.
  final ValueListenable<String> phase;

  /// Optional style override; defaults to `theme.textTheme.bodyMedium`.
  final TextStyle? style;

  /// Optional icon rendered before the label. Defaults to a small
  /// `CircularProgressIndicator` so the widget reads as "work in
  /// progress" at a glance — but the elapsed-seconds suffix is what
  /// actually tells the user which step they're on.
  final Widget? leading;

  /// When false, suppresses the default leading spinner. Use when
  /// the host already owns its own progress chrome.
  final bool showSpinner;

  @override
  State<PhasedStatusIndicator> createState() => _PhasedStatusIndicatorState();
}

class _PhasedStatusIndicatorState extends State<PhasedStatusIndicator> {
  Timer? _tick;
  DateTime? _phaseStartedAt;
  String _lastPhase = '';

  @override
  void initState() {
    super.initState();
    _lastPhase = widget.phase.value;
    if (_lastPhase.isNotEmpty) {
      _phaseStartedAt = DateTime.now();
      _ensureTimer();
    }
    widget.phase.addListener(_onPhaseChanged);
  }

  @override
  void didUpdateWidget(covariant PhasedStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      oldWidget.phase.removeListener(_onPhaseChanged);
      widget.phase.addListener(_onPhaseChanged);
      _onPhaseChanged();
    }
  }

  @override
  void dispose() {
    widget.phase.removeListener(_onPhaseChanged);
    _tick?.cancel();
    super.dispose();
  }

  void _onPhaseChanged() {
    final next = widget.phase.value;
    if (next == _lastPhase) return;
    _lastPhase = next;
    if (next.isEmpty) {
      _phaseStartedAt = null;
      _tick?.cancel();
      _tick = null;
    } else {
      _phaseStartedAt = DateTime.now();
      _ensureTimer();
    }
    if (mounted) setState(() {});
  }

  void _ensureTimer() {
    _tick ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.phase.value;
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    final elapsed = _phaseStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_phaseStartedAt!);
    // Zero seconds during the first 200 ms reads as a mistake
    // ("stuck at 0"), so pin to 1 for anything under 1 s.
    final seconds = elapsed.inSeconds < 1 ? 1 : elapsed.inSeconds;
    final theme = Theme.of(context);
    final style = widget.style ?? theme.textTheme.bodyMedium;
    final leading = widget.showSpinner
        ? (widget.leading ??
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ))
        : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading,
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            '$label\u2026 (${seconds}s)',
            style: style,
          ),
        ),
      ],
    );
  }
}
