// ============================================================================
//  E-Zyro · Sistema de Diseño unificado v1.0
//  Un solo archivo de tokens + ThemeData + helpers de componente.
//
//  Reemplaza a los 9 sistemas previos (Verdant, Style E, Paper, Portal claro/
//  oscuro, Ficha Colaborador, Mi Espacio, _C Trámites, Finanzas suelto).
//
//  USO
//  1. En MaterialApp:
//        theme:      buildEzTheme(ezLight),
//        darkTheme:  buildEzTheme(ezDark),
//        themeMode:  ThemeMode.system,
//  2. En cualquier widget:
//        final c = context.ez;            // -> EzColors del tema activo
//        color: c.brand, ...
//  3. Componentes:
//        EzButton.primary('Guardar', onPressed: ...)
//        EzCard(child: ...)
//        EzStatusChip.success('Entregado')
//
//  FUENTES (pubspec.yaml -> google_fonts, o assets propios):
//     'Plus Jakarta Sans'  -> texto / UI
//     'JetBrains Mono'     -> datos, montos, códigos (tabular)
//  Objetivo de toque mínimo: 48 px.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================================================
//  1 · COLOR  (ThemeExtension -> viaja dentro de ThemeData)
// ============================================================================

@immutable
class EzColors extends ThemeExtension<EzColors> {
  // --- Marca & acción ---
  final Color brand;          // esmeralda: marca, headers, estructura
  final Color brandStrong;    // esmeralda profundo: fin del gradiente, hover
  final Color brandSoft;      // tinte de marca: fondos suaves, chips brand
  final Color accent;         // lima: ACCIÓN primaria, FAB (una por pantalla)
  final Color accentStrong;   // lima profundo: pressed / borde de accent
  final Color accentSoft;     // tinte lima: fondos suaves
  final Color onAccent;       // ink oscuro que va SOBRE accent (nunca blanco)

  // --- Superficie & texto ---
  final Color canvas;         // fondo de pantalla (crema en claro)
  final Color canvasSunken;   // fondo hundido / track de barras
  final Color surface;        // tarjetas, sheets
  final Color surfaceAlt;     // superficie secundaria / inputs
  final Color hairline;       // bordes y divisores
  final Color ink;            // texto primario
  final Color inkSecondary;   // texto secundario
  final Color inkMuted;       // texto terciario / placeholder

  // --- Estado semántico (par: pleno + tinte suave) ---
  final Color success;        final Color successSoft;   // completado, aprobado, entregado
  final Color warning;        final Color warningSoft;   // pendiente, tardanza, por revisar
  final Color danger;         final Color dangerSoft;    // eliminar, vencido, error
  final Color info;           final Color infoSoft;      // en proceso, informativo

  // --- Única desviación externa (Portal / cliente) ---
  final Color brandExternal;  // en superficies del Portal, brand := brandExternal

  final bool isDark;

  const EzColors({
    required this.brand,
    required this.brandStrong,
    required this.brandSoft,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.onAccent,
    required this.canvas,
    required this.canvasSunken,
    required this.surface,
    required this.surfaceAlt,
    required this.hairline,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.brandExternal,
    required this.isDark,
  });

