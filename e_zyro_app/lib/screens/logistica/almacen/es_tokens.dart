// es_tokens.dart — Design tokens para el panel de Almacén/Logística unificado.
// Portado del prototipo "Style E · Material Friendly" (Plus Jakarta Sans,
// contenedores tonales, esquinas grandes), con el acento de Material alineado
// al VERDE DE MARCA de la app (#8FD11B). Equipo (índigo) y Compra (ámbar) se
// conservan del prototipo como código visual del tipo.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color tokens.
class ESC {
  // surfaces
  static const bg         = Color(0xFFEEF4E4);
  static const surface    = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF7FAEF);
  static const line       = Color(0x141A2912); // ink @ ~8%
  static const lineStrong = Color(0x241A2912); // ink @ ~14%

  // brand (verde de marca de la app)
  static const brand     = Color(0xFF8FD11B);
  static const brandDeep = Color(0xFF5E8C0E);
  static const lime      = Color(0xFF8FD11B);
  static const limeGlow  = Color(0xFFA3E635);

  // type families — el código visual central
  static const mat       = Color(0xFF8FD11B); // Material (se consume) — verde marca
  static const matBg     = Color(0xFFE6F4CD);
  static const equip     = Color(0xFF5145CD); // Equipo (se devuelve) — índigo
  static const equipBg   = Color(0xFFE2E0FB);
  static const compra    = Color(0xFFC2620C); // Compra (procurement) — ámbar
  static const compraBg  = Color(0xFFF7E3CD);

  // status
  static const pend      = Color(0xFFB45309); static const pendBg     = Color(0xFFFDECCC);
  static const aprob     = Color(0xFF1D4ED8); static const aprobBg    = Color(0xFFDBE7FE);
  static const entreg    = Color(0xFF15803D); static const entregBg   = Color(0xFFD7F0DB);
  static const devuelto  = Color(0xFF475569); static const devueltoBg = Color(0xFFE6EAF0);
  static const vencido   = Color(0xFFDC2626); static const vencidoBg  = Color(0xFFFDE0E0);
  static const stock     = Color(0xFF0E7490); static const stockBg    = Color(0xFFCDEEF3);
  static const nostock   = Color(0xFFD9620A); static const nostockBg  = Color(0xFFFCE3CF);

  // text
  static const ink       = Color(0xFF1A2912);
  static const inkSub    = Color(0xFF5D6E4C);
  static const inkFaint  = Color(0xFF8C9B7A);

  static const radius    = 24.0;
}

/// Tinte tonal suave de un color (para tarjetas/contenedores tonales).
Color esTint(Color c, double a) => c.withValues(alpha: a);

/// Helper de estilo Plus Jakarta Sans — garantiza la fuente de marca.
TextStyle pj({
  double size = 14,
  FontWeight weight = FontWeight.w500,
  Color color = ESC.ink,
  double spacing = 0,
  double height = 1.2,
}) =>
    GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
    );

/// Estado → (foreground, background).
({Color fg, Color bg}) esStatusColors(String status) {
  switch (status) {
    case 'Pendiente':   return (fg: ESC.pend,     bg: ESC.pendBg);
    case 'Aprobada':    return (fg: ESC.aprob,    bg: ESC.aprobBg);
    case 'Entregada':   return (fg: ESC.entreg,   bg: ESC.entregBg);
    case 'Devuelto':    return (fg: ESC.devuelto, bg: ESC.devueltoBg);
    case 'Vencido':     return (fg: ESC.vencido,  bg: ESC.vencidoBg);
    case 'Rechazado':   return (fg: ESC.vencido,  bg: ESC.vencidoBg);
    case 'En préstamo': return (fg: ESC.equip,    bg: ESC.equipBg);
    default:            return (fg: ESC.inkSub,   bg: ESC.line);
  }
}
