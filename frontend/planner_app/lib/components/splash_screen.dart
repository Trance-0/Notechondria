part of notechondria_frontend;

/// Splash screen showing an animated Citric acid cycle (Krebs cycle).
///
/// Molecules orbit a central ring, with byproducts (CO2, NADH, FADH2, GTP)
/// pulsing outward at their respective reaction steps. The animation loops
/// continuously until [onFinished] fires or 10 seconds elapse.
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
  // null means no notable byproduct at that step.
  static const _byproducts = <int, List<String>>{
    0: ['NADH'], // Oxaloacetate + Acetyl-CoA → Citrate (regeneration produces NADH)
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 300,
                height: 300,
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
                      size: const Size(300, 300),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.appTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Loading...',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: subtleColor,
                ),
              ),
            ],
          ),
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
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.36;
    final n = metabolites.length;

    // Draw orbit ring.
    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, ringPaint);

    // Draw connecting arrows between nodes.
    final arrowPaint = Paint()
      ..color = subtleColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var i = 0; i < n; i++) {
      final angle1 = -math.pi / 2 + (2 * math.pi * i / n);
      final angle2 = -math.pi / 2 + (2 * math.pi * ((i + 1) % n) / n);
      final p1 = center + Offset(math.cos(angle1), math.sin(angle1)) * radius;
      final p2 = center + Offset(math.cos(angle2), math.sin(angle2)) * radius;
      // Draw arc-like line between nodes.
      final midAngle = (angle1 + angle2) / 2;
      final cp = center +
          Offset(math.cos(midAngle), math.sin(midAngle)) * (radius * 0.85);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, p2.dx, p2.dy);
      canvas.drawPath(path, arrowPaint);
    }

    // Current active step (which metabolite the "glow" is on).
    final activeStep = (progress * n).floor() % n;
    final stepFraction = (progress * n) % 1.0;

    // Draw metabolite nodes.
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * radius;

      final isActive = i == activeStep;
      final nodeRadius = isActive ? 6.0 + 2.0 * math.sin(stepFraction * math.pi) : 4.5;
      final alpha = isActive ? 1.0 : 0.5;

      // Node dot.
      final dotPaint = Paint()
        ..color = nodeColor.withValues(alpha: alpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, nodeRadius, dotPaint);

      // Glow ring on active node.
      if (isActive) {
        final glowPaint = Paint()
          ..color = nodeColor.withValues(alpha: 0.25 * (1.0 - stepFraction))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawCircle(pos, nodeRadius + 4.0 + 6.0 * stepFraction, glowPaint);
      }

      // Label.
      final labelOffset = center +
          Offset(math.cos(angle), math.sin(angle)) * (radius + 18);
      _drawText(
        canvas,
        metabolites[i],
        labelOffset,
        isActive
            ? textColor
            : subtleColor.withValues(alpha: 0.6),
        isActive ? 10.0 : 9.0,
        isActive ? FontWeight.w600 : FontWeight.w400,
      );
    }

    // Draw byproducts flying outward from active step.
    if (byproducts.containsKey(activeStep)) {
      final products = byproducts[activeStep]!;
      final angle = -math.pi / 2 + (2 * math.pi * activeStep / n);
      for (var j = 0; j < products.length; j++) {
        final spread = (j - (products.length - 1) / 2) * 0.3;
        final flyAngle = angle + spread;
        final flyDist = radius + 40 + 25 * stepFraction;
        final flyPos = center +
            Offset(math.cos(flyAngle), math.sin(flyAngle)) * flyDist;
        final flyAlpha = (1.0 - stepFraction).clamp(0.0, 1.0);
        _drawText(
          canvas,
          products[j],
          flyPos,
          nodeColor.withValues(alpha: flyAlpha * 0.8),
          8.5,
          FontWeight.w600,
        );
      }
    }

    // Central label.
    _drawText(
      canvas,
      'Citric Acid\nCycle',
      center,
      subtleColor.withValues(alpha: 0.4),
      11.0,
      FontWeight.w500,
      textAlign: TextAlign.center,
    );

    // Acetyl-CoA arrow entering at Oxaloacetate/Citrate junction.
    final entryAngle = -math.pi / 2 + (2 * math.pi * 0 / n); // Citrate position
    final arrowStart = center +
        Offset(math.cos(entryAngle), math.sin(entryAngle)) * (radius + 45);
    final arrowEnd = center +
        Offset(math.cos(entryAngle), math.sin(entryAngle)) * (radius + 14);
    final entryPaint = Paint()
      ..color = nodeColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(arrowStart, arrowEnd, entryPaint);
    // Arrowhead.
    final headAngle = math.atan2(
        arrowEnd.dy - arrowStart.dy, arrowEnd.dx - arrowStart.dx);
    final headSize = 5.0;
    final headPath = Path()
      ..moveTo(arrowEnd.dx, arrowEnd.dy)
      ..lineTo(
        arrowEnd.dx - headSize * math.cos(headAngle - 0.4),
        arrowEnd.dy - headSize * math.sin(headAngle - 0.4),
      )
      ..lineTo(
        arrowEnd.dx - headSize * math.cos(headAngle + 0.4),
        arrowEnd.dy - headSize * math.sin(headAngle + 0.4),
      )
      ..close();
    canvas.drawPath(
        headPath,
        Paint()
          ..color = nodeColor.withValues(alpha: 0.5)
          ..style = PaintingStyle.fill);
    _drawText(
      canvas,
      'Acetyl-CoA',
      arrowStart + const Offset(0, -8),
      nodeColor.withValues(alpha: 0.6),
      8.5,
      FontWeight.w500,
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
  }) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        fontFamily: 'sans-serif',
        height: 1.2,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textAlign: textAlign,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_KrebsCyclePainter old) => old.progress != progress;
}