  /// Gradiente firma del Hero AppBar / login.
  LinearGradient get brandGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [brand, const Color(0xFF146848)]
            : [const Color(0xFF2BA86E), brandStrong],
      );

  /// Copia con brand desplazada al verde externo del Portal.
  EzColors get external => copyWith(brand: brandExternal);

  @override
  EzColors copyWith({
    Color? brand, Color? brandStrong, Color? brandSoft,
    Color? accent, Color? accentStrong, Color? accentSoft, Color? onAccent,
    Color? canvas, Color? canvasSunken, Color? surface, Color? surfaceAlt, Color? hairline,
    Color? ink, Color? inkSecondary, Color? inkMuted,
    Color? success, Color? successSoft, Color? warning, Color? warningSoft,
    Color? danger, Color? dangerSoft, Color? info, Color? infoSoft,
    Color? brandExternal, bool? isDark,
  }) {
    return EzColors(
      brand: brand ?? this.brand,
      brandStrong: brandStrong ?? this.brandStrong,
      brandSoft: brandSoft ?? this.brandSoft,
      accent: accent ?? this.accent,
      accentStrong: accentStrong ?? this.accentStrong,
      accentSoft: accentSoft ?? this.accentSoft,
      onAccent: onAccent ?? this.onAccent,
      canvas: canvas ?? this.canvas,
      canvasSunken: canvasSunken ?? this.canvasSunken,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      hairline: hairline ?? this.hairline,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      brandExternal: brandExternal ?? this.brandExternal,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  EzColors lerp(ThemeExtension<EzColors>? other, double t) {
    if (other is! EzColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EzColors(
      brand: l(brand, other.brand),
      brandStrong: l(brandStrong, other.brandStrong),
      brandSoft: l(brandSoft, other.brandSoft),
      accent: l(accent, other.accent),
      accentStrong: l(accentStrong, other.accentStrong),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccent: l(onAccent, other.onAccent),
      canvas: l(canvas, other.canvas),
      canvasSunken: l(canvasSunken, other.canvasSunken),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      hairline: l(hairline, other.hairline),
      ink: l(ink, other.ink),
      inkSecondary: l(inkSecondary, other.inkSecondary),
      inkMuted: l(inkMuted, other.inkMuted),
      success: l(success, other.success),
      successSoft: l(successSoft, other.successSoft),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      info: l(info, other.info),
      infoSoft: l(infoSoft, other.infoSoft),
      brandExternal: l(brandExternal, other.brandExternal),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// Tema CLARO — lienzo crema + esmeralda + lima.
const EzColors ezLight = EzColors(
  brand: Color(0xFF1E9462), brandStrong: Color(0xFF15824F), brandSoft: Color(0xFFE1F1E8),
  accent: Color(0xFF8FD11B), accentStrong: Color(0xFF5E8C0E), accentSoft: Color(0xFFECF7D3),
  onAccent: Color(0xFF17240F),
  canvas: Color(0xFFF3F1E6), canvasSunken: Color(0xFFECEADB),
  surface: Color(0xFFFFFFFF), surfaceAlt: Color(0xFFF5F4EA), hairline: Color(0xFFE4E1D1),
  ink: Color(0xFF15241A), inkSecondary: Color(0xFF566B5E), inkMuted: Color(0xFF8B968B),
  success: Color(0xFF2F9E52), successSoft: Color(0xFFE1F1E4),
  warning: Color(0xFFD98A16), warningSoft: Color(0xFFF8ECD2),
  danger: Color(0xFFD6584F), dangerSoft: Color(0xFFF7E1DF),
  info: Color(0xFF3E80C0), infoSoft: Color(0xFFE0EAF4),
  brandExternal: Color(0xFF16A34A),
  isDark: false,
);

/// Tema OSCURO — verde-negro profundo + esmeralda/lima más brillantes.
const EzColors ezDark = EzColors(
  brand: Color(0xFF2BA86E), brandStrong: Color(0xFF1F7A52), brandSoft: Color(0xFF12291F),
  accent: Color(0xFFC2F23B), accentStrong: Color(0xFFA8E10C), accentSoft: Color(0xFF24310C),
  onAccent: Color(0xFF14210C),
  canvas: Color(0xFF0E1611), canvasSunken: Color(0xFF0A100C),
  surface: Color(0xFF16211B), surfaceAlt: Color(0xFF1E2A23), hairline: Color(0xFF26332B),
  ink: Color(0xFFE8F0E8), inkSecondary: Color(0xFFA7B5AC), inkMuted: Color(0xFF6E7D73),
  success: Color(0xFF6FC07E), successSoft: Color(0xFF17281A),
  warning: Color(0xFFE6B45A), warningSoft: Color(0xFF2E2413),
  danger: Color(0xFFE8807C), dangerSoft: Color(0xFF2E1917),
  info: Color(0xFF7FB0DD), infoSoft: Color(0xFF14202B),
  brandExternal: Color(0xFF4ADE80),
  isDark: true,
);

/// Acceso rápido: `context.ez`
extension EzContext on BuildContext {
  EzColors get ez => Theme.of(this).extension<EzColors>() ?? ezLight;
}

// ============================================================================
//  2 · FORMA · RITMO · ELEVACIÓN
// ============================================================================

class EzRadius {
  static const double xs = 8;    // input pequeño, tag
  static const double sm = 12;   // snackbar, mini-card
  static const double md = 16;   // botón, input, icon-tile
  static const double lg = 20;   // tarjeta
  static const double xl = 24;   // bottom sheet, diálogo
  static const double full = 999; // chip, badge, avatar-pill

  static BorderRadius r(double v) => BorderRadius.circular(v);
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius button = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xl));
}

class EzSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;   // padding de tarjeta / margen de pantalla
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;  // touch mínimo
  static const double touchMin = 48;
}

class EzElevation {
  /// Sombra por nivel (solo en tema claro; en oscuro usa surface+borde).
  static List<BoxShadow> sm(EzColors c) => c.isDark
      ? const [BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1))]
      : const [BoxShadow(color: Color(0x0F15241A), blurRadius: 2, offset: Offset(0, 1))];
  static List<BoxShadow> md(EzColors c) => c.isDark
      ? const [BoxShadow(color: Color(0x80000000), blurRadius: 20, offset: Offset(0, 6))]
      : const [BoxShadow(color: Color(0x1415241A), blurRadius: 16, offset: Offset(0, 4))];
  static List<BoxShadow> lg(EzColors c) => c.isDark
      ? const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 16))]
      : const [BoxShadow(color: Color(0x1F15241A), blurRadius: 32, offset: Offset(0, 12))];
}

