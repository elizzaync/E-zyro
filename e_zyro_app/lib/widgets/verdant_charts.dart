import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Primitivas de gráfico reutilizadas por las pantallas rediseñadas con el
/// lenguaje visual "Verdant" (Asistencias, Desempeño, Evaluaciones,
/// Vacaciones): anillo de progreso, barra apilada, estrellas y sparkline.

/// Anillo de progreso con el valor centrado (p. ej. "78%" o "4.3").
class RingChart extends StatelessWidget {
  final double percent; // 0-100
  final double size;
  final double strokeWidth;
  final Color color;
  final Color track;
  final Color textColor;
  /// Texto a mostrar al centro. Si es null, usa "{percent.round()}{suffix}".
  final String? label;
  final String suffix;
  final double? fontSize;

  const RingChart({
    super.key,
    required this.percent,
    this.size = 64,
    this.strokeWidth = 7,
    required this.color,
    required this.track,
    required this.textColor,
    this.label,
    this.suffix = '%',
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final p = percent.clamp(0, 100).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
                percent: p, strokeWidth: strokeWidth, color: color, track: track),
          ),
          Text(
            label ?? '${p.round()}$suffix',
            style: GoogleFonts.spaceGrotesk(
              fontSize: fontSize ?? size * 0.27,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final double strokeWidth;
  final Color color;
  final Color track;

  _RingPainter({
    required this.percent,
    required this.strokeWidth,
    required this.color,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawArc(rect, 0, 2 * 3.14159265, false, trackPaint);

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = 2 * 3.14159265 * (percent / 100);
    canvas.drawArc(rect, -3.14159265 / 2, sweep, false, valuePaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.color != color || old.track != track;
}

/// Barra horizontal con segmentos proporcionales (uno por estado/categoría).
/// Los segmentos con valor 0 se omiten.
class StackBarChart extends StatelessWidget {
  final List<StackBarSegment> segments;
  final double height;
  final double radius;
  final double gap;

  const StackBarChart({
    super.key,
    required this.segments,
    this.height = 12,
    this.radius = 8,
    this.gap = 3,
  });

  @override
  Widget build(BuildContext context) {
    final visibles = segments.where((s) => s.value > 0).toList();
    if (visibles.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(height: height, child: Container(color: Colors.grey.withValues(alpha: 0.15))),
      );
    }
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var i = 0; i < visibles.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(
              flex: visibles[i].value.round().clamp(1, 1 << 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius / 2),
                child: Container(color: visibles[i].color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StackBarSegment {
  final double value;
  final Color color;
  const StackBarSegment(this.value, this.color);
}

/// Fila de 5 estrellas representando un valor 0-5 (redondeado al entero más cercano).
class StarRating extends StatelessWidget {
  final double value; // 0-5
  final Color color;
  final Color empty;
  final double size;

  const StarRating({
    super.key,
    required this.value,
    required this.color,
    required this.empty,
    this.size = 15,
  });

  @override
  Widget build(BuildContext context) {
    final filled = value.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i < filled ? color : empty,
          ),
        );
      }),
    );
  }
}

/// Mini gráfico de línea (tendencia). Requiere >= 2 puntos; el caller debe
/// decidir si lo omite cuando no hay historial suficiente.
class Sparkline extends StatelessWidget {
  final List<double> points;
  final Color color;
  final double width;
  final double height;
  final double strokeWidth;

  const Sparkline({
    super.key,
    required this.points,
    required this.color,
    this.width = 56,
    this.height = 22,
    this.strokeWidth = 2,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SparklinePainter(points: points, color: color, strokeWidth: strokeWidth),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> points;
  final Color color;
  final double strokeWidth;

  _SparklinePainter({required this.points, required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final minV = points.reduce((a, b) => a < b ? a : b);
    final maxV = points.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV) == 0 ? 1 : (maxV - minV);
    final step = size.width / (points.length - 1);

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i * step;
      final y = size.height - ((points[i] - minV) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points != points || old.color != color;
}
