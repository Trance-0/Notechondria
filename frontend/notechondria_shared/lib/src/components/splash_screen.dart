import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'splash_painter.dart';

/// Splash screen showing an animated Citric acid cycle (Krebs cycle).
///
/// The cycle axis is at the left center of the screen. It rotates to bring
/// each metabolite to the screen center. Each metabolite's structural
/// formula is anchored to its node and freely moves out of screen as the
/// cycle rotates - no English names are drawn next to the nodes. The
/// background is dotted with tiny rotating structural formulas of small
/// molecules that commonly accompany the cycle (H2O, CO2, NAD+, pyruvate
/// fragments, etc.). The version string in the bottom-left is supplied by
/// the host app via [appVersion] so each app can show its own
/// build-time-injected `--dart-define=APP_VERSION=...` value.
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
  late final AnimationController _cycleController;
  late final AnimationController _fadeController;
  bool _dismissed = false;

  static const _metabolites = [
    'Citrate',
    'Isocitrate',
    '\u03b1-Ketoglutarate',
    'Succinyl-CoA',
    'Succinate',
    'Fumarate',
    'Malate',
    'Oxaloacetate',
  ];

  static const _byproducts = <int, List<String>>{
    0: ['NADH'],
    2: ['CO\u2082', 'NADH'],
    3: ['CO\u2082', 'NADH'],
    4: ['GTP'],
    5: ['FADH\u2082'],
    7: ['NADH'],
  };

  late final List<SplashParticle> _particles;

  @override
  void initState() {
    super.initState();
    _cycleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16000),
    )..repeat();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    final rng = math.Random(42);
    _particles = List.generate(30, (_) {
      return SplashParticle(
        seedX: rng.nextDouble(),
        seedY: rng.nextDouble(),
        velocityX: (rng.nextDouble() - 0.5) * 0.6,
        velocityY: (rng.nextDouble() - 0.5) * 0.45,
        // Uniform size across all particles — the owner wanted every
        // particle (background + cycle-attached) to look the same
        // size, only the alpha should differ. A fixed scale of ~1.0x
        // reads about the same as the old 0.75–1.5 mid-range once
        // the alpha pulse takes effect in the painter.
        size: 1.0,
        rotation: rng.nextDouble() * 2 * math.pi,
        rotationSpeed: (rng.nextDouble() - 0.5) * 0.9,
        moleculeType: rng.nextInt(8),
        phase: rng.nextDouble() * 2 * math.pi,
      );
    });
  }

  @override
  void dispose() {
    _cycleController.dispose();
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
    final ringColor = theme.colorScheme.primary.withValues(alpha: 0.18);
    final nodeColor = theme.colorScheme.primary;
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
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _cycleController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: KrebsCyclePainter(
                          progress: _cycleController.value,
                          metabolites: _metabolites,
                          byproducts: _byproducts,
                          particles: _particles,
                          nodeColor: nodeColor,
                          ringColor: ringColor,
                          textColor: textColor,
                          subtleColor: subtleColor,
                          isDark: isDark,
                        ),
                      );
                    },
                  ),
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