// ============================================================================
//  3 · TIPOGRAFÍA
// ============================================================================

class EzType {
  // Vía google_fonts (mismo mecanismo que ya usaba Almacén): llamar al getter
  // registra el font loader Y devuelve el family name interno correcto — un
  // string 'Plus Jakarta Sans' pelado NO matchea y caería a Roboto en
  // silencio porque las fuentes no están empaquetadas en pubspec.
  static final String sans =
      GoogleFonts.plusJakartaSans().fontFamily ?? 'Plus Jakarta Sans';
  static final String mono =
      GoogleFonts.jetBrainsMono().fontFamily ?? 'JetBrains Mono';

  static TextTheme textTheme(EzColors c) => TextTheme(
        displayLarge: TextStyle(fontFamily: sans, fontSize: 34, height: 1.05, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.ink),
        headlineMedium: TextStyle(fontFamily: sans, fontSize: 28, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.ink),
        titleLarge: TextStyle(fontFamily: sans, fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, color: c.ink),
        titleMedium: TextStyle(fontFamily: sans, fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, color: c.ink),
        bodyLarge: TextStyle(fontFamily: sans, fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, color: c.ink),
        bodyMedium: TextStyle(fontFamily: sans, fontSize: 15, height: 1.5, fontWeight: FontWeight.w400, color: c.ink),          // base
        labelLarge: TextStyle(fontFamily: sans, fontSize: 15, height: 1.3, fontWeight: FontWeight.w700, color: c.ink),          // botón
        bodySmall: TextStyle(fontFamily: sans, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500, color: c.inkSecondary),  // caption
        labelSmall: TextStyle(fontFamily: sans, fontSize: 12, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: c.inkMuted), // overline
      );

