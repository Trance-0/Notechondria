part of notechondria_frontend;

/// Splash screen showing an animated Citric acid cycle (Krebs cycle).
///
/// The cycle axis is at the left center of the screen. It rotates to bring
/// each metabolite to the screen center. The active metabolite's structural
/// formula orbits with its node while text labels stay horizontal.
/// Light-weight randomised particles simulate a chemical environment.
class _SplashScreen extends StatefulWidget {
  const _SplashScreen({
    required this.appTitle,
    this.onFinished,
  });

  final String appTitle;
  final VoidCallback? onFinished;

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dismissed = false;

  // Citric acid cycle metabolites in order.
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

  // Byproducts emitted at each step.
  static const _byproducts = <int, List<String>>{
    0: ['NADH'],
    2: ['CO\u2082', 'NADH'],
    3: ['CO\u2082', 'NADH'],
    4: ['GTP'],
    5: ['FADH\u2082'],
    7: ['NADH'],
  };

  // Pre-generated particle seeds (angle, radius-fraction, speed-factor, size).
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 12000),
    )..repeat();
    // Generate randomised particles once.
    final rng = math.Random(42);
    _particles = List.generate(40, (_) {
      return _Particle(
        angle: rng.nextDouble() * 2 * math.pi,
        radiusFraction: 0.25 + rng.nextDouble() * 0.75,
        speed: 0.15 + rng.nextDouble() * 0.6,
        size: 1.5 + rng.nextDouble() * 3.0,
        drift: (rng.nextDouble() - 0.5) * 0.4,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    widget.onFinished?.call();
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
                    animation: _controller,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _KrebsCyclePainter(
                          progress: _controller.value,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.appTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Loading...',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: subtleColor,
                        ),
                      ),
                    ],
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

/// Immutable particle seed created once in initState.
class _Particle {
  const _Particle({
    required this.angle,
    required this.radiusFraction,
    required this.speed,
    required this.size,
    required this.drift,
  });
  final double angle;
  final double radiusFraction;
  final double speed;
  final double size;
  final double drift;
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

    // --- Particles (behind everything) ---
    _drawParticles(canvas, center, radius, w, h);

    // Orbit ring — thicker for visual weight.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );

    // Connecting arrows.
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

    // Metabolite nodes.
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

      // Small metabolite name near the node (always horizontal).
      final nameOffset =
          pos + Offset(math.cos(angle), math.sin(angle)) * (nr + 14);
      final cosA = math.cos(angle);
      _drawText(
        canvas,
        metabolites[i],
        nameOffset,
        (isActive ? textColor : subtleColor).withValues(
            alpha: (isActive ? 0.9 : 0.4) * fade),
        isActive ? 11.0 : 9.0,
        isActive ? FontWeight.w600 : FontWeight.w400,
        xAnchor: cosA > 0.3 ? 0.0 : (cosA < -0.3 ? 1.0 : 0.5),
      );
    }

    // Byproducts flying outward.
    if (byproducts.containsKey(activeStep)) {
      final products = byproducts[activeStep]!;
      final angle = 2 * math.pi * activeStep / n + rotationAngle;
      final base =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (base.dx > -30) {
        for (var j = 0; j < products.length; j++) {
          final spread = (j - (products.length - 1) / 2) * 0.3;
          final fa = angle + spread;
          final fd = radius + 65 + 30 * stepFraction;
          final fp = center + Offset(math.cos(fa), math.sin(fa)) * fd;
          final flyAlpha = (1.0 - stepFraction).clamp(0.0, 1.0);
          final cosF = math.cos(fa);
          _drawText(
            canvas,
            products[j],
            fp,
            nodeColor.withValues(alpha: flyAlpha * 0.8),
            13.0,
            FontWeight.w600,
            xAnchor: cosF > 0.3 ? 0.0 : (cosF < -0.3 ? 1.0 : 0.5),
          );
        }
      }
    }

    // Acetyl-CoA entry arrow.
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
      _drawText(
        canvas,
        'Acetyl-CoA',
        aStart + dir * 12,
        nodeColor.withValues(alpha: 0.6),
        11.0,
        FontWeight.w500,
        xAnchor: math.cos(ea) > 0.3 ? 0.0 : (math.cos(ea) < -0.3 ? 1.0 : 0.5),
      );
    }

    // -----------------------------------------------------------------------
    // Active metabolite: structural formula orbits with the active node.
    // The formula position follows the node but is offset outward so it
    // doesn't overlap the cycle ring. Text labels stay horizontal.
    // -----------------------------------------------------------------------
    final activeAngle = 2 * math.pi * activeStep / n + rotationAngle;
    final activePos =
        center + Offset(math.cos(activeAngle), math.sin(activeAngle)) * radius;

    // Only draw when the node is reasonably on-screen.
    if (activePos.dx > -30) {
      // Push the formula outward from the node, clamped to stay on screen.
      final outDir = Offset(math.cos(activeAngle), math.sin(activeAngle));
      final rawFormulaCenter = activePos + outDir * (radius * 0.38);
      final formulaCenter = Offset(
        rawFormulaCenter.dx.clamp(w * 0.15, w * 0.88),
        rawFormulaCenter.dy.clamp(h * 0.10, h * 0.85),
      );
      final formulaAlpha = (0.4 + 0.6 * math.sin(stepFraction * math.pi))
          .clamp(0.0, 1.0);
      _drawSkeletalFormula(
          canvas, activeStep, formulaCenter, formulaAlpha, w);
    }
  }

  // =========================================================================
  // Particle effects
  // =========================================================================

  void _drawParticles(
      Canvas canvas, Offset center, double radius, double w, double h) {
    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      // Each particle orbits at its own speed and radius.
      final angle = p.angle + progress * 2 * math.pi * p.speed;
      final r = radius * p.radiusFraction;
      final drift = math.sin(progress * 2 * math.pi * 3 + p.angle) * p.drift * radius * 0.15;
      final pos = center +
          Offset(math.cos(angle), math.sin(angle)) * r +
          Offset(0, drift);
      if (pos.dx < -20 || pos.dx > w + 20 || pos.dy < -20 || pos.dy > h + 20) {
        continue;
      }
      // Fade based on screen position.
      final fade = ((pos.dx + 20) / 100).clamp(0.0, 1.0);
      final alpha = (0.12 + 0.18 * math.sin(progress * 2 * math.pi * 2 + p.angle * 3))
          .clamp(0.0, 1.0) * fade;
      particlePaint.color = nodeColor.withValues(alpha: alpha);
      canvas.drawCircle(pos, p.size, particlePaint);
    }
  }

  // =========================================================================
  // 2-D skeletal structural formula drawing
  // =========================================================================

  void _drawSkeletalFormula(
    Canvas canvas,
    int index,
    Offset origin,
    double alpha,
    double canvasWidth,
  ) {
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
      case 0: // Citrate
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

      case 1: // Isocitrate
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

      case 2: // α-Ketoglutarate
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

      case 3: // Succinyl-CoA
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

      case 4: // Succinate
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

      case 5: // Fumarate
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

      case 6: // Malate
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

      case 7: // Oxaloacetate
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

    // Metabolite name label above the structure.
    _drawText(
      canvas,
      metabolites[index],
      origin + Offset(0, -bondLen * 1.8),
      nodeColor.withValues(alpha: alpha),
      fontSize * 1.4,
      FontWeight.w700,
    );
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
