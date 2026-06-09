import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Gauge circular para mostrar los días de vacaciones disponibles.
/// Dibuja un anillo de progreso (disponible / máximo) con el número al centro.
class VacacionesGauge extends StatelessWidget {
  final double disponible;
  final double max; // tope de acumulación (o devengado total)
  final double size;
  final Color color;

  const VacacionesGauge({
    super.key,
    required this.disponible,
    required this.max,
    this.size = 180,
    this.color = const Color(0xFF14B8A6), // teal
  });

  @override
  Widget build(BuildContext context) {
    final frac = max > 0 ? (disponible / max).clamp(0.0, 1.0) : 0.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(fraction: frac, color: color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                disponible.toStringAsFixed(disponible % 1 == 0 ? 0 : 1),
                style: TextStyle(fontSize: size * 0.26, fontWeight: FontWeight.bold, color: color),
              ),
              Text('días disponibles',
                  style: TextStyle(fontSize: size * 0.075, color: Colors.black54)),
              if (max > 0)
                Text('de ${max.toStringAsFixed(0)} (tope)',
                    style: TextStyle(fontSize: size * 0.065, color: Colors.black38)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction;
  final Color color;

  _GaugePainter({required this.fraction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.12);
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [color.withValues(alpha: 0.6), color],
      ).createShader(rect);

    // Pista completa
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);
    // Progreso desde arriba (-90°)
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * fraction, false, progress);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.color != color;
}
