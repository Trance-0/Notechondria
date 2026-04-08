part of notechondria_frontend;

/// Splash screen showing an animated Citric acid cycle (Krebs cycle).
///
/// The cycle axis is at the left center of the screen. It rotates to bring
/// each metabolite to the screen center, with byproducts pulsing outward.
/// All text remains horizontal. The animation loops until [onFinished] fires
/// or the user taps the screen.
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
    '\u03b1-Ketoglutarate', // α-Ketoglutarate
    'Succinyl-CoA',
    'Succinate',
    'Fumarate',
    'Malate',
    'Oxaloacetate',
  ];

  // Byproducts emitted at each step (index = step producing it).
  static const _byproducts = <int, List<String>>{
    0: ['NADH'], // Oxaloacetate + Acetyl-CoA → Citrate
    2: ['CO\u2082', 'NADH'], // Isocitrate → α-KG
    3: ['CO\u2082', 'NADH'], // α-KG → Succinyl-CoA
    4: ['GTP'], // Succinyl-CoA → Succinate
    5: ['FADH\u2082'], // Succinate → Fumarate
    7: ['NADH'], // Malate → Oxaloacetate
  };

  @override
  void initState() {
    super.initState();
    // One full cycle = 4 seconds, loops forever.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();
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

class _KrebsCyclePainter extends CustomPainter {
  _KrebsCyclePainter({
    required this.progress,
    required this.metabolites,
    required this.byproducts,
    required this.nodeColor,
    required this.ringColor,
    required this.textColor,
    required this.subtleColor,
    required this.isDark,
  });

  final double progress;
  final List<String> metabolites;
  final Map<int, List<String>> byproducts;
  final Color nodeColor;
  final Color ringColor;
  final Color textColor;
  final Color subtleColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Axis at left center of screen.
    final center = Offset(0, h / 2);
    final radius = w * 0.5;
    final n = metabolites.length;

    // Rotate so the active step is always at angle 0 (rightmost = screen center).
    final rotationAngle = -2 * math.pi * progress;

    // Orbit ring.
    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, ringPaint);

    // Connecting arrows between adjacent nodes.
    final arrowPaint = Paint()
      ..color = subtleColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

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
      // Smooth fade near the left screen edge.
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

      // Label — left-align on right side, right-align on left side.
      final cosA = math.cos(angle);
      final lbl = pos + Offset(math.cos(angle), math.sin(angle)) * (nr + 8);
      _drawText(
        canvas,
        metabolites[i],
        lbl,
        textColor.withValues(alpha: (isActive ? 1.0 : 0.6) * fade),
        isActive ? 16.0 : 14.0,
        isActive ? FontWeight.w600 : FontWeight.w400,
        xAnchor: cosA > 0.3 ? 0.0 : (cosA < -0.3 ? 1.0 : 0.5),
      );
    }

    // Byproducts flying outward from active step.
    if (byproducts.containsKey(activeStep)) {
      final products = byproducts[activeStep]!;
      final angle = 2 * math.pi * activeStep / n + rotationAngle;
      final base =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (base.dx > -30) {
        for (var j = 0; j < products.length; j++) {
          final spread = (j - (products.length - 1) / 2) * 0.3;
          final fa = angle + spread;
          final fd = radius + 45 + 30 * stepFraction;
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

    // "Citric Acid Cycle" label inside the visible arc.
    _drawText(
      canvas,
      'Citric Acid\nCycle',
      Offset(w * 0.22, h / 2),
      subtleColor.withValues(alpha: 0.3),
      18.0,
      FontWeight.w500,
      textAlign: TextAlign.center,
    );

    // Acetyl-CoA entry arrow (follows Citrate node as it rotates).
    final ea = rotationAngle; // index 0: 2π * 0 / n + rotation
    final ep = center + Offset(math.cos(ea), math.sin(ea)) * radius;
    if (ep.dx > -30) {
      final dir = Offset(math.cos(ea), math.sin(ea));
      final aStart = center + dir * (radius + 55);
      final aEnd = center + dir * (radius + 18);
      canvas.drawLine(
        aStart,
        aEnd,
        Paint()
          ..color = nodeColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      final ha =
          math.atan2(aEnd.dy - aStart.dy, aEnd.dx - aStart.dx);
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
      final cosE = math.cos(ea);
      _drawText(
        canvas,
        'Acetyl-CoA',
        aStart + dir * 12,
        nodeColor.withValues(alpha: 0.6),
        13.0,
        FontWeight.w500,
        xAnchor: cosE > 0.3 ? 0.0 : (cosE < -0.3 ? 1.0 : 0.5),
      );
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