  /// Estilo para cifras/códigos: mono + tabular.
  static TextStyle data(EzColors c, {double size = 22, FontWeight w = FontWeight.w600, Color? color}) => TextStyle(
        fontFamily: mono, fontSize: size, fontWeight: w, color: color ?? c.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

// ============================================================================
//  4 · THEME DATA
// ============================================================================

ThemeData buildEzTheme(EzColors c) {
  final scheme = (c.isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
    primary: c.brand,
    onPrimary: Colors.white,
    secondary: c.accent,
    onSecondary: c.onAccent,
    surface: c.surface,
    onSurface: c.ink,
    error: c.danger,
    brightness: c.isDark ? Brightness.dark : Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: c.isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.canvas,
    colorScheme: scheme,
    fontFamily: EzType.sans,
    textTheme: EzType.textTheme(c),
    extensions: [c],
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),

    // -- AppBar plano (variante por defecto) --
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: EzType.sans, fontSize: 20, fontWeight: FontWeight.w800, color: c.ink),
    ),

    // -- Botón primario (lima) --
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(0, 52),
        shape: const RoundedRectangleBorder(borderRadius: EzRadius.button),
        textStyle: TextStyle(fontFamily: EzType.sans, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    // -- Elevated (alias visual de Filled — para llamadas sueltas no migradas) --
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: c.isDark ? 0 : 1,
        minimumSize: const Size(0, 52),
        shape: const RoundedRectangleBorder(borderRadius: EzRadius.button),
        textStyle: TextStyle(fontFamily: EzType.sans, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    // -- Botón secundario (contorno esmeralda) --
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.brand,
        side: BorderSide(color: c.brand, width: 1.5),
        minimumSize: const Size(0, 52),
        shape: const RoundedRectangleBorder(borderRadius: EzRadius.button),
        textStyle: TextStyle(fontFamily: EzType.sans, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    // -- Botón texto / terciario --
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.brand,
        minimumSize: const Size(0, 48),
        shape: const RoundedRectangleBorder(borderRadius: EzRadius.button),
        textStyle: TextStyle(fontFamily: EzType.sans, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),

    // -- FAB = acción primaria = lima --
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
      elevation: 4,
      shape: const RoundedRectangleBorder(borderRadius: EzRadius.button),
    ),

    // -- Card --
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: c.isDark ? 0 : 1,
      shadowColor: const Color(0x1415241A),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: EzRadius.card,
        side: c.isDark ? BorderSide(color: c.hairline) : BorderSide.none,
      ),
    ),

    // -- Inputs --
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: TextStyle(color: c.inkMuted, fontFamily: EzType.sans),
      border: OutlineInputBorder(borderRadius: EzRadius.r(EzRadius.md), borderSide: BorderSide(color: c.hairline)),
      enabledBorder: OutlineInputBorder(borderRadius: EzRadius.r(EzRadius.md), borderSide: BorderSide(color: c.hairline)),
      focusedBorder: OutlineInputBorder(borderRadius: EzRadius.r(EzRadius.md), borderSide: BorderSide(color: c.brand, width: 1.8)),
      errorBorder: OutlineInputBorder(borderRadius: EzRadius.r(EzRadius.md), borderSide: BorderSide(color: c.danger, width: 1.5)),
    ),

    // -- Bottom sheet (respeta el tema, radio 24) --
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.canvas,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: c.canvas,
      shape: const RoundedRectangleBorder(borderRadius: EzRadius.sheet),
      showDragHandle: true,
      dragHandleColor: c.hairline,
    ),

    // -- Diálogo (radio 24) --
    dialogTheme: DialogThemeData(
      backgroundColor: c.canvas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: EzRadius.r(EzRadius.xl)),
      titleTextStyle: TextStyle(fontFamily: EzType.sans, fontSize: 19, fontWeight: FontWeight.w800, color: c.ink),
      contentTextStyle: TextStyle(fontFamily: EzType.sans, fontSize: 14, height: 1.55, color: c.inkSecondary),
    ),

    // -- Snackbar (flotante, radio 12, un solo estándar) --
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(fontFamily: EzType.sans, fontSize: 14, fontWeight: FontWeight.w600, color: c.canvas),
      shape: RoundedRectangleBorder(borderRadius: EzRadius.r(EzRadius.sm)),
      insetPadding: const EdgeInsets.all(EzSpace.x4),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: c.brand,
      unselectedLabelColor: c.inkMuted,
      indicatorColor: c.brand,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(fontFamily: EzType.sans, fontSize: 15, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontFamily: EzType.sans, fontSize: 15, fontWeight: FontWeight.w500),
    ),

    // -- Chip nativo (Chip/ChoiceChip/FilterChip) — mismo pill que EzStatusChip/
    // EzCountChip para que lo no-migrado no desentone --
    chipTheme: ChipThemeData(
      backgroundColor: c.canvasSunken,
      selectedColor: c.accent,
      disabledColor: c.canvasSunken,
      labelStyle: TextStyle(fontFamily: EzType.sans, fontSize: 13, fontWeight: FontWeight.w600, color: c.inkSecondary),
      secondaryLabelStyle: TextStyle(fontFamily: EzType.sans, fontSize: 13, fontWeight: FontWeight.w700, color: c.onAccent),
      side: BorderSide(color: c.hairline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EzRadius.full)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),

    // -- Barra de navegación inferior: selección = brand (estructura/wayfinding,
    // no "acción" — el lima queda reservado para el FAB/CTA primario) --
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.brandSoft,
      elevation: c.isDark ? 0 : 2,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: EzType.sans, fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? c.brand : c.inkMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? c.brand : c.inkMuted, size: 24);
      }),
    ),
  );
}

