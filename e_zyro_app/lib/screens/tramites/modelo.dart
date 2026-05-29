// Paleta dinamica (_C), TramiteModel y catalogo tiposPermiso.
part of '../pantalla_tramites.dart';

// ─────────────────────────────────────────────
//  Paleta dinámica (light / dark)
// ─────────────────────────────────────────────

class _C {
  static const green = Color(0xFF8FD11B);
  static const danger = Color(0xFFEF4444);

  final bool isDark;
  final ColorScheme cs;

  _C(BuildContext context)
    : isDark = Theme.of(context).brightness == Brightness.dark,
      cs = Theme.of(context).colorScheme;

  Color get surface => cs.surface;
  Color get scaffoldBg =>
      isDark ? const Color(0xFF0F1117) : const Color(0xFFF5F5F5);
  Color get surfaceHigh =>
      isDark ? const Color(0xFF222636) : Colors.grey.shade100;
  Color get border =>
      isDark ? green.withValues(alpha: 0.28) : Colors.grey.shade200;
  Color get inputBg => isDark ? const Color(0xFF141620) : Colors.white;
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

