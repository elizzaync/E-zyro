import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../widgets/verdant_theme.dart';

/// Utilidades compartidas por las pantallas del módulo de Finanzas.

final NumberFormat _fmtMoneda = NumberFormat.currency(locale: 'es_PE', symbol: 'S/ ');

String money(num v) => _fmtMoneda.format(v);

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
Color colorEstado(String estado) {
  switch (estado) {
    case 'pagada':
    case 'cobrada':
    case 'aprobada':
      return Colors.green;
    case 'pagada_parcial':
    case 'cobrada_parcial':
    case 'calculada':
      return Colors.orange;
    case 'anulada':
      return Colors.red;
    case 'pendiente':
    default:
      return Colors.blueGrey;
  }
}

/// Chip de estado coloreado.
Widget chipEstado(String estado) {
  final c = colorEstado(estado);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.withValues(alpha: 0.5)),
    ),
    child: Text(estado.replaceAll('_', ' '),
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
  );
}

/// Muestra un SnackBar de error rojo.
void mostrarError(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700));
}

/// Muestra un SnackBar de éxito verde.
void mostrarOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700));
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
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
              child: Icon(icono, size: 54, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Text(titulo,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface)),
            const SizedBox(height: 6),
            SizedBox(
              width: 260,
              child: Text(subtitulo,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5, color: scheme.onSurfaceVariant, height: 1.4)),
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
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
        ],
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
                Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
    final v = VerdantColors.of(context);
    final theme = Theme.of(context);
    final inputTheme = theme.copyWith(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: v.cardAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: v.heroSolid, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: v.red, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: v.red, width: 1.6),
        ),
        labelStyle: TextStyle(color: v.sub, fontSize: 13.5),
        helperStyle: TextStyle(color: v.mut, fontSize: 11),
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
                  color: v.track,
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
                  color: v.heroSolid.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icono, color: v.heroSolid, size: 22),
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
                            color: v.ink)),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitulo!,
                          style: TextStyle(fontSize: 11.5, color: v.sub)),
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
                  backgroundColor: v.heroSolid,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
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

  const FinTotalesCard({super.key, required this.subtotal, required this.igvPct});

  @override
  Widget build(BuildContext context) {
    final v = VerdantColors.of(context);
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
                    color: destacar ? v.ink : v.sub)),
            Text(valor,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: destacar ? 17 : 12.5,
                    fontWeight: FontWeight.w700,
                    color: destacar ? v.heroSolid : v.ink)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: v.cardAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: v.bd),
      ),
      child: Column(children: [
        fila('Subtotal', money(subtotal)),
        fila('IGV (${igvPct.toStringAsFixed(igvPct % 1 == 0 ? 0 : 2)}%)',
            money(igv)),
        Divider(height: 14, color: v.track),
        fila('Total a registrar', money(total), destacar: true),
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
