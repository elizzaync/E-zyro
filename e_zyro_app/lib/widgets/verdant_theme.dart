import 'package:flutter/material.dart';

/// Paleta compartida por las pantallas rediseñadas con el lenguaje visual
/// "Verdant" (hero verde bosque + lima de acento). Una instancia por
/// claro/oscuro, derivada de `Theme.of(context).brightness` — no es un tema
/// global de la app, solo el set de colores que usan estas pantallas.
class VerdantColors {
  final bool dark;
  final Color heroStart, heroEnd, heroSolid;
  final Color onHero, onHeroSub, heroChip, heroCard, heroBd;
  final Color lime, limeInk, linkc;
  final Color card, cardAlt, track, bd;
  final Color ink, sub, mut;
  final Color red, redBg, amb, ambBg, blu, bluBg, grn, grnBg;

  const VerdantColors._({
    required this.dark,
    required this.heroStart,
    required this.heroEnd,
    required this.heroSolid,
    required this.onHero,
    required this.onHeroSub,
    required this.heroChip,
    required this.heroCard,
    required this.heroBd,
    required this.lime,
    required this.limeInk,
    required this.linkc,
    required this.card,
    required this.cardAlt,
    required this.track,
    required this.bd,
    required this.ink,
    required this.sub,
    required this.mut,
    required this.red,
    required this.redBg,
    required this.amb,
    required this.ambBg,
    required this.blu,
    required this.bluBg,
    required this.grn,
    required this.grnBg,
  });

  factory VerdantColors.of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? _dark : _light;
  }

  static const _light = VerdantColors._(
    dark: false,
    heroStart: Color(0xFF2BA86E), heroEnd: Color(0xFF15824F), heroSolid: Color(0xFF1E9462),
    onHero: Colors.white, onHeroSub: Color(0xC2FFFFFF),
    heroChip: Color(0x29FFFFFF), heroCard: Color(0x24FFFFFF), heroBd: Color(0x42FFFFFF),
    lime: Color(0xFFC2F23B), limeInk: Color(0xFF163420), linkc: Color(0xFF2E7D32),
    card: Colors.white, cardAlt: Color(0xFFF1F4EC), track: Color(0xFFE6EBDF), bd: Color(0x12102818),
    ink: Color(0xFF15241A), sub: Color(0xFF56624F), mut: Color(0xFF8C9888),
    red: Color(0xFFD6584F), redBg: Color(0xFFFBE7E5),
    amb: Color(0xFFC58A1C), ambBg: Color(0xFFFAF1DA),
    blu: Color(0xFF3E80C0), bluBg: Color(0xFFE7F0FA),
    grn: Color(0xFF3E9A4E), grnBg: Color(0xFFE7F4E9),
  );

  static const _dark = VerdantColors._(
    dark: true,
    heroStart: Color(0xFF1F7A52), heroEnd: Color(0xFF165A3C), heroSolid: Color(0xFF1F7A52),
    onHero: Colors.white, onHeroSub: Color(0xB8FFFFFF),
    heroChip: Color(0x21FFFFFF), heroCard: Color(0x17FFFFFF), heroBd: Color(0x29FFFFFF),
    lime: Color(0xFFC2F23B), limeInk: Color(0xFF11281A), linkc: Color(0xFFC2F23B),
    card: Color(0xFF101A14), cardAlt: Color(0xFF17221B), track: Color(0xFF1E2A22), bd: Color(0x0FFFFFFF),
    ink: Color(0xFFE8F0E8), sub: Color(0xFF9AA89C), mut: Color(0xFF67756A),
    red: Color(0xFFE8807C), redBg: Color(0x33D6584F),
    amb: Color(0xFFE6B45A), ambBg: Color(0x38C58A1C),
    blu: Color(0xFF7FB0DD), bluBg: Color(0x383E80C0),
    grn: Color(0xFF6FC07E), grnBg: Color(0x383E9A4E),
  );

  Gradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [heroStart, heroEnd],
      );
}
