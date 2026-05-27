// Toolkit del estilo "Paper Dots" (bitácora): tarjetas con borde tinta grueso
// y sombra dura tipo sello (offset, sin blur), botones sello, stickers rotados,
// cinta washi y subrayado a mano. Tokens tomados de D:\paper-dots-style.
//
// Estilo permanente del Panel de Logística (pantalla_inventario_panel.dart).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Paleta ────────────────────────────────────────────────────────────────────
const Color kPaperPaper = Color(0xFFF8F6EE);
const Color kPaperInk = Color(0xFF2A2A26);
const Color kPaperInkSoft = Color(0xFF6B6864);
const Color kPaperLime = Color(0xFFA3E635);
const Color kPaperLimeDeep = Color(0xFF65A30D);
const Color kPaperWarm = Color(0xFFF0D090);
const Color kPaperHair = Color(0xFFDCD8C8);
const Color kPaperRose = Color(0xFFF4A89C);
const Color kPaperSky = Color(0xFFA8C8E8);
const Color kPaperLilac = Color(0xFFCDB6E6);

/// Decoración base "papel": fondo + borde 1.5px tinta + sombra dura (sin blur).
BoxDecoration paperCardDecoration({
  Color bg = Colors.white,
  Color? shadowColor,
  double radius = 12,
  double offset = 4,
  double borderWidth = 1.5,
}) {
  return BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: kPaperInk, width: borderWidth),
    boxShadow: [
      BoxShadow(
        color: shadowColor ?? kPaperInk,
        offset: Offset(offset, offset),
        blurRadius: 0,
      ),
    ],
  );
}

/// Tarjeta de papel reutilizable con rotación opcional y cinta/sticker.
class PaperCard extends StatelessWidget {
  final Widget child;
  final Color bg;
  final Color? shadowColor;
  final double radius;
  final double offset;
  final double rotate; // grados
  final EdgeInsetsGeometry padding;

  const PaperCard({
    super.key,
    required this.child,
    this.bg = Colors.white,
    this.shadowColor,
    this.radius = 12,
    this.offset = 4,
    this.rotate = 0,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: paperCardDecoration(
        bg: bg,
        shadowColor: shadowColor,
        radius: radius,
        offset: offset,
      ),
      child: child,
    );
    if (rotate == 0) return card;
    return Transform.rotate(angle: rotate * 3.1415926 / 180, child: card);
  }
}

/// Etiqueta "sticker" rotada (uppercase, mono).
class PaperSticker extends StatelessWidget {
  final String text;
  final Color bg;
  final double rotate;
  final Color color;

  const PaperSticker({
    super.key,
    required this.text,
    this.bg = kPaperWarm,
    this.rotate = -3,
    this.color = kPaperInk,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate * 3.1415926 / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), offset: Offset(0, 1)),
          ],
        ),
        child: Text(
          text.toUpperCase(),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Cinta washi decorativa (rayada).
class PaperTape extends StatelessWidget {
  final Color color;
  final double width;
  final double rotate;

  const PaperTape({
    super.key,
    this.color = kPaperWarm,
    this.width = 56,
    this.rotate = -3,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: rotate * 3.1415926 / 180,
      child: Container(
        width: width,
        height: 16,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), offset: Offset(0, 1), blurRadius: 2),
          ],
        ),
        child: CustomPaint(painter: _TapeStripesPainter()),
      ),
    );
  }
}

class _TapeStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x0D000000);
    for (double x = 0; x < size.width; x += 7) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Botón "sello": borde tinta + sombra dura. Variante lima (filled) o blanca.
class PaperButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool filled; // true = lima, false = blanco

  const PaperButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    final bg = filled ? kPaperLime : Colors.white;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kPaperInk, width: 1.5),
          boxShadow: const [
            BoxShadow(color: kPaperInk, offset: Offset(2, 2), blurRadius: 0),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: kPaperInk),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: kPaperInk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Subrayado dibujado a mano (garabato), bajo títulos de sección.
class PaperUnderline extends StatelessWidget {
  final double width;
  final Color color;
  const PaperUnderline({super.key, this.width = 80, this.color = kPaperLimeDeep});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, 8),
      painter: _UnderlinePainter(color),
    );
  }
}

class _UnderlinePainter extends CustomPainter {
  final Color color;
  const _UnderlinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final path = Path()..moveTo(2, 5);
    path.quadraticBezierTo(w * 0.18, 1, w * 0.35, 4);
    path.quadraticBezierTo(w * 0.52, 7, w * 0.68, 4);
    path.quadraticBezierTo(w * 0.84, 1, w - 2, 3);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Fondo "papel": color cálido + grid de puntos + viñeta sutil.
class PaperBackground extends StatelessWidget {
  final Widget child;
  const PaperBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: kPaperPaper)),
        Positioned.fill(child: CustomPaint(painter: _PaperDotsPainter())),
        child,
      ],
    );
  }
}

class _PaperDotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const step = 14.0;
    final dot = Paint()..color = kPaperInk.withValues(alpha: 0.13);
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.0, dot);
      }
    }
    final vignette = Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, const Color(0xFF463214).withValues(alpha: 0.06)],
        stops: const [0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Encabezado de sección estilo bitácora: título Outfit + subrayado + trailing.
class PaperSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final double underlineWidth;

  const PaperSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.underlineWidth = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kPaperInk,
              ),
            ),
            const SizedBox(height: 2),
            PaperUnderline(width: underlineWidth),
          ],
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              letterSpacing: 1,
              color: kPaperInkSoft,
            ),
          ),
      ],
    );
  }
}
