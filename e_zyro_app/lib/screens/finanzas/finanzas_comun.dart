import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
