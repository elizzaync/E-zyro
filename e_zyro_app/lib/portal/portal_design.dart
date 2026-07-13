// Sistema de diseño "Ejecutivo Oscuro" para el Portal Cliente B2B de e-zyro.
//
// Paleta, tipografía (Manrope) y helpers visuales compartidos por las
// pantallas del portal (cards, chips de delta, formateadores de números).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/ez_theme.dart';

/// Paleta del Portal (oscuro).
/// MERGE "por valor" con lib/theme/ez_theme.dart (2026-07-13): el azul-pizarra
/// "Ejecutivo" se retira y cada constante queda igualada al token ezDark
/// equivalente, sin tocar a los consumidores (analytics/dashboard ejecutivo).
/// `violeta` es color de serie de gráfico sin rol semántico en Ez — se deja.
abstract final class PortalColores {
  // Bases (= ezDark canvas/surface/hairline)
  static const Color fondo = Color(0xFF0E1611);
  static const Color superficie = Color(0xFF16211B);
  static const Color bordeCard = Color(0xFF26332B);

  // Texto (= ezDark ink/inkSecondary)
  static const Color textoPrimario = Color(0xFFE8F0E8);
  static const Color textoSecundario = Color(0xFFA7B5AC);

  // Acentos (= ezDark accent/info/warning/danger)
  static const Color lima = Color(0xFFC2F23B);
  static const Color cian = Color(0xFF7FB0DD);
  static const Color ambar = Color(0xFFE6B45A);
  static const Color coral = Color(0xFFE8807C);
  static const Color violeta = Color(0xFF9B8AFB); // serie de gráfico — se deja

  // Utilitarios
  static const Color transparente = Color(0x00000000);
  static const Color sombra = Color(0x66000000);
  static const Color divisor = Color(0xFF26332B); // = ezDark.hairline
  static const Color tooltipFondo = Color(0xFF1E2A23); // = ezDark.surfaceAlt
}

/// Tipografía del portal basada en Manrope.
abstract final class PortalTipografia {
  /// Título de sección / pantalla (w800).
  static TextStyle titulo({
    double tamano = 18,
    Color color = PortalColores.textoPrimario,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: tamano,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1.2,
      );

  /// Números de KPI: w800 con cifras tabulares para que no "bailen"
  /// durante las animaciones de conteo.
  static TextStyle kpi({
    double tamano = 30,
    Color color = PortalColores.textoPrimario,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: tamano,
        fontWeight: FontWeight.w800,
        color: color,
        height: 1.05,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Cuerpo de texto (w500).
  static TextStyle cuerpo({
    double tamano = 13,
    Color color = PortalColores.textoSecundario,
    FontWeight peso = FontWeight.w500,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: tamano,
        fontWeight: peso,
        color: color,
        height: 1.3,
      );

  /// Etiquetas pequeñas (ejes, leyendas, badges).
  static TextStyle etiqueta({
    double tamano = 11,
    Color color = PortalColores.textoSecundario,
    FontWeight peso = FontWeight.w600,
  }) =>
      GoogleFonts.plusJakartaSans(
        fontSize: tamano,
        fontWeight: peso,
        color: color,
        letterSpacing: 0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Tema oscuro del Portal — ahora es el dark global del sistema Ez con la
/// única desviación permitida (brand → brandExternal). El "Ejecutivo Oscuro"
/// propio se retiró; ver lib/theme/ez_theme.dart.
// Construido una sola vez al cargar el módulo (no en cada navegación al portal).
final portalThemeCached = buildEzTheme(ezDark.external);

/// Decoraciones y widgets utilitarios del portal.
abstract final class PortalDecoraciones {
  /// Decoración estándar de card: radio 20, borde sutil y sombra suave.
  static BoxDecoration card({Color color = PortalColores.superficie}) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: PortalColores.bordeCard, width: 1),
        boxShadow: const [
          BoxShadow(
            color: PortalColores.sombra,
            blurRadius: 24,
            offset: Offset(0, 10),
            spreadRadius: -12,
          ),
        ],
      );

  /// Contenedor tintado para iconos de scorecards.
  static BoxDecoration contenedorIcono(Color acento) => BoxDecoration(
        color: acento.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      );
}

/// Formateadores de números del portal.
abstract final class PortalFormato {
  static final NumberFormat _compacto = NumberFormat.compact(locale: 'es');
  static final NumberFormat _decimal1 = NumberFormat('#,##0.0', 'es');
  static final NumberFormat _entero = NumberFormat('#,##0', 'es');

  /// 1234 -> "1,2 k" (compacto en español).
  static String compacto(num valor) => _compacto.format(valor);

  /// 98.42 -> "98,4%".
  static String porcentaje(num valor) => '${_decimal1.format(valor)}%';

  /// 1234.5 -> "1.234,5".
  static String decimal1(num valor) => _decimal1.format(valor);

  /// 1234 -> "1.234".
  static String entero(num valor) => _entero.format(valor);
}

/// Chip de variación (delta): triángulo arriba en lima o abajo en coral,
/// sobre un fondo translúcido del mismo acento.
class ChipDelta extends StatelessWidget {
  const ChipDelta({
    super.key,
    required this.texto,
    required this.positivo,
    this.invertirColor = false,
  });

  /// Texto del delta, por ejemplo "1,2 pts" u "8".
  final String texto;

  /// Dirección de la flecha (true = sube).
  final bool positivo;

  /// Para métricas donde bajar es bueno (p. ej. equipos críticos),
  /// invierte el color manteniendo la dirección de la flecha.
  final bool invertirColor;

  @override
  Widget build(BuildContext context) {
    final bool favorable = invertirColor ? !positivo : positivo;
    final Color color = favorable ? PortalColores.lima : PortalColores.coral;
    final String flecha = positivo ? '▲' : '▼';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$flecha $texto',
        style: PortalTipografia.etiqueta(tamano: 10.5, color: color),
      ),
    );
  }
}
