import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'reaction_defs.dart';
import 'reaction_simulator.dart';

/// Ambient reaction-simulator animation (TCA cycle particles drifting,
/// colliding, and reacting on a toroidal world). Fills its parent and
/// repaints from an internal [Ticker]; intended as the splash-screen
/// backdrop. Rendering port of the `index` repo's `renderer.js` +
/// `pictograms.js` (background gradient, tracking boxes, and theme
/// machinery dropped — the host's background and theme colors apply).
class ReactionSimulatorView extends StatefulWidget {
  const ReactionSimulatorView({super.key, this.opacity = 0.55});

  /// Overall paint opacity so the simulation reads as a backdrop
  /// behind the splash title rather than the main subject.
  final double opacity;

  @override
  State<ReactionSimulatorView> createState() => _ReactionSimulatorViewState();
}

class _ReactionSimulatorViewState extends State<ReactionSimulatorView>
    with SingleTickerProviderStateMixin {
  final ReactionSimulator _simulator = ReactionSimulator();
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _populationClock = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    // Clamp huge steps (first frame, tab resumed from background) so
    // particles don't teleport across the torus.
    if (dt <= 0 || dt > 0.1) dt = 1 / 60;
    _simulator.step(dt);
    _populationClock += dt;
    if (_populationClock >= 0.5) {
      _populationClock = 0;
      _simulator.populationTick();
    }
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      _simulator.setSize(constraints.maxWidth, constraints.maxHeight);
      return CustomPaint(
        painter: _ReactionPainter(
          simulator: _simulator,
          repaint: _frame,
          bondColor: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          badgeFill: theme.colorScheme.surfaceContainerHighest,
          badgeGlyphColor: theme.colorScheme.onSurface,
          opacity: widget.opacity,
        ),
        size: Size.infinite,
      );
    });
  }
}

class _ReactionPainter extends CustomPainter {
  _ReactionPainter({
    required this.simulator,
    required super.repaint,
    required this.bondColor,
    required this.badgeFill,
    required this.badgeGlyphColor,
    required this.opacity,
  });

