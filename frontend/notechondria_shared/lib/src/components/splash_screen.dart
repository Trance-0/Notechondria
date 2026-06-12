import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../reaction_simulator/reaction_view.dart';

/// Splash screen backed by the reaction-simulator animation (TCA-cycle
/// molecules drifting, colliding, and reacting on a toroidal world).
///
/// Replaced the hand-drawn rotating Krebs-cycle painter in 0.1.128 with
/// a Dart port of the owner's `index` repo reaction simulator
/// (https://index.trance-0.com/utils/reaction_simulator); see
/// `../reaction_simulator/`. The version string in the bottom-left is
/// supplied by the host app via [appVersion] so each app can show its
/// own build-time-injected `--dart-define=APP_VERSION=...` value.
///
/// The detailed loading-status line under the title is driven by
/// [loadingStatus]. The host app typically wires a `ValueNotifier<String>`
/// to it and pushes strings like `"Connecting to server"` or
/// `"Loading public notes data"` as bootstrap progresses. When omitted the
/// splash falls back to a static `"Loading..."` string.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.appTitle,
    required this.appVersion,
    this.onFinished,
    this.loadingStatus,
    this.apiBaseUrl,
  });

  final String appTitle;
  final String appVersion;
  final VoidCallback? onFinished;
  final ValueListenable<String>? loadingStatus;

  /// Backend base URL to display next to the version string. The splash
  /// extracts and shows just the host (e.g. `notechondria.render.com`)
  /// so the operator can see which deployment they're hitting. When null
  /// or empty the splash shows `offline`.
  final String? apiBaseUrl;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onFinished?.call();
  }

  /// Formats the optional backend URL into a compact host tag shown next
  /// to the version string. Empty / null / malformed URLs collapse to
  /// `offline`. Relative paths (`/api/v1`) are shown verbatim so an
  /// operator inspecting the splash can tell local-dev from remote-prod.
  static String _formatBackendTag(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'offline';
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return trimmed;
    return uri.host;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0f172a) : const Color(0xFFF8FAFC);
    final textColor = theme.colorScheme.onSurface;
    final subtleColor = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: dismiss,
      child: Container(
        color: bgColor,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                const Positioned.fill(
                  child: ReactionSimulatorView(),
                ),
                Positioned(
                  right: constraints.maxWidth * 0.08,
                  bottom: constraints.maxHeight * 0.12,
                  child: _HeaderColumn(
                    appTitle: widget.appTitle,
                    textColor: textColor,
                    subtleColor: subtleColor,
                    fadeController: _fadeController,
                    loadingStatus: widget.loadingStatus,
                  ),
                ),
                Positioned(
                  left: constraints.maxWidth * 0.04,
                  bottom: constraints.maxHeight * 0.04,
                  child: Text(
                    'v${widget.appVersion} \u00b7 ${_formatBackendTag(widget.apiBaseUrl)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: subtleColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderColumn extends StatelessWidget {
  const _HeaderColumn({
    required this.appTitle,
    required this.textColor,
    required this.subtleColor,
    required this.fadeController,
    required this.loadingStatus,
  });

  final String appTitle;
  final Color textColor;
  final Color subtleColor;
  final AnimationController fadeController;
  final ValueListenable<String>? loadingStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleFade = CurvedAnimation(
      parent: fadeController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    final statusFade = CurvedAnimation(
      parent: fadeController,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    final titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(titleFade);
    final statusSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(statusFade);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: titleFade,
          child: SlideTransition(
            position: titleSlide,
            child: Text(
              appTitle,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: statusFade,
          child: SlideTransition(
            position: statusSlide,
            child: _LoadingStatusText(
              listenable: loadingStatus,
              style: theme.textTheme.bodyLarge?.copyWith(color: subtleColor),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingStatusText extends StatelessWidget {
  const _LoadingStatusText({required this.listenable, required this.style});

  final ValueListenable<String>? listenable;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final defaultText = Text('Loading...', style: style);
    final source = listenable;
    if (source == null) return defaultText;
    return ValueListenableBuilder<String>(
      valueListenable: source,
      builder: (context, value, _) {
        final display = value.isEmpty ? 'Loading...' : value;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, anim) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(anim);
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: Text(
            display,
            key: ValueKey<String>(display),
            style: style,
          ),
        );
      },
    );
  }
}
