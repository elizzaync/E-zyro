// topo_background.dart — Animated topographic-lines background.
// Ported from D:\flutter with E-zyro green palette as defaults.
// Usage: wrap any screen body with TopoBackground(child: ...)

import 'dart:math' as math;
import 'package:flutter/material.dart';

class TopoBackground extends StatefulWidget {
  /// Deep accent (line gradient end). Default: E-zyro forest green.
  final Color c1;

  /// Light accent (line gradient start). Default: E-zyro lime green.
  final Color c2;

  /// Base background color. Default: light green-cream.
  final Color base;

  /// Number of contour lines.
  final int count;

  /// Wave amplitude in logical pixels.
  final double amp;

  /// Base stroke width.
  final double stroke;

  /// Extra stroke width added every 3rd line.
  final double vary;

  /// 1.0 = 28s loop, 0.5 = ~56s (relaxed), 2.0 = ~14s (fast).
  final double speed;

  /// Optional child rendered on top of the background.
  final Widget? child;

  const TopoBackground({
    super.key,
    this.c1 = const Color(0xFF1E9462),
    this.c2 = const Color(0xFF8FD11B),
    this.base = const Color(0xFFF3F1E6),
    this.count = 26,
    this.amp = 14,
    this.stroke = 0.55,
    this.vary = 0.4,
    this.speed = 1.0,
    this.child,
  });

  @override
  State<TopoBackground> createState() => _TopoBackgroundState();
}

class _TopoBackgroundState extends State<TopoBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  Duration get _loop =>
      Duration(milliseconds: (28000 / widget.speed).clamp(2000, 120000).round());

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _loop)..repeat();
  }

  @override
  void didUpdateWidget(covariant TopoBackground old) {
    super.didUpdateWidget(old);
    if (widget.speed != old.speed) {
      _ctrl
        ..stop()
        ..duration = _loop
        ..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: widget.base),

        // Upper-right light glow
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0.4, -0.4),
              radius: 1.0,
              colors: [widget.c2.withValues(alpha:0.15), Colors.transparent],
              stops: const [0.0, 0.65],
            ),
          ),
        ),

        // Lower-left deep glow
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, 0.6),
              radius: 0.9,
              colors: [widget.c1.withValues(alpha:0.10), Colors.transparent],
              stops: const [0.0, 0.65],
            ),
          ),
        ),

        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) => CustomPaint(
              painter: _TopoPainter(
                t: _ctrl.value,
                c1: widget.c1,
                c2: widget.c2,
                count: widget.count,
                amp: widget.amp,
                stroke: widget.stroke,
                vary: widget.vary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),

        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _TopoPainter extends CustomPainter {
  final double t;
  final Color c1;
  final Color c2;
  final int count;
  final double amp;
  final double stroke;
  final double vary;

  _TopoPainter({
    required this.t,
    required this.c1,
    required this.c2,
    required this.count,
    required this.amp,
    required this.stroke,
    required this.vary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    final s = math.sin(t * 2 * math.pi);
    canvas.translate(-6 + 6 * s, 4 - 4 * s);

    final w = size.width;
    final h = size.height;
    final spacing = h / count;

    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [c2.withValues(alpha:0.55), c1.withValues(alpha:0.35)],
    ).createShader(Rect.fromLTWH(0, 0, w, h));

    const segCount = 22;
    for (int i = 0; i < count; i++) {
      final y = (i + 0.5) * spacing;
      final a = amp + (i % 4) * (amp * 0.3);
      final phase = i * 0.7;

      final path = Path()..moveTo(-50, y);
      for (int j = 0; j < segCount; j++) {
        final x = -50 + j * (w + 100) / (segCount - 1);
        final yy = y + math.sin(j * 0.55 + phase) * a;
        path.lineTo(x, yy);
      }

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (i % 3 == 0) ? stroke + vary : stroke
        ..shader = shader;

      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TopoPainter old) =>
      old.t != t ||
      old.c1 != c1 ||
      old.c2 != c2 ||
      old.count != count ||
      old.amp != amp ||
      old.stroke != stroke ||
      old.vary != vary;
}

/// Frosted-glass card to float on top of [TopoBackground].
/// Adapts automatically to light and dark mode.
class TopoGlassCard extends StatelessWidget {
  final Widget child;
  final double radius;

  const TopoGlassCard({super.key, required this.child, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF16211B).withValues(alpha:0.84)
              : const Color(0xFFFFFCF5).withValues(alpha:0.84),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isDark
                ? const Color(0xFF8FD11B).withValues(alpha:0.22)
                : const Color(0xFF1E9462).withValues(alpha:0.14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:isDark ? 0.24 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