// ============================================================================
//  5 · HELPERS DE COMPONENTE
// ============================================================================

/// Botón con las 4 variantes del sistema y altura táctil garantizada.
class EzButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final _EzBtnKind _kind;
  final bool expand;

  const EzButton._(this.label, this.onPressed, this.icon, this._kind, this.expand);

  factory EzButton.primary(String label, {VoidCallback? onPressed, IconData? icon, bool expand = true}) =>
      EzButton._(label, onPressed, icon, _EzBtnKind.primary, expand);
  factory EzButton.secondary(String label, {VoidCallback? onPressed, IconData? icon, bool expand = true}) =>
      EzButton._(label, onPressed, icon, _EzBtnKind.secondary, expand);
  factory EzButton.text(String label, {VoidCallback? onPressed, IconData? icon, bool expand = false}) =>
      EzButton._(label, onPressed, icon, _EzBtnKind.text, expand);
  factory EzButton.danger(String label, {VoidCallback? onPressed, IconData? icon, bool expand = true}) =>
      EzButton._(label, onPressed, icon, _EzBtnKind.danger, expand);

  @override
  Widget build(BuildContext context) {
    final c = context.ez;
    final child = icon == null
        ? Text(label)
        : Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 20), const SizedBox(width: EzSpace.x2), Text(label)]);

    Widget btn;
    switch (_kind) {
      case _EzBtnKind.primary:
        btn = FilledButton(onPressed: onPressed, child: child);
        break;
      case _EzBtnKind.secondary:
        btn = OutlinedButton(onPressed: onPressed, child: child);
        break;
      case _EzBtnKind.text:
        btn = TextButton(onPressed: onPressed, child: child);
        break;
      case _EzBtnKind.danger:
        btn = FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: c.danger,
            foregroundColor: c.isDark ? c.dangerSoft : Colors.white,
            minimumSize: const Size(0, 52),
            shape: const RoundedRectangleBorder(borderRadius: EzRadius.button),
            textStyle: TextStyle(fontFamily: EzType.sans, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          child: child,
        );
        break;
    }
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

enum _EzBtnKind { primary, secondary, text, danger }

