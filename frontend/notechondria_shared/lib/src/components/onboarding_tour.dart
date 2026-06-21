import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/blur_dialog.dart';

/// One page of the first-run onboarding tour. Deliberately
/// layout-agnostic: an icon + short title + body, never a pointer at a
/// specific on-screen widget. Anchored coach marks were rejected
/// because each step would need authoring twice around the 960 px
/// drawer/sidebar breakpoint and would break on UI refactors; a
/// conceptual paged intro renders identically on phone and desktop.
class TourStep {
  const TourStep({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

/// Show the first-run onboarding tour as a blur-backed, skippable,
/// paged overlay. Resolves when the user finishes ("Done"), skips, or
/// taps outside. Callers stamp their "seen" flag regardless of how it
/// closed — the tour is a one-time intro, re-openable from Settings.
Future<void> showOnboardingTour(
  BuildContext context, {
  required String appTitle,
  required List<TourStep> steps,
}) {
  if (steps.isEmpty) return Future<void>.value();
  return showBlurDialog<void>(
    context: context,
    child: _OnboardingTourDialog(appTitle: appTitle, steps: steps),
  );
}

class _OnboardingTourDialog extends StatefulWidget {
  const _OnboardingTourDialog({required this.appTitle, required this.steps});

  final String appTitle;
  final List<TourStep> steps;

  @override
  State<_OnboardingTourDialog> createState() => _OnboardingTourDialogState();
}

class _OnboardingTourDialogState extends State<_OnboardingTourDialog> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    final clamped = index.clamp(0, widget.steps.length - 1);
    _controller.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isLast = _index == widget.steps.length - 1;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.appTitle,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(isLast ? l10n.commonClose : l10n.commonSkip),
                  ),
                ],
              ),
              SizedBox(
                height: 240,
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemCount: widget.steps.length,
                  itemBuilder: (context, i) {
                    final step = widget.steps[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(step.icon,
                            size: 56, color: theme.colorScheme.primary),
                        const SizedBox(height: 18),
                        Text(
                          step.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            step.body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.steps.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(
                    onPressed: _index == 0 ? null : () => _go(_index - 1),
                    child: Text(l10n.commonBack),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (isLast) {
                        Navigator.of(context).pop();
                      } else {
                        _go(_index + 1);
                      }
                    },
                    child: Text(isLast ? l10n.commonDone : l10n.commonNext),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
