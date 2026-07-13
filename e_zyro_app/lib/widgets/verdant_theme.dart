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

  // MERGE "por valor" con lib/theme/ez_theme.dart (2026-07-13): Verdant fue la
  // base del sistema Ez, así que la mayoría ya coincidía; se igualan los que
  // divergían (amb/warning, grn/success, cardAlt/surfaceAlt, track, sub, mut)
  // sin tocar a los consumidores.
  static const _light = VerdantColors._(
    dark: false,
    heroStart: Color(0xFF2BA86E), heroEnd: Color(0xFF15824F), heroSolid: Color(0xFF1E9462), // = ez brand/brandStrong
    onHero: Colors.white, onHeroSub: Color(0xC2FFFFFF),
    heroChip: Color(0x29FFFFFF), heroCard: Color(0x24FFFFFF), heroBd: Color(0x42FFFFFF),
    lime: Color(0xFF8FD11B), limeInk: Color(0xFF17240F), linkc: Color(0xFF1E9462), // = ez accent/onAccent/brand
    card: Colors.white, cardAlt: Color(0xFFF5F4EA), track: Color(0xFFECEADB), bd: Color(0xFFE4E1D1), // = ez surface/surfaceAlt/canvasSunken/hairline
    ink: Color(0xFF15241A), sub: Color(0xFF566B5E), mut: Color(0xFF8B968B), // = ez ink/inkSecondary/inkMuted
    red: Color(0xFFD6584F), redBg: Color(0xFFF7E1DF), // = ez danger/dangerSoft
    amb: Color(0xFFD98A16), ambBg: Color(0xFFF8ECD2), // = ez warning/warningSoft
    blu: Color(0xFF3E80C0), bluBg: Color(0xFFE0EAF4), // = ez info/infoSoft
    grn: Color(0xFF2F9E52), grnBg: Color(0xFFE1F1E4), // = ez success/successSoft
  );

  static const _dark = VerdantColors._(
    dark: true,
    heroStart: Color(0xFF2BA86E), heroEnd: Color(0xFF146848), heroSolid: Color(0xFF1F7A52), // = ez brandGradient dark
    onHero: Colors.white, onHeroSub: Color(0xB8FFFFFF),
    heroChip: Color(0x21FFFFFF), heroCard: Color(0x17FFFFFF), heroBd: Color(0x29FFFFFF),
    lime: Color(0xFFC2F23B), limeInk: Color(0xFF14210C), linkc: Color(0xFFC2F23B), // = ez accent/onAccent dark
    card: Color(0xFF16211B), cardAlt: Color(0xFF1E2A23), track: Color(0xFF0A100C), bd: Color(0xFF26332B), // = ez surface/surfaceAlt/canvasSunken/hairline dark
    ink: Color(0xFFE8F0E8), sub: Color(0xFFA7B5AC), mut: Color(0xFF6E7D73), // = ez ink/inkSecondary/inkMuted dark
    red: Color(0xFFE8807C), redBg: Color(0xFF2E1917), // = ez danger/dangerSoft dark
    amb: Color(0xFFE6B45A), ambBg: Color(0xFF2E2413), // = ez warning/warningSoft dark
    blu: Color(0xFF7FB0DD), bluBg: Color(0xFF14202B), // = ez info/infoSoft dark
    grn: Color(0xFF6FC07E), grnBg: Color(0xFF17281A), // = ez success/successSoft dark
  );

  Gradient get heroGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [heroStart, heroEnd],
      );
}
