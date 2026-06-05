// pantalla_resumen_compra.dart — Fase 4: "carta de costo total/estimado".
// Se muestra DESPUÉS de completar el registro de una compra, como resumen
// tipo orden de pedido: ítems, cantidades, precios y el TOTAL del pedido.
// Solo lectura; no toca el flujo de compras.

import 'package:flutter/material.dart';
import '../../../models/compras_models.dart';
import 'es_tokens.dart';
import 'es_widgets.dart';

class PantallaResumenCompra extends StatelessWidget {
  final TicketCompra ticket;
  const PantallaResumenCompra({super.key, required this.ticket});

  String _money(double v) => 'S/ ${v.toStringAsFixed(2)}';

  double _subtotal(TicketCompraItem it) {
    if (it.totalItem != null) return it.totalItem!;
    final qty = (it.cantidadComprada ?? it.cantidad).toDouble();
    return qty * (it.precioUnitario ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    final esEstimado = ticket.totalReal == null;
    final monto = ticket.totalReal ?? ticket.totalEstimado ?? ticket.total;
    final proveedor = ticket.proveedorUnicoNombre ??
        ticket.canalUnico ??
        (ticket.items.isNotEmpty
            ? (ticket.items.first.proveedorNombre ??
                ticket.items.first.canalPersonalizado ??
                'Varios')
            : 'Varios');

    return Scaffold(
      backgroundColor: ESC.bg,
      body: Column(children: [
        ESPanelBar(
          title: 'Resumen del pedido',
          subtitle: ticket.codigo,
          trailing: ESBarIcon(ESIcons.cart, onTap: () {}),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            // ── Cabecera de la "carta" ──────────────────────────────────────
            ESCard(
              accent: ESC.compra,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: ESC.compraBg, borderRadius: BorderRadius.circular(12)),
                    child: Icon(ESIcons.cart, color: ESC.compra, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(ticket.codigo, style: pj(size: 17, weight: FontWeight.w800, color: ESC.compra)),
                      Text(ticket.proyectoNombre, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: pj(size: 12, color: ESC.inkSub)),
                    ]),
                  ),
                  StatusPill(_estadoLabel(ticket.estado)),
                ]),
                const SizedBox(height: 12),
                _filaMeta(ESIcons.truck, 'Proveedor / canal', proveedor),
                const SizedBox(height: 8),
                _filaMeta(ESIcons.pin, 'Solicitante', ticket.solicitanteNombre),
                const SizedBox(height: 8),
                _filaMeta(ESIcons.clock, 'Registrado', ticket.creadoEn),
              ]),
            ),
            const SizedBox(height: 12),

            ESSectionLabel('Detalle del pedido · ${ticket.items.length} ítem(s)'),
            const SizedBox(height: 10),

            // ── Tabla de ítems ──────────────────────────────────────────────
            ESCard(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                for (int i = 0; i < ticket.items.length; i++) ...[
                  _filaItem(ticket.items[i]),
                  if (i < ticket.items.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Container(height: 1, color: ESC.line),
                    ),
                ],
              ]),
            ),
            const SizedBox(height: 12),

            // ── Total ───────────────────────────────────────────────────────
            ESCard(
              accent: ESC.compra,
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(esEstimado ? 'TOTAL ESTIMADO' : 'TOTAL DEL PEDIDO',
                      style: pj(size: 12, weight: FontWeight.w700, color: ESC.compra, spacing: 1)),
                  if (esEstimado)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Sujeto a precios reales de compra',
                          style: pj(size: 11, color: ESC.inkFaint)),
                    ),
                ]),
                const Spacer(),
                Text(_money(monto), style: pj(size: 26, weight: FontWeight.w800, color: ESC.compra, spacing: -0.5)),
              ]),
            ),
            const SizedBox(height: 16),
            ESButton('Listo', icon: ESIcons.check, expand: true,
                onTap: () => Navigator.pop(context)),
          ]),
        ),
      ]),
    );
  }

  Widget _filaMeta(IconData ic, String label, String value) => Row(children: [
        Icon(ic, size: 16, color: ESC.inkSub),
        const SizedBox(width: 8),
        Text('$label: ', style: pj(size: 12.5, color: ESC.inkFaint)),
        Expanded(
          child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: pj(size: 12.5, weight: FontWeight.w600, color: ESC.inkSub)),
        ),
      ]);

  Widget _filaItem(TicketCompraItem it) {
    final qty = it.cantidadComprada ?? it.cantidad;
    final pu = it.precioUnitario;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(color: ESC.compraBg, borderRadius: BorderRadius.circular(5)),
        child: Text(it.tipoItem == 'material' ? 'MAT' : 'EQ',
            style: pj(size: 10, weight: FontWeight.w800, color: ESC.compra)),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(it.nombre, style: pj(size: 13.5, weight: FontWeight.w700, height: 1.3)),
          const SizedBox(height: 3),
          Text(
            '$qty ${it.unidad}'
            '${pu != null ? '  ×  ${_money(pu)}' : '  ×  (sin precio)'}',
            style: pj(size: 12, color: ESC.inkFaint),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Text(_money(_subtotal(it)),
          style: pj(size: 13.5, weight: FontWeight.w800, color: ESC.ink)),
    ]);
  }

  String _estadoLabel(String e) {
    switch (e) {
      case 'completado':
        return 'Entregada';
      case 'en_proceso':
        return 'Aprobada';
      case 'cancelado':
        return 'Rechazado';
      default:
        return 'Pendiente';
    }
  }
}
