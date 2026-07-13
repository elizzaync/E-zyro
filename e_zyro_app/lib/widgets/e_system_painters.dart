// e_system_painters.dart
//
// Custom painters for the E-System TIC login hero:
//   • BoltPainter    — the lightning glyph inside the rounded badge
//   • TopoPainter    — drifting horizontal contour lines (subtle)
//   • ParticlePainter — radial sparks from the logo + ambient drift
//
// All single-pass paints, no shaders, suitable for 60fps on midrange devices.

import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
// BoltLogo — public widget wrapping BoltPainter inside a rounded
// lime square. Centralized here so the painter file owns the geometry.
// ─────────────────────────────────────────────────────────────
class BoltLogo extends StatelessWidget {
  final double size;
  final double radius;
  final Color background;
  final Color glyph;

  const BoltLogo({
    super.key,
    this.size = 42,
    this.radius = 12,
    this.background = const Color(0xFF8FD11B),
    this.glyph = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.46, size * 0.58),
          painter: BoltPainter(color: glyph),
        ),
      ),
    );
  }
}

class BoltPainter extends CustomPainter {
  final Color color;
  BoltPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeJoin = StrokeJoin.round;

    // Lightning bolt from viewBox 0 0 14 18:
    // M 9 1 L 2 10 H 6 L 5 17 L 12 8 H 8 L 9 1 z
    final p = Path()
      ..moveTo(9 / 14 * w, 1 / 18 * h)
      ..lineTo(2 / 14 * w, 10 / 18 * h)
      ..lineTo(6 / 14 * w, 10 / 18 * h)
      ..lineTo(5 / 14 * w, 17 / 18 * h)
      ..lineTo(12 / 14 * w, 8 / 18 * h)
      ..lineTo(8 / 14 * w, 8 / 18 * h)
      ..close();

    canvas.drawPath(p, fill);
    canvas.drawPath(p, stroke);
  }

  @override
  bool shouldRepaint(BoltPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────
// TopoPainter — sine-wave horizontal lines, slow drift.
// `t` is 0..1 from an AnimationController (use reverse:true loop).
// ─────────────────────────────────────────────────────────────
class TopoPainter extends CustomPainter {
  final double t;
  final double opacity;
  final int lineCount;

  TopoPainter({
    required this.t,
    this.opacity = 0.2,
    this.lineCount = 9,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Slow translation, ±10px horizontal, ±6px vertical
    final dx = math.sin(t * math.pi * 2) * 10;
    final dy = math.cos(t * math.pi * 2) * 6;
    canvas.save();
    canvas.translate(dx, dy);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: opacity)
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;

    final w = size.width + 60;
    final spacing = size.height / lineCount;

    for (int i = 0; i < lineCount; i++) {
      final y = 30 + i * spacing;
      final path = Path()..moveTo(-30, y);
      const segs = 18;
      for (int j = 0; j < segs; j++) {
        final x = -30 + j * (w / (segs - 1));
        final yy = y + math.sin(j * 0.7 + i) * 14;
        path.lineTo(x, yy);
      }
      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(TopoPainter old) =>
      old.t != t || old.opacity != opacity || old.lineCount != lineCount;
}

// ─────────────────────────────────────────────────────────────
// Particle — single spark definition.
//   Logo particles: animate from (originX, originY) outward by (dx, dy)
//   Ambient particles: animate from (x, y) by (dx, dy), with ambient=true
// `duration` is the loop length in seconds. `phase` (0..1) staggers them.
// ─────────────────────────────────────────────────────────────
class Particle {
  final double dx, dy;
  final double size;
  final double phase;    // 0..1, staggers each particle's cycle
  final double duration; // seconds — multiplies the painter's t cycle
  final double x, y;     // absolute starting offset (ambient only)
  final bool ambient;

  const Particle({
    required this.dx,
    required this.dy,
    required this.size,
    required this.phase,
    required this.duration,
    this.x = 0,
    this.y = 0,
    this.ambient = false,
  });
}

// ─────────────────────────────────────────────────────────────
// ParticlePainter — paints sparks with a fade-in/fade-out envelope.
//
// The AnimationController loops every ~5s. Each particle owns its
// `duration` and `phase`, so we map the controller's t to a per-particle
// progress and reuse the same controller for all particles.
// ─────────────────────────────────────────────────────────────
class ParticlePainter extends CustomPainter {
  final double t; // 0..1 from controller
  final List<Particle> particles;
  final List<Particle> ambient;
  final double originX;
  final double originY;
  final Color color;

  ParticlePainter({
    required this.t,
    required this.particles,
    required this.ambient,
    required this.originX,
    required this.originY,
    this.color = const Color(0xFF8FD11B),
  });

  // Master cycle of the controller in seconds. Must match what you
  // pass to AnimationController.duration in the screen.
  static const double _ctrlPeriodSec = 5.0;

  void _paintOne(Canvas canvas, Particle p,
      {required double oX, required double oY}) {
    // Map controller t to a per-particle 0..1 progress.
    final cycles = _ctrlPeriodSec / p.duration;
    final progress = ((t * cycles) + p.phase) % 1.0;

    // Opacity envelope: ramp-up 0→20%, hold to 80%, ramp-down to 100%
    double opacity;
    if (progress < 0.2) {
      opacity = (progress / 0.2) * 0.9;
    } else if (progress < 0.8) {
      opacity = 0.9;
    } else {
      opacity = (1 - (progress - 0.8) / 0.2) * 0.9;
    }
    if (opacity <= 0.01) return;

    final x = oX + p.dx * progress;
    final y = oY + p.dy * progress;

    // Soft halo
    final halo = Paint()
      ..color = color.withValues(alpha: opacity * 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 1.2);
    canvas.drawCircle(Offset(x, y), p.size * 1.4, halo);

    // Sharp core
    final core = Paint()..color = color.withValues(alpha: opacity);
    canvas.drawCircle(Offset(x, y), p.size * 0.7, core);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Logo-anchored radial particles
    for (final p in particles) {
      _paintOne(canvas, p, oX: originX, oY: originY);
    }
    // Ambient scattered particles (each has its own origin)
    for (final p in ambient) {
      _paintOne(canvas, p, oX: p.x, oY: p.y);
    }
  }

  @override
  bool shouldRepaint(ParticlePainter old) =>
      old.t != t || old.particles != particles || old.ambient != ambient;
}