/// Tarjeta única del sistema (superficie + radio lg + sombra sm / borde en dark).
class EzCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  const EzCard({super.key, required this.child, this.padding = const EdgeInsets.all(EzSpace.x4), this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ez;
    return Material(
      color: c.surface,
      borderRadius: EzRadius.card,
      child: InkWell(
        onTap: onTap,
        borderRadius: EzRadius.card,
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: EzRadius.card,
            border: c.isDark ? Border.all(color: c.hairline) : null,
            boxShadow: c.isDark ? null : EzElevation.sm(c),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Estado semántico. `EzStatus.pendiente` -> color + tinte correctos.
enum EzStatus { success, warning, danger, info, neutral }

class EzStatusChip extends StatelessWidget {
  final String label;
  final EzStatus status;
  const EzStatusChip(this.label, {super.key, this.status = EzStatus.neutral});

  factory EzStatusChip.success(String l) => EzStatusChip(l, status: EzStatus.success);
  factory EzStatusChip.warning(String l) => EzStatusChip(l, status: EzStatus.warning);
  factory EzStatusChip.danger(String l) => EzStatusChip(l, status: EzStatus.danger);
  factory EzStatusChip.info(String l) => EzStatusChip(l, status: EzStatus.info);

  @override
  Widget build(BuildContext context) {
    final c = context.ez;
    late Color fg, bg;
    switch (status) {
      case EzStatus.success: fg = c.isDark ? c.success : const Color(0xFF237A40); bg = c.successSoft; break;
      case EzStatus.warning: fg = c.isDark ? c.warning : const Color(0xFFA66A0E); bg = c.warningSoft; break;
      case EzStatus.danger:  fg = c.isDark ? c.danger  : const Color(0xFFB4433B); bg = c.dangerSoft;  break;
      case EzStatus.info:    fg = c.isDark ? c.info    : const Color(0xFF2E639C); bg = c.infoSoft;    break;
      case EzStatus.neutral: fg = c.inkSecondary; bg = c.canvasSunken; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(EzRadius.full)),
      child: Text(label, style: TextStyle(fontFamily: EzType.sans, fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// Chip de filtro/contador: seleccionado = accent, resto = contorno.
class EzCountChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;
  const EzCountChip(this.label, {super.key, this.count, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ez;
    return Material(
      color: selected ? c.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(EzRadius.full),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(EzRadius.full),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 16, vertical: selected ? 9 : 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(EzRadius.full),
            border: selected ? null : Border.all(color: c.hairline, width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(
              fontFamily: EzType.sans, fontSize: 14, fontWeight: FontWeight.w700,
              color: selected ? c.onAccent : c.inkSecondary)),
            if (count != null) ...[
              const SizedBox(width: EzSpace.x2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: selected ? c.onAccent.withValues(alpha: 0.12) : c.brandSoft, borderRadius: BorderRadius.circular(EzRadius.full)),
                child: Text('$count', style: TextStyle(
                  fontFamily: EzType.mono, fontSize: 12, fontWeight: FontWeight.w600,
                  color: selected ? c.onAccent : c.brand)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Hero AppBar con el gradiente firma (para portadas de módulo).
/// Úsalo dentro de un CustomScrollView como SliverToBoxAdapter, o como header
/// de la pantalla. Para listas/detalle usa el AppBar plano del ThemeData.
class EzHeroHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;
  const EzHeroHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.onBack});

  @override
  Widget build(BuildContext context) {
    final c = context.ez;
    return Container(
      padding: EdgeInsets.fromLTRB(EzSpace.x4, MediaQuery.of(context).padding.top + EzSpace.x3, EzSpace.x4, EzSpace.x6),
      decoration: BoxDecoration(
        gradient: c.brandGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(EzRadius.xl)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (onBack != null)
            _glassIcon(context, Icons.arrow_back, onBack!),
          const Spacer(),
          ...actions,
        ]),
        const SizedBox(height: EzSpace.x4),
        Text(title, style: TextStyle(fontFamily: EzType.sans, fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
        if (subtitle != null) ...[
          const SizedBox(height: EzSpace.x3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(EzRadius.full)),
            child: Text(subtitle!, style: TextStyle(fontFamily: EzType.sans, fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white)),
          ),
        ],
      ]),
    );
  }

  static Widget _glassIcon(BuildContext context, IconData icon, VoidCallback onTap) => Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(EzRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(EzRadius.sm),
          child: const SizedBox(width: 38, height: 38, child: Icon(Icons.arrow_back, size: 20, color: Colors.white)),
        ),
      );
}

// ============================================================================
//  FIN — E-Zyro Sistema de Diseño v1.0
// ============================================================================