  final ReactionSimulator simulator;
  final Color bondColor;
  final Color badgeFill;
  final Color badgeGlyphColor;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    for (final p in simulator.particles) {
      final def = simulator.defs[p.kind];
      if (def == null) continue;
      final a = p.alpha() * opacity;
      if (a <= 0.001) continue;
      _drawWrapped(canvas, p, def, a, w, h);
    }
    _drawBadges(canvas);
  }

  /// Draw wrap copies near each seam so a particle straddling the
  /// torus edge is never visually clipped.
  void _drawWrapped(Canvas canvas, SimParticle p, MoleculeDef def, double alpha,
      double w, double h) {
    final r = p.r;
    final offs = <(double, double)>[(0, 0)];
    if (p.x < r) offs.add((w, 0));
    if (p.x > w - r) offs.add((-w, 0));
    if (p.y < r) offs.add((0, h));
    if (p.y > h - r) offs.add((0, -h));
    if (p.x < r && p.y < r) offs.add((w, h));
    if (p.x > w - r && p.y < r) offs.add((-w, h));
    if (p.x < r && p.y > h - r) offs.add((w, -h));
    if (p.x > w - r && p.y > h - r) offs.add((-w, -h));
    for (final (ox, oy) in offs) {
      _drawAt(canvas, p, def, alpha, p.x + ox, p.y + oy);
    }
  }

  void _drawAt(Canvas canvas, SimParticle p, MoleculeDef def, double alpha,
      double x, double y) {
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(p.angle);
    final bondPaint = Paint()
      ..color = bondColor.withValues(alpha: bondColor.a * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final bond in def.bonds) {
      final a = def.atoms[bond.a];
      final b = def.atoms[bond.b];
      if (bond.order == 2) {
        final dx = b.dx - a.dx, dy = b.dy - a.dy;
        final d = math.sqrt(dx * dx + dy * dy);
        final dist = d == 0 ? 1.0 : d;
        final nx = -dy / dist * 1.6, ny = dx / dist * 1.6;
        canvas.drawLine(Offset(a.dx + nx, a.dy + ny),
            Offset(b.dx + nx, b.dy + ny), bondPaint);
        canvas.drawLine(Offset(a.dx - nx, a.dy - ny),
            Offset(b.dx - nx, b.dy - ny), bondPaint);
      } else {
        canvas.drawLine(Offset(a.dx, a.dy), Offset(b.dx, b.dy), bondPaint);
      }
    }
    for (final atom in def.atoms) {
      final style = atomStyle(atom.element);
      canvas.drawCircle(
        Offset(atom.dx, atom.dy),
        style.r,
        Paint()..color = style.fill.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        Offset(atom.dx, atom.dy),
        style.r,
        Paint()
          ..color = style.stroke.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }
    canvas.restore();
  }

  void _drawBadges(Canvas canvas) {
    for (final b in simulator.badges) {
      final fadeIn = math.min(1.0, b.t / 0.15);
      final fadeOut =
          1 - math.min(1.0, math.max(0.0, (b.t - (b.life - 0.3)) / 0.3));
      final a = math.min(fadeIn, fadeOut) * opacity;
      if (a <= 0.001) continue;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(b.x, b.y), width: 32, height: 22),
        const Radius.circular(11),
      );
      canvas.drawRRect(
          rect, Paint()..color = badgeFill.withValues(alpha: a * 0.95));
      _drawPictogram(canvas, b.glyph, b.x, b.y, a);
    }
  }

  /// Port of `pictograms.js` — tiny glyphs inside the reaction badges.
  void _drawPictogram(
      Canvas canvas, String name, double x, double y, double alpha) {
    final stroke = Paint()
      ..color = badgeGlyphColor.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Paint fillOf(Color c) => Paint()..color = c.withValues(alpha: alpha);
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);

    switch (name) {
      case 'plus':
        line(x - 5, y, x + 5, y);
        line(x, y - 5, x, y + 5);
      case 'arrow':
        line(x - 6, y, x + 5, y);
        line(x + 5, y, x + 1, y - 3);
        line(x + 5, y, x + 1, y + 3);
      case 'rotate':
        canvas.drawArc(Rect.fromCircle(center: Offset(x, y), radius: 5),
            math.pi * 0.2, math.pi * 1.5, false, stroke);
        line(x + 4, y - 3, x + 5, y + 1);
        line(x + 5, y + 1, x + 1, y);
      case 'co2_up':
        final cy = y + 2;
        canvas.drawCircle(
            Offset(x - 5, cy), 1.8, fillOf(const Color(0xFFC1574C)));
        canvas.drawCircle(
            Offset(x + 5, cy), 1.8, fillOf(const Color(0xFFC1574C)));
        canvas.drawCircle(Offset(x, cy), 1.8, fillOf(const Color(0xFF5E5E5E)));
        line(x - 4, y - 5, x, y - 8);
        line(x, y - 8, x + 4, y - 5);
      case 'h2o_in':
        canvas.drawCircle(Offset(x, y - 1), 2, fillOf(const Color(0xFFC1574C)));
        canvas.drawCircle(
            Offset(x - 4, y + 3), 1.5, fillOf(const Color(0xFFDCDCDC)));
        canvas.drawCircle(
            Offset(x + 4, y + 3), 1.5, fillOf(const Color(0xFFDCDCDC)));
        line(x - 4, y - 5, x, y - 2);
        line(x, y - 2, x + 4, y - 5);
      case 'h2_up':
        canvas.drawCircle(
            Offset(x - 3, y + 2), 1.8, fillOf(const Color(0xFFDCDCDC)));
        canvas.drawCircle(
            Offset(x + 3, y + 2), 1.8, fillOf(const Color(0xFFDCDCDC)));
        line(x - 4, y - 4, x, y - 7);
        line(x, y - 7, x + 4, y - 4);
      default:
        canvas.drawCircle(Offset(x, y), 3, stroke);
    }
  }

  @override
  bool shouldRepaint(_ReactionPainter oldDelegate) => true;
}
