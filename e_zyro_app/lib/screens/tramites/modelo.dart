// Paleta dinamica (_C), TramiteModel y catalogo tiposPermiso.
part of '../pantalla_tramites.dart';

// ─────────────────────────────────────────────
//  Paleta dinámica (light / dark)
// ─────────────────────────────────────────────

// MERGE "por valor" con lib/theme/ez_theme.dart (2026-07-13): cada constante
// quedó igualada al hex del token Ez equivalente, sin tocar los ~35 call-sites
// (varios en contexto const, que exige valores estáticos).
class _C {
  static const green = Color(0xFF8FD11B); // = ezLight.accent (ya coincidía)
  static const danger = Color(0xFFD6584F); // = ezLight.danger

  final bool isDark;
  final ColorScheme cs;

  _C(BuildContext context)
    : isDark = Theme.of(context).brightness == Brightness.dark,
      cs = Theme.of(context).colorScheme;

  Color get surface => cs.surface;
  Color get scaffoldBg =>
      isDark ? const Color(0xFF0E1611) : const Color(0xFFF3F1E6); // = ez canvas
  Color get surfaceHigh =>
      isDark ? const Color(0xFF1E2A23) : const Color(0xFFF5F4EA); // = ez surfaceAlt
  Color get border =>
      isDark ? const Color(0xFF26332B) : const Color(0xFFE4E1D1); // = ez hairline
  Color get inputBg =>
      isDark ? const Color(0xFF1E2A23) : const Color(0xFFF5F4EA); // = ez surfaceAlt
  Color get textPrimary => cs.onSurface;
  Color get textSecondary => cs.onSurface.withValues(alpha: 0.65);
  Color get textMuted => cs.onSurface.withValues(alpha: 0.40);

  ThemeData pickerTheme(BuildContext ctx) =>
      Theme.of(ctx).copyWith(colorScheme: cs.copyWith(primary: green));
}

// ─────────────────────────────────────────────
//  Modelo de datos
// ─────────────────────────────────────────────

class TramiteModel {
  int tipoPemiso;
  DateTime? fechaInicio;
  DateTime? fechaFin;
  TimeOfDay? horaInicio;
  TimeOfDay? horaFin;
  String sustento;

  TramiteModel({
    this.tipoPemiso = 1,
    this.fechaInicio,
    this.fechaFin,
    this.horaInicio,
    this.horaFin,
    this.sustento = '',
  });
}

const List<Map<String, dynamic>> tiposPermiso = [
  {'id': 1, 'label': '(1) Permiso personal'},
  {'id': 2, 'label': '(2) Comisión de Trabajo'},
  {'id': 3, 'label': '(3) Cita Essalud / Clínica'},
  {'id': 4, 'label': '(4) Permanencia Capacitación'},
  {'id': 5, 'label': '(5) Permanencia Extra (H)'},
  {'id': 6, 'label': '(6) Recuperación (H)'},
  {'id': 7, 'label': '(7) Vacaciones'},
  {'id': 8, 'label': '(8) Día(s) Libre(s)'},
  {'id': 9, 'label': '(9) Transferencia'},
  {'id': 10, 'label': '(10) Otros'},
];

