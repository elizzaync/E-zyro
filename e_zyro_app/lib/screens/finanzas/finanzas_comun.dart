import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../theme/ez_theme.dart';

/// Utilidades compartidas por las pantallas del módulo de Finanzas.

final Map<String, NumberFormat> _fmtPorMoneda = {};

/// Símbolo de presentación por código de moneda ('PEN' → 'S/', 'USD' → 'US$').
String simboloMoneda(String moneda) =>
    moneda == 'PEN' ? 'S/' : (moneda == 'USD' ? 'US\$' : moneda);

/// Formatea un monto en la moneda del documento (por defecto soles).
String money(num v, [String moneda = 'PEN']) =>
    (_fmtPorMoneda[moneda] ??= NumberFormat.currency(
            locale: 'es_PE', symbol: '${simboloMoneda(moneda)} '))
        .format(v);

/// Convierte de forma segura un valor JSON (num/String/null) a double.
/// El backend serializa los Decimal como string ("0.00"); castear a `num`
/// directamente revienta con "type 'String' is not a subtype of type 'num?'".
double toNum(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

/// Periodo 'YYYY-MM' del mes actual.
String periodoActual() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

String hoyISO() => DateTime.now().toIso8601String().substring(0, 10);

/// Color asociado al estado de una factura/comprobante/planilla.
Color colorEstado(String estado, EzColors ez) {
  switch (estado) {
    case 'pagada':
    case 'cobrada':
    case 'aprobada':
      return ez.success;
    case 'pagada_parcial':
    case 'cobrada_parcial':
    case 'calculada':
      return ez.warning;
    case 'anulada':
      return ez.danger;
    case 'pendiente':
    default:
      return ez.inkMuted;
  }
}

/// Chip de estado coloreado.
Widget chipEstado(String estado, EzColors ez) {
  final c = colorEstado(estado, ez);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(EzRadius.xs),
      border: Border.all(color: c.withValues(alpha: 0.5)),
    ),
    child: Text(estado.replaceAll('_', ' '),
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

/// Muestra un SnackBar de error rojo.
void mostrarError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: context.ez.danger));
}

/// Muestra un SnackBar de éxito verde.
void mostrarOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: context.ez.success));
}

/// Estado vacío estándar de Finanzas: ícono en círculo pastel + título + subtítulo.
class EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  const EstadoVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
  });

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration:
                  BoxDecoration(color: ez.canvasSunken, shape: BoxShape.circle),
              child: Icon(icono, size: 54, color: ez.inkMuted),
            ),
            const SizedBox(height: 18),
            Text(titulo,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: ez.ink)),
            const SizedBox(height: 6),
            SizedBox(
              width: 260,
              child: Text(subtitulo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5, color: ez.inkSecondary, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta-resumen con un valor monetario grande (para headers de reporte).
class TarjetaResumen extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;
  final IconData icono;
  const TarjetaResumen({
    super.key,
    required this.titulo,
    required this.valor,
    required this.color,
    required this.icono,
  });

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ez.surface,
        borderRadius: EzRadius.card,
        boxShadow: EzElevation.sm(ez),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icono, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TextStyle(fontSize: 12, color: ez.inkSecondary)),
                const SizedBox(height: 2),
                Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formularios de registro (lenguaje visual Verdant) ────────────────────────

/// Contenedor estándar de los formularios de registro de Finanzas (bottom
/// sheets): asa de arrastre, encabezado con ícono en badge + título +
/// subtítulo (qué automatiza el registro), campos con estilo relleno
/// redondeado (vía Theme override, sin tocar cada campo) y botón primario
/// ancho con estado de carga integrado.
class FinFormSheet extends StatelessWidget {
  final String titulo;
  final String? subtitulo;
  final IconData icono;
  final Widget child;
  final String textoBoton;
  final bool guardando;
  final VoidCallback? onGuardar;

  const FinFormSheet({
    super.key,
    required this.titulo,
    this.subtitulo,
    required this.icono,
    required this.child,
    required this.textoBoton,
    this.guardando = false,
    this.onGuardar,
  });

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    final theme = Theme.of(context);
    final inputTheme = theme.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ez.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: EzRadius.r(EzRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: EzRadius.r(EzRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: EzRadius.r(EzRadius.md),
          borderSide: BorderSide(color: ez.brand, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: EzRadius.r(EzRadius.md),
          borderSide: BorderSide(color: ez.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: EzRadius.r(EzRadius.md),
          borderSide: BorderSide(color: ez.danger, width: 1.6),
        ),
        labelStyle: TextStyle(color: ez.inkSecondary, fontSize: 13.5),
        helperStyle: TextStyle(color: ez.inkMuted, fontSize: 11),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: ez.hairline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: ez.brand.withValues(alpha: 0.13),
                  borderRadius: EzRadius.r(EzRadius.md),
                ),
                child: Icon(icono, color: ez.brand, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: ez.ink)),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitulo!,
                          style: TextStyle(fontSize: 11.5, color: ez.inkSecondary)),
                    ],
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            Theme(data: inputTheme, child: child),
            const SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: guardando ? null : onGuardar,
                style: FilledButton.styleFrom(
                  backgroundColor: ez.accent,
                  foregroundColor: ez.onAccent,
                  shape: const RoundedRectangleBorder(
                      borderRadius: EzRadius.button),
                ),
                child: guardando
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ez.onAccent))
                    : Text(textoBoton,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de totales en vivo (subtotal / IGV / total) para que el usuario vea
/// exactamente lo que se va a registrar antes de guardar.
class FinTotalesCard extends StatelessWidget {
  final double subtotal;
  final double igvPct;
  final String moneda;

  const FinTotalesCard(
      {super.key,
      required this.subtotal,
      required this.igvPct,
      this.moneda = 'PEN'});

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    final igv = subtotal * igvPct / 100;
    final total = subtotal + igv;
    Widget fila(String label, String valor,
        {bool destacar = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: destacar ? 13.5 : 12,
                    fontWeight: destacar ? FontWeight.w700 : FontWeight.w500,
                    color: destacar ? ez.ink : ez.inkSecondary)),
            Text(valor,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: destacar ? 17 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: destacar ? ez.brand : ez.ink)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ez.surfaceAlt,
        borderRadius: EzRadius.r(EzRadius.md),
        border: Border.all(color: ez.hairline),
      ),
      child: Column(children: [
        fila('Subtotal', money(subtotal, moneda)),
        fila('IGV (${igvPct.toStringAsFixed(igvPct % 1 == 0 ? 0 : 2)}%)',
            money(igv, moneda)),
        Divider(height: 14, color: ez.hairline),
        fila('Total a registrar', money(total, moneda), destacar: true),
      ]),
    );
  }
}

/// Etiqueta legible de un valor con guiones bajos ('nota_credito' → 'Nota crédito').
String etiquetaLegible(String v) {
  final limpio = v.replaceAll('_', ' ');
  return limpio.isEmpty
      ? v
      : '${limpio[0].toUpperCase()}${limpio.substring(1)}';
}
