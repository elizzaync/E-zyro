import 'package:flutter/material.dart';

import '../../utils/app_session.dart';
import 'pantalla_plan_cuentas.dart';
import 'pantalla_cuentas_pagar.dart';
import 'pantalla_cuentas_cobrar.dart';
import 'pantalla_reportes_financieros.dart';
import 'pantalla_activos_fijos.dart';
import 'pantalla_planilla.dart';
import 'pantalla_tributario.dart';

/// Hub del módulo de Finanzas / ERP contable. Agrupa los submódulos y muestra
/// solo los que el rol del usuario tiene permiso de ver (admin ve todos).
class PantallaFinanzas extends StatelessWidget {
  const PantallaFinanzas({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppSession.i;
    final items = <_ModuloFin>[
      if (s.canVerContabilidad)
        _ModuloFin('Plan de cuentas', 'Catálogo PCGE y balance de comprobación',
            Icons.account_tree_outlined, const Color(0xFF5A9A00), const PantallaPlanCuentas()),
      if (s.canVerCxp)
        _ModuloFin('Cuentas por Pagar', 'Facturas de proveedores y saldos',
            Icons.shopping_cart_outlined, Colors.deepOrange, const PantallaCuentasPagar()),
      if (s.canVerCxc)
        _ModuloFin('Cuentas por Cobrar', 'Comprobantes a clientes y cobros',
            Icons.point_of_sale_outlined, Colors.teal, const PantallaCuentasCobrar()),
      if (s.canVerContabilidad)
        _ModuloFin('Reportes financieros', 'Balance general, resultados, comprobación',
            Icons.assessment_outlined, Colors.indigo, const PantallaReportesFinancieros()),
      if (s.canVerActivosFijos)
        _ModuloFin('Activos fijos', 'Depreciación mensual y valor en libros',
            Icons.precision_manufacturing_outlined, Colors.brown, const PantallaActivosFijos()),
      if (s.canVerPlanilla)
        _ModuloFin('Planilla', 'Nómina: cálculo, aprobación y pago',
            Icons.payments_outlined, Colors.purple, const PantallaPlanilla()),
      if (s.canVerTributario)
        _ModuloFin('Tributario / IGV', 'Registro de compras y ventas',
            Icons.receipt_long_outlined, Colors.blueGrey, const PantallaTributario()),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finanzas', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: items.isEmpty
          ? const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('No tienes permisos para ver módulos de finanzas.',
                  textAlign: TextAlign.center)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _tarjeta(context, items[i]),
            ),
    );
  }

  Widget _tarjeta(BuildContext context, _ModuloFin m) {
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 1.5,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => m.pantalla)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(m.icono, color: m.color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(m.subtitulo, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuloFin {
  final String titulo, subtitulo;
  final IconData icono;
  final Color color;
  final Widget pantalla;
  _ModuloFin(this.titulo, this.subtitulo, this.icono, this.color, this.pantalla);
}
