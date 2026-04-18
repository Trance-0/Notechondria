import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  late final List<_Particle> _particles;

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
      return _Particle(
        seedX: rng.nextDouble(),
        seedY: rng.nextDouble(),
        velocityX: (rng.nextDouble() - 0.5) * 0.6,
        velocityY: (rng.nextDouble() - 0.5) * 0.45,
        size: 0.75 + rng.nextDouble() * 0.75,
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
                        painter: _KrebsCyclePainter(
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

class _Particle {
  const _Particle({
    required this.seedX,
    required this.seedY,
    required this.velocityX,
    required this.velocityY,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    required this.moleculeType,
    required this.phase,
  });

  /// Initial position as a 0..1 fraction of the viewport width / height.
  /// The particle drifts away from this seed by `velocity * progress` and
  /// wraps at viewport edges so it visits the whole screen, not only the
  /// ring area.
  final double seedX;
  final double seedY;

  /// Drift in viewport fractions per full splash progress cycle. Total
  /// travel over one cycle = sqrt(vx^2 + vy^2) of the viewport's short
  /// side. Independent from the cycle's rotation.
  final double velocityX;
  final double velocityY;

  final double size;
  final double rotation;
  final double rotationSpeed;
  final int moleculeType;

  /// Shifts the particle's alpha-pulsing so neighbors don't strobe in
  /// unison.
  final double phase;
}

class _KrebsCyclePainter extends CustomPainter {
  _KrebsCyclePainter({
    required this.progress,
    required this.metabolites,
    required this.byproducts,
    required this.particles,
    required this.nodeColor,
    required this.ringColor,
    required this.textColor,
    required this.subtleColor,
    required this.isDark,
  });

  final double progress;
  final List<String> metabolites;
  final Map<int, List<String>> byproducts;
  final List<_Particle> particles;
  final Color nodeColor;
  final Color ringColor;
  final Color textColor;
  final Color subtleColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(0, h / 2);
    final radius = w * 0.5;
    final n = metabolites.length;
    final rotationAngle = -2 * math.pi * progress;

    _drawParticles(canvas, center, radius, w, h);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );

    final arrowPaint = Paint()
      ..color = subtleColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    for (var i = 0; i < n; i++) {
      final a1 = 2 * math.pi * i / n + rotationAngle;
      final a2 = 2 * math.pi * ((i + 1) % n) / n + rotationAngle;
      final p1 = center + Offset(math.cos(a1), math.sin(a1)) * radius;
      final p2 = center + Offset(math.cos(a2), math.sin(a2)) * radius;
      if (p1.dx < -60 && p2.dx < -60) continue;
      final mid = (a1 + a2) / 2;
      final cp =
          center + Offset(math.cos(mid), math.sin(mid)) * (radius * 0.85);
      canvas.drawPath(
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..quadraticBezierTo(cp.dx, cp.dy, p2.dx, p2.dy),
        arrowPaint,
      );
    }

    final activeStep = (progress * n).floor() % n;
    final stepFraction = (progress * n) % 1.0;

    for (var i = 0; i < n; i++) {
      final angle = 2 * math.pi * i / n + rotationAngle;
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (pos.dx < -60) continue;

      final isActive = i == activeStep;
      final nr =
          isActive ? 10.0 + 3.0 * math.sin(stepFraction * math.pi) : 7.0;
      final fade = ((pos.dx + 20) / 80).clamp(0.0, 1.0);

      canvas.drawCircle(
        pos,
        nr,
        Paint()
          ..color = nodeColor.withValues(alpha: (isActive ? 1.0 : 0.5) * fade)
          ..style = PaintingStyle.fill,
      );

      if (isActive) {
        canvas.drawCircle(
          pos,
          nr + 6.0 + 8.0 * stepFraction,
          Paint()
            ..color = nodeColor.withValues(
                alpha: 0.25 * (1.0 - stepFraction) * fade)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
    }

    if (byproducts.containsKey(activeStep)) {
      final products = byproducts[activeStep]!;
      final angle = 2 * math.pi * activeStep / n + rotationAngle;
      final base =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (base.dx > -30) {
        for (var j = 0; j < products.length; j++) {
          final spread = (j - (products.length - 1) / 2) * 0.3;
          final fa = angle + spread;
          final fd = radius + 75 + 35 * stepFraction;
          final fp = center + Offset(math.cos(fa), math.sin(fa)) * fd;
          final flyAlpha = (1.0 - stepFraction).clamp(0.0, 1.0);
          _drawByproductFormula(
            canvas,
            products[j],
            fp,
            flyAlpha,
          );
        }
      }
    }

    final ea = rotationAngle;
    final ep = center + Offset(math.cos(ea), math.sin(ea)) * radius;
    if (ep.dx > -30) {
      final dir = Offset(math.cos(ea), math.sin(ea));
      final aStart = center + dir * (radius + 75);
      final aEnd = center + dir * (radius + 18);
      canvas.drawLine(
        aStart,
        aEnd,
        Paint()
          ..color = nodeColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      final ha = math.atan2(aEnd.dy - aStart.dy, aEnd.dx - aStart.dx);
      canvas.drawPath(
        Path()
          ..moveTo(aEnd.dx, aEnd.dy)
          ..lineTo(aEnd.dx - 7 * math.cos(ha - 0.4),
              aEnd.dy - 7 * math.sin(ha - 0.4))
          ..lineTo(aEnd.dx - 7 * math.cos(ha + 0.4),
              aEnd.dy - 7 * math.sin(ha + 0.4))
          ..close(),
        Paint()
          ..color = nodeColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill,
      );
      _drawAcetylCoA(canvas, aStart, dir);
    }

    final activeAngle = 2 * math.pi * activeStep / n + rotationAngle;
    final activePos =
        center + Offset(math.cos(activeAngle), math.sin(activeAngle)) * radius;

    // Continuous morph between adjacent metabolites: the outgoing formula
    // fades only in the last third of its step, the incoming one starts
    // fading in at the same moment, and the previous formula lingers for
    // the first third of a new step. There is therefore always at least
    // one skeletal structure at near-full alpha on screen, with a window
    // of overlap in between. This fixes the mobile-view gap where the
    // former `sin(stepFraction * pi)` alpha curve dipped to 0 at each
    // step boundary.
    const crossFadeStart = 0.65; // outgoing begins to fade here
    const inheritanceCutoff = 0.35; // previous lingers until here

    double fadeOut(double t) =>
        t <= crossFadeStart ? 1.0 : 1.0 - (t - crossFadeStart) / (1.0 - crossFadeStart);
    double fadeIn(double t) =>
        t <= crossFadeStart ? 0.0 : (t - crossFadeStart) / (1.0 - crossFadeStart);
    double inheritAlpha(double t) =>
        t >= inheritanceCutoff ? 0.0 : 1.0 - t / inheritanceCutoff;

    void paintFormulaAt(int stepIndex, double alpha) {
      if (alpha <= 0.01) return;
      final angle = 2 * math.pi * stepIndex / n + rotationAngle;
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (pos.dx < -30) return;
      final outDir = Offset(math.cos(angle), math.sin(angle));
      final anchor = pos + outDir * (radius * 0.38);
      _drawSkeletalFormula(
        canvas,
        stepIndex,
        anchor,
        (0.35 + 0.55).clamp(0.0, 1.0) * alpha,
        w,
      );
    }

    if (activePos.dx > -30) {
      // Previous formula still partially visible at the very start of a
      // new step. Skip this on the wrap-around when stepIndex would map
      // to an off-screen node.
      final previousIndex = (activeStep - 1 + n) % n;
      paintFormulaAt(previousIndex, inheritAlpha(stepFraction));

      // Active formula: full alpha through most of the step, fading out
      // only in the final crossfade window.
      paintFormulaAt(activeStep, fadeOut(stepFraction));

      // Incoming next metabolite.
      final incomingIndex = (activeStep + 1) % n;
      paintFormulaAt(incomingIndex, fadeIn(stepFraction));
    }
  }

  void _drawParticles(
      Canvas canvas, Offset center, double radius, double w, double h) {
    // Particles wrap around an extended box so they never pop at the
    // viewport edge. `margin` keeps half a molecule's worth of padding
    // out of view on each side before wrapping.
    const margin = 60.0;
    final wrapW = w + margin * 2;
    final wrapH = h + margin * 2;
    for (final p in particles) {
      final driftX = math.sin(progress * 2 * math.pi + p.phase) * 0.04;
      final driftY = math.cos(progress * 2 * math.pi + p.phase * 0.7) * 0.04;
      final rawX = (p.seedX + p.velocityX * progress + driftX) % 1.0;
      final rawY = (p.seedY + p.velocityY * progress + driftY) % 1.0;
      final normX = rawX < 0 ? rawX + 1.0 : rawX;
      final normY = rawY < 0 ? rawY + 1.0 : rawY;
      final pos = Offset(
        normX * wrapW - margin,
        normY * wrapH - margin,
      );

      // Fade particles that overlap the cycle ring so they don't muddle
      // the skeletal formulas, but leave them visible everywhere else.
      final distanceFromRing = (pos - center).distance;
      final ringProximity =
          ((distanceFromRing - radius).abs() / 90.0).clamp(0.0, 1.0);
      final baseAlpha =
          (0.22 + 0.12 * math.sin(progress * 2 * math.pi * 2 + p.phase))
              .clamp(0.0, 1.0);
      final alpha = baseAlpha * (0.4 + 0.6 * ringProximity);

      final rotation =
          p.rotation + progress * 2 * math.pi * p.rotationSpeed;

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(rotation);
      _drawParticleMolecule(canvas, p.moleculeType, p.size, alpha);
      canvas.restore();
    }
  }

  void _drawParticleMolecule(
      Canvas canvas, int type, double scale, double alpha) {
    final bl = 7.0 * scale;
    final fs = 7.8 * scale;
    final bond = Paint()
      ..color = textColor.withValues(alpha: alpha * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final accent = nodeColor.withValues(alpha: alpha);
    final normal = textColor.withValues(alpha: alpha * 0.95);

    void line(Offset a, Offset b) => canvas.drawLine(a, b, bond);

    void doubleLine(Offset a, Offset b) {
      line(a, b);
      final d = b - a;
      final len = d.distance;
      if (len == 0) return;
      final perp = Offset(-d.dy, d.dx) / len * 1.9;
      line(a + perp, b + perp);
    }

    void lbl(String s, Offset pos, {Color? color, double? fsOverride}) {
      _drawText(canvas, s, pos, color ?? normal, fsOverride ?? fs,
          FontWeight.w600);
    }

    switch (type % 8) {
      case 0:
        line(Offset.zero, Offset(-bl, bl * 0.7));
        line(Offset.zero, Offset(bl, bl * 0.7));
        lbl('O', const Offset(0, -1), color: accent);
        lbl('H', Offset(-bl * 1.25, bl * 0.8));
        lbl('H', Offset(bl * 1.25, bl * 0.8));
        break;

      case 1:
        doubleLine(Offset(-bl * 1.1, 0), Offset(-bl * 0.25, 0));
        doubleLine(Offset(bl * 0.25, 0), Offset(bl * 1.1, 0));
        lbl('C', Offset.zero, color: accent);
        lbl('O', Offset(-bl * 1.7, 0));
        lbl('O', Offset(bl * 1.7, 0));
        break;

      case 2:
        const c = Offset.zero;
        line(Offset(-bl, bl * 0.5), c);
        doubleLine(c, Offset(0, -bl));
        line(c, Offset(bl, bl * 0.5));
        lbl('O', Offset(0, -bl * 1.7), color: accent);
        lbl('OH', Offset(bl * 1.55, bl * 0.6), color: accent);
        break;

      case 3:
        final c1 = Offset(-bl * 1.4, 0);
        final c2 = Offset(-bl * 0.3, bl * 0.5);
        final c3 = Offset(bl * 0.8, 0);
        line(c1, c2);
        line(c2, c3);
        doubleLine(c2, Offset(-bl * 0.4, -bl * 0.8));
        lbl('O', Offset(-bl * 0.4, -bl * 1.5), color: accent);
        lbl('H\u2083C', Offset(-bl * 2.1, -bl * 0.1));
        lbl('COOH', Offset(bl * 2.2, 0), color: accent);
        break;

      case 4:
        final rect = Rect.fromCenter(
            center: Offset.zero, width: bl * 3.6, height: bl * 1.7);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          bond,
        );
        lbl('NAD\u207a', Offset.zero,
            color: accent, fsOverride: fs * 0.85);
        break;

      case 5:
        for (var k = 0; k < 4; k++) {
          final a = k * math.pi / 2 + math.pi / 4;
          line(Offset.zero, Offset(math.cos(a), math.sin(a)) * bl);
        }
        lbl('P', Offset.zero, color: accent);
        break;

      case 6:
        canvas.drawCircle(Offset.zero, bl * 0.45, bond);
        lbl('H\u207a', Offset(bl * 1.35, 0), color: accent);
        break;

      case 7:
        final c1 = Offset(-bl, 0);
        final c2 = Offset(bl * 0.2, 0);
        line(c1, c2);
        doubleLine(c2, Offset(bl * 0.9, -bl * 0.8));
        lbl('O', Offset(bl * 0.9, -bl * 1.5), color: accent);
        lbl('H\u2083C', Offset(-bl * 1.8, 0));
        lbl('S-CoA', Offset(bl * 1.8, bl * 0.3), color: accent);
        break;
    }
  }

  /// Skeletal formula for acetyl-CoA feeding the cycle. Drawn at [origin]
  /// pointing inward along [dir] (unit vector from center outward).
  void _drawAcetylCoA(Canvas canvas, Offset origin, Offset dir) {
    const bondLen = 14.0;
    const fontSize = 11.0;
    final bondPaint = Paint()
      ..color = textColor.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final doublePaint = Paint()
      ..color = textColor.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final labelColor = textColor.withValues(alpha: 0.9);
    final accentColor = nodeColor.withValues(alpha: 0.85);

    final perp = Offset(-dir.dy, dir.dx);
    final outward = dir * -1;
    final step = outward * bondLen;

    final cMethyl = origin + outward * 6.0;
    final cCarbonyl = cMethyl + step;
    final sAtom = cCarbonyl + step;
    final coaAnchor = sAtom + step * 0.9;
    final oxo = cCarbonyl + perp * bondLen * 0.9;

    _drawText(canvas, 'H\u2083C', cMethyl - dir * 6.0, labelColor, fontSize,
        FontWeight.w700,
        xAnchor: dir.dx > 0.3 ? 0.0 : (dir.dx < -0.3 ? 1.0 : 0.5));
    canvas.drawLine(cMethyl + outward * 5.5, cCarbonyl - outward * 5.5, bondPaint);
    canvas.drawLine(
      cCarbonyl + perp * 2.5,
      oxo - perp * 2.5,
      bondPaint,
    );
    canvas.drawLine(
      cCarbonyl + perp * 2.5 + outward * 2.0,
      oxo - perp * 2.5 + outward * 2.0,
      doublePaint,
    );
    _drawText(canvas, 'O', oxo + perp * 6.0, accentColor, fontSize,
        FontWeight.w700);
    canvas.drawLine(cCarbonyl + outward * 5.5, sAtom - outward * 5.5, bondPaint);
    _drawText(canvas, 'S', sAtom, accentColor, fontSize, FontWeight.w700);
    canvas.drawLine(sAtom + outward * 5.5, coaAnchor - outward * 2.0, bondPaint);
    _drawText(canvas, 'CoA', coaAnchor + outward * 10.0, accentColor, fontSize,
        FontWeight.w700,
        xAnchor: dir.dx > 0.3 ? 1.0 : (dir.dx < -0.3 ? 0.0 : 0.5));
  }

  /// Compact schematic structural formula for a cycle byproduct. [origin] is
  /// the flight position; alpha fades with the step. No English names are
  /// drawn — just skeletal lines and element labels (O, N, P, H, etc.).
  void _drawByproductFormula(
      Canvas canvas, String species, Offset origin, double alpha) {
    if (alpha <= 0.02) return;
    final bond = Paint()
      ..color = textColor.withValues(alpha: alpha * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final bondSoft = Paint()
      ..color = textColor.withValues(alpha: alpha * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final accent = nodeColor.withValues(alpha: alpha * 0.9);
    final normal = textColor.withValues(alpha: alpha * 0.95);

    void line(Offset a, Offset b, {bool soft = false}) {
      canvas.drawLine(a, b, soft ? bondSoft : bond);
    }

    void doubleLine(Offset a, Offset b) {
      final d = b - a;
      final len = d.distance;
      if (len == 0) return;
      final perp = Offset(-d.dy, d.dx) / len * 2.0;
      line(a, b);
      line(a + perp, b + perp, soft: true);
    }

    void lbl(String s, Offset p, {Color? color, double size = 9.5}) {
      _drawText(canvas, s, origin + p, color ?? normal, size, FontWeight.w700);
    }

    void ringHexagon(Offset c, double r, {List<int> doubleEdges = const []}) {
      final pts = List<Offset>.generate(
        6,
        (k) => c +
            Offset(
              math.cos(math.pi / 6 + k * math.pi / 3),
              math.sin(math.pi / 6 + k * math.pi / 3),
            ) *
                r,
      );
      for (var k = 0; k < 6; k++) {
        final a = pts[k];
        final b = pts[(k + 1) % 6];
        if (doubleEdges.contains(k)) {
          doubleLine(a, b);
        } else {
          line(a, b);
        }
      }
    }

    switch (species) {
      case 'CO\u2082':
        const oLeft = Offset(-12, 0);
        const oRight = Offset(12, 0);
        doubleLine(origin + const Offset(-4, 0), origin + oLeft + const Offset(4, 0));
        doubleLine(origin + const Offset(4, 0), origin + oRight + const Offset(-4, 0));
        lbl('O', oLeft, color: accent);
        lbl('C', const Offset(0, 0));
        lbl('O', oRight, color: accent);
        break;

      case 'NADH':
        final ringC = origin + const Offset(-2, 0);
        ringHexagon(ringC, 8.5, doubleEdges: [1, 3]);
        lbl('N', Offset(ringC.dx - origin.dx + math.cos(math.pi / 6 + 5 * math.pi / 3) * 8.5,
                ringC.dy - origin.dy + math.sin(math.pi / 6 + 5 * math.pi / 3) * 8.5),
            color: accent,
            size: 8.5);
        final carbAnchor = ringC + const Offset(10, -3);
        line(ringC + const Offset(7.4, -4.2), carbAnchor);
        doubleLine(carbAnchor, carbAnchor + const Offset(3, -5));
        lbl('O', Offset(carbAnchor.dx - origin.dx + 4, carbAnchor.dy - origin.dy - 7),
            color: accent, size: 8.0);
        lbl('NH\u2082', Offset(carbAnchor.dx - origin.dx + 7, carbAnchor.dy - origin.dy + 2),
            color: accent, size: 7.5);
        lbl('H', Offset(ringC.dx - origin.dx, ringC.dy - origin.dy - 14),
            color: accent, size: 8.5);
        break;

      case 'FADH\u2082':
        final c = origin + const Offset(-4, 0);
        ringHexagon(c, 7.5, doubleEdges: [0, 2, 4]);
        final c2 = c + const Offset(13, 0);
        ringHexagon(c2, 7.5, doubleEdges: [1]);
        final sideN = c2 + const Offset(8, -4);
        line(c2 + const Offset(6.5, -4.2), sideN);
        lbl('N', Offset(sideN.dx - origin.dx, sideN.dy - origin.dy),
            color: accent, size: 8.0);
        final sideO = c + const Offset(-8, -4);
        doubleLine(c + const Offset(-6.5, -4.2), sideO);
        lbl('O', Offset(sideO.dx - origin.dx - 3, sideO.dy - origin.dy - 2),
            color: accent, size: 8.0);
        lbl('H', const Offset(-4, 11), color: accent, size: 8.0);
        lbl('H', const Offset(9, 11), color: accent, size: 8.0);
        break;

      case 'GTP':
        final purineC = origin + const Offset(-8, 0);
        ringHexagon(purineC, 6.5, doubleEdges: [1, 3]);
        final ring2c = purineC + const Offset(10.5, 1);
        final pts5 = List<Offset>.generate(
          5,
          (k) => ring2c +
              Offset(
                math.cos(-math.pi / 2 + k * 2 * math.pi / 5),
                math.sin(-math.pi / 2 + k * 2 * math.pi / 5),
              ) *
                  5.5,
        );
        for (var k = 0; k < 5; k++) {
          line(pts5[k], pts5[(k + 1) % 5]);
        }
        for (var i = 0; i < 3; i++) {
          final cx = 4.0 + i * 9.0;
          canvas.drawCircle(
            origin + Offset(cx, 8.5),
            2.8,
            Paint()
              ..color = accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
          if (i < 2) {
            line(
              origin + Offset(cx + 2.8, 8.5),
              origin + Offset(cx + 9.0 - 2.8, 8.5),
            );
          }
        }
        break;

      default:
        _drawText(canvas, species, origin,
            nodeColor.withValues(alpha: alpha * 0.8), 12.0, FontWeight.w600);
    }
  }

  void _drawSkeletalFormula(
    Canvas canvas,
    int index,
    Offset origin,
    double alpha,
    double canvasWidth,
  ) {
    if (alpha <= 0.01) return;
    final bondLen = (canvasWidth * 0.058).clamp(28.0, 48.0);
    final fontSize = (bondLen * 0.36).clamp(10.0, 16.0);
    final bondPaint = Paint()
      ..color = textColor.withValues(alpha: alpha * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final doubleBondPaint = Paint()
      ..color = textColor.withValues(alpha: alpha * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final labelColor = textColor.withValues(alpha: alpha);
    final accentColor = nodeColor.withValues(alpha: alpha * 0.9);

    const zigUp = Offset(1.0, -0.5);
    const zigDown = Offset(1.0, 0.5);

    Offset normalize(Offset o) {
      final len = o.distance;
      return len > 0 ? o / len : o;
    }

    Offset zig(Offset from, Offset dir) =>
        from + normalize(dir) * bondLen;

    void drawBond(Offset a, Offset b) {
      canvas.drawLine(a, b, bondPaint);
    }

    void drawDoubleBond(Offset a, Offset b) {
      canvas.drawLine(a, b, bondPaint);
      final perp = normalize(Offset(-(b.dy - a.dy), b.dx - a.dx)) * 4.0;
      canvas.drawLine(a + perp, b + perp, doubleBondPaint);
    }

    void label(Offset pos, String text, {double xAnchor = 0.5}) {
      _drawText(canvas, text, pos, labelColor, fontSize,
          FontWeight.w600, xAnchor: xAnchor);
    }

    void accentLabel(Offset pos, String text, {double xAnchor = 0.5}) {
      _drawText(canvas, text, pos, accentColor, fontSize,
          FontWeight.w700, xAnchor: xAnchor);
    }

    final branchUp = Offset(0, -bondLen * 0.55);
    final branchDown = Offset(0, bondLen * 0.55);

    switch (index) {
      case 0:
        final c1 = origin + Offset(-bondLen * 2.5, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        final c5 = zig(c4, zigUp);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        label(c2 + branchDown * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c2, c3);
        drawBond(c3, c4);
        label(c4 + branchDown * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c4, c5);
        label(c5 + const Offset(8, 0), 'COOH', xAnchor: 0.0);
        final brUp = c3 + branchUp;
        drawBond(c3, brUp);
        accentLabel(brUp + branchUp * 0.4, 'COOH');
        final brDn = c3 + branchDown;
        drawBond(c3, brDn);
        accentLabel(brDn + branchDown * 0.4, 'OH');
        break;

      case 1:
        final c1 = origin + Offset(-bondLen * 2.5, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        final c5 = zig(c4, zigUp);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        label(c2 + branchDown * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c2, c3);
        drawBond(c3, c4);
        drawBond(c4, c5);
        label(c5 + const Offset(8, 0), 'COOH', xAnchor: 0.0);
        final brUp = c3 + branchUp;
        drawBond(c3, brUp);
        accentLabel(brUp + branchUp * 0.4, 'COOH');
        final brDn4 = c4 + branchDown;
        drawBond(c4, brDn4);
        accentLabel(brDn4 + branchDown * 0.4, 'OH');
        break;

      case 2:
        final c1 = origin + Offset(-bondLen * 2.0, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        final c5 = zig(c4, zigUp);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        label(c2 + branchDown * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c2, c3);
        label(c3 + branchUp * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c3, c4);
        final oxo = c4 + branchDown;
        drawDoubleBond(c4, oxo);
        accentLabel(oxo + branchDown * 0.4, 'O');
        drawBond(c4, c5);
        label(c5 + const Offset(8, 0), 'COOH', xAnchor: 0.0);
        break;

      case 3:
        final c1 = origin + Offset(-bondLen * 2.5, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        final c5 = zig(c4, zigUp);
        final c6 = zig(c5, zigDown);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        label(c2 + branchDown * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c2, c3);
        label(c3 + branchUp * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c3, c4);
        final oxo = c4 + branchDown;
        drawDoubleBond(c4, oxo);
        accentLabel(oxo + branchDown * 0.4, 'O');
        drawBond(c4, c5);
        accentLabel(c5 + branchUp * 0.5, 'S', xAnchor: 0.5);
        drawBond(c5, c6);
        label(c6 + const Offset(8, 0), 'CoA', xAnchor: 0.0);
        break;

      case 4:
        final c1 = origin + Offset(-bondLen * 1.5, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        label(c2 + branchDown * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c2, c3);
        label(c3 + branchUp * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c3, c4);
        label(c4 + const Offset(8, 0), 'COOH', xAnchor: 0.0);
        break;

      case 5:
        final c1 = origin + Offset(-bondLen * 1.5, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        drawDoubleBond(c2, c3);
        accentLabel(
          Offset((c2.dx + c3.dx) / 2, (c2.dy + c3.dy) / 2) + branchUp * 0.6,
          'trans',
          xAnchor: 0.5,
        );
        drawBond(c3, c4);
        label(c4 + const Offset(8, 0), 'COOH', xAnchor: 0.0);
        break;

      case 6:
        final c1 = origin + Offset(-bondLen * 1.5, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        label(c2 + branchDown * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c2, c3);
        drawBond(c3, c4);
        label(c4 + const Offset(8, 0), 'COOH', xAnchor: 0.0);
        final brDn3 = c3 + branchUp;
        drawBond(c3, brDn3);
        accentLabel(brDn3 + branchUp * 0.4, 'OH');
        break;

      case 7:
        final c1 = origin + Offset(-bondLen * 1.5, 0);
        final c2 = zig(c1, zigDown);
        final c3 = zig(c2, zigUp);
        final c4 = zig(c3, zigDown);
        label(c1 + const Offset(-8, 0), 'HOOC', xAnchor: 1.0);
        drawBond(c1, c2);
        final oxo = c2 + branchDown;
        drawDoubleBond(c2, oxo);
        accentLabel(oxo + branchDown * 0.4, 'O');
        drawBond(c2, c3);
        label(c3 + branchUp * 0.5, 'H\u2082', xAnchor: 0.5);
        drawBond(c3, c4);
        label(c4 + const Offset(8, 0), 'COOH', xAnchor: 0.0);
        break;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position,
    Color color,
    double fontSize,
    FontWeight fontWeight, {
    TextAlign textAlign = TextAlign.center,
    double xAnchor = 0.5,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontFamily: 'sans-serif',
          height: 1.2,
        ),
      ),
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position - Offset(tp.width * xAnchor, tp.height / 2));
  }

  @override
  bool shouldRepaint(_KrebsCyclePainter old) => old.progress != progress;
}
