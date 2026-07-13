// es_tokens.dart — Design tokens para el panel de Almacén/Logística unificado.
// Portado del prototipo "Style E · Material Friendly" (Plus Jakarta Sans,
// contenedores tonales, esquinas grandes), con el acento de Material alineado
// al VERDE DE MARCA de la app (#8FD11B). Equipo (índigo) y Compra (ámbar) se
// conservan del prototipo como código visual del tipo.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color tokens.
/// MERGE "por valor" con lib/theme/ez_theme.dart (ezLight, 2026-07-10): cada
/// constante de estado/superficie/texto quedó igualada al hex del token Ez
/// equivalente para que Almacén comparta paleta con el resto de la app sin
/// tocar es_widgets.dart ni los 8 consumidores. `equip`/`compra` (y sus *Bg,
/// y `matBg`) son colores de CATEGORÍA sin rol semántico en Ez — se dejan.
class ESC {
  // surfaces
  static const bg         = Color(0xFFF3F1E6); // = ezLight.canvas
  static const surface    = Color(0xFFFFFFFF); // = ezLight.surface (ya coincidía)
  static const surfaceAlt = Color(0xFFF7FAEF);
  static const line       = Color(0x141A2912); // ink @ ~8%
  static const lineStrong = Color(0x241A2912); // ink @ ~14%

  // brand (verde de marca de la app)
  static const brand     = Color(0xFF8FD11B); // = ezLight.accent (ya coincidía)
  static const brandDeep = Color(0xFF5E8C0E); // = ezLight.accentStrong (ya coincidía)
  static const lime      = Color(0xFF8FD11B);
  static const limeGlow  = Color(0xFF8FD11B);

  // type families — el código visual central
  static const mat       = Color(0xFF8FD11B); // Material (se consume) — = ezLight.accent
  static const matBg     = Color(0xFFE6F4CD); // categoría, sin *Soft equivalente en Ez — se deja
  static const equip     = Color(0xFF5145CD); // Equipo (se devuelve) — índigo, categoría sin rol semántico — se deja
  static const equipBg   = Color(0xFFE2E0FB); // categoría — se deja
  static const compra    = Color(0xFFC2620C); // Compra (procurement) — ámbar, categoría sin rol semántico — se deja
  static const compraBg  = Color(0xFFF7E3CD); // categoría — se deja

  // status (= pares estado/*Soft de ezLight)
  static const pend      = Color(0xFFD98A16); static const pendBg     = Color(0xFFF8ECD2); // = ezLight.warning/warningSoft
  static const aprob     = Color(0xFF3E80C0); static const aprobBg    = Color(0xFFE0EAF4); // = ezLight.info/infoSoft
  static const entreg    = Color(0xFF2F9E52); static const entregBg   = Color(0xFFE1F1E4); // = ezLight.success/successSoft
  static const devuelto  = Color(0xFF566B5E); static const devueltoBg = Color(0xFFECEADB); // = ezLight.inkSecondary / canvasSunken (sin inkSecondarySoft en Ez)
  static const vencido   = Color(0xFFD6584F); static const vencidoBg  = Color(0xFFF7E1DF); // = ezLight.danger/dangerSoft
  static const stock     = Color(0xFF3E80C0); static const stockBg    = Color(0xFFE0EAF4); // = ezLight.info/infoSoft
  static const nostock   = Color(0xFFD98A16); static const nostockBg  = Color(0xFFF8ECD2); // = ezLight.warning/warningSoft

  // text (= ezLight.ink/inkSecondary/inkMuted)
  static const ink       = Color(0xFF15241A);
  static const inkSub    = Color(0xFF566B5E);
  static const inkFaint  = Color(0xFF8B968B);

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
