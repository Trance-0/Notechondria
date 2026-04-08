part of notechondria_frontend;

/// Splash screen showing an animated Citric acid cycle (Krebs cycle).
///
/// The cycle axis is at the left center of the screen. It rotates to bring
/// each metabolite to the screen center, with byproducts pulsing outward.
/// Metabolites are shown as simplified structural formulas. The animation
/// loops until [onFinished] fires or the user taps the screen.
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

  @override
  void initState() {
    super.initState();
    // One full cycle = 8 seconds, loops forever.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
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
    final center = Offset(0, h / 2);
    final radius = w * 0.5;
    final n = metabolites.length;
    final rotationAngle = -2 * math.pi * progress;

    // Orbit ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Connecting arrows.
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

    // Metabolite nodes with structural formulas.
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

      // Structural formula drawn near the node.
      final cosA = math.cos(angle);
      final formulaCenter =
          pos + Offset(math.cos(angle), math.sin(angle)) * (nr + 40);
      final formulaAlpha = (isActive ? 1.0 : 0.5) * fade;
      final scale = isActive ? 1.0 : 0.8;
      _drawStructuralFormula(
        canvas,
        i,
        formulaCenter,
        formulaAlpha,
        scale,
        cosA,
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
      // Acetyl-CoA structural: CH₃-C(=O)-S-CoA
      _drawText(
        canvas,
        'CH\u2083\u2013CO\u2013S\u2013CoA',
        aStart + dir * 12,
        nodeColor.withValues(alpha: 0.6),
        11.0,
        FontWeight.w500,
        xAnchor: math.cos(ea) > 0.3 ? 0.0 : (math.cos(ea) < -0.3 ? 1.0 : 0.5),
      );
    }
  }

  /// Draws a simplified structural formula for the metabolite at [index].
  /// Each formula shows the carbon backbone with key functional groups using
  /// standard chemical notation (COOH, C=O, OH, CoA, etc.).
  void _drawStructuralFormula(
    Canvas canvas,
    int index,
    Offset center,
    double alpha,
    double scale,
    double cosAngle,
  ) {
    final color = textColor.withValues(alpha: alpha);
    final fs = 9.0 * scale;

    // Horizontal anchor: formulas are drawn left-to-right from an anchor.
    // Shift so the formula doesn't overlap the node.
    final xAnchor = cosAngle > 0.3 ? 0.0 : (cosAngle < -0.3 ? 1.0 : 0.5);

    switch (index) {
      case 0: // Citrate: HOOC-CH₂-C(OH)(COOH)-CH₂-COOH
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CH\u2082', '\u2013', 'C', '(OH)', '\u2013',
          'CH\u2082', '\u2013', 'COOH',
        ], color, fs, xAnchor);
        // Mark the middle C with a branch: COOH going up
        final midX = center.dx + (xAnchor == 0.0 ? 42 * scale : -12 * scale);
        _drawText(canvas, '|', Offset(midX, center.dy - 6 * scale),
            color.withValues(alpha: alpha * 0.6), fs * 0.8, FontWeight.w400);
        _drawText(canvas, 'COOH', Offset(midX, center.dy - 14 * scale),
            color, fs * 0.8, FontWeight.w500);
        break;

      case 1: // Isocitrate: HOOC-CH₂-CH(COOH)-CH(OH)-COOH
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CH\u2082', '\u2013', 'CH', '\u2013', 'CH',
          '(OH)', '\u2013', 'COOH',
        ], color, fs, xAnchor);
        final midX = center.dx + (xAnchor == 0.0 ? 36 * scale : -18 * scale);
        _drawText(canvas, '|', Offset(midX, center.dy - 6 * scale),
            color.withValues(alpha: alpha * 0.6), fs * 0.8, FontWeight.w400);
        _drawText(canvas, 'COOH', Offset(midX, center.dy - 14 * scale),
            color, fs * 0.8, FontWeight.w500);
        break;

      case 2: // α-Ketoglutarate: HOOC-CH₂-CH₂-CO-COOH
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CH\u2082', '\u2013', 'CH\u2082', '\u2013',
          'CO', '\u2013', 'COOH',
        ], color, fs, xAnchor);
        // Double-bond indicator above CO
        final coX = center.dx + (xAnchor == 0.0 ? 48 * scale : -8 * scale);
        _drawText(canvas, '=O', Offset(coX, center.dy - 10 * scale),
            color, fs * 0.8, FontWeight.w500);
        break;

      case 3: // Succinyl-CoA: HOOC-CH₂-CH₂-CO-S-CoA
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CH\u2082', '\u2013', 'CH\u2082', '\u2013',
          'CO', '\u2013', 'S', '\u2013', 'CoA',
        ], color, fs, xAnchor);
        break;

      case 4: // Succinate: HOOC-CH₂-CH₂-COOH
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CH\u2082', '\u2013', 'CH\u2082', '\u2013',
          'COOH',
        ], color, fs, xAnchor);
        break;

      case 5: // Fumarate: HOOC-CH=CH-COOH (trans)
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CH', '=', 'CH', '\u2013', 'COOH',
        ], color, fs, xAnchor);
        break;

      case 6: // Malate: HOOC-CH₂-CH(OH)-COOH
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CH\u2082', '\u2013', 'CH', '(OH)', '\u2013',
          'COOH',
        ], color, fs, xAnchor);
        break;

      case 7: // Oxaloacetate: HOOC-CO-CH₂-COOH
        _drawFormulaLine(canvas, center, [
          'HOOC', '\u2013', 'CO', '\u2013', 'CH\u2082', '\u2013', 'COOH',
        ], color, fs, xAnchor);
        final coX = center.dx + (xAnchor == 0.0 ? 20 * scale : -32 * scale);
        _drawText(canvas, '=O', Offset(coX, center.dy - 10 * scale),
            color, fs * 0.8, FontWeight.w500);
        break;
    }
  }

  /// Renders a horizontal formula as a sequence of text segments.
  void _drawFormulaLine(
    Canvas canvas,
    Offset center,
    List<String> parts,
    Color color,
    double fontSize,
    double xAnchor,
  ) {
    // Measure total width first.
    double totalWidth = 0;
    final widths = <double>[];
    for (final part in parts) {
      final tp = TextPainter(
        text: TextSpan(
          text: part,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
            fontFamily: 'sans-serif',
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      widths.add(tp.width);
      totalWidth += tp.width;
    }
    double x = center.dx - totalWidth * xAnchor;
    final y = center.dy;
    for (var i = 0; i < parts.length; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: parts[i],
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: parts[i].length > 1 ? FontWeight.w500 : FontWeight.w400,
            fontFamily: 'sans-serif',
            height: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y - tp.height / 2));
      x += widths[i];
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
