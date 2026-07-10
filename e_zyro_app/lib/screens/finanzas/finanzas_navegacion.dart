import 'package:flutter/material.dart';

import '../../utils/app_session.dart';
import 'pantalla_plan_cuentas.dart';
import 'pantalla_cuentas_pagar.dart';
import 'pantalla_cuentas_cobrar.dart';
import 'pantalla_reportes_financieros.dart';
import 'pantalla_activos_fijos.dart';
import 'pantalla_planilla.dart';
import 'pantalla_tributario.dart';
import 'pantalla_centros_costo.dart';
import 'pantalla_rentabilidad.dart';
import 'pantalla_configuracion_erp.dart';
import 'pantalla_presupuesto.dart';
import 'pantalla_inventario_valorizado.dart';
import 'pantalla_caja_chica.dart';
import 'pantalla_conciliacion_bancaria.dart';
import 'pantalla_cierre_contable.dart';
import 'pantalla_manual_finanzas.dart';

/// Fuente única del mapa de navegación de Finanzas: define qué submódulos
/// existen, a qué sección pertenecen, su permiso y la pantalla destino.
/// Lo consumen tanto el hub ([PantallaFinanzas]) como el conmutador rápido
/// que aparece en el AppBar de cada pantalla de Finanzas.

/// Identificadores estables de cada submódulo (para resaltar "estás aquí").
class FinId {
  static const planCuentas = 'plan_cuentas';
  static const reportes = 'reportes';
  static const tributario = 'tributario';
  static const cxp = 'cxp';
  static const cxc = 'cxc';
  static const cajaChica = 'caja_chica';
  static const conciliacion = 'conciliacion';
  static const activosFijos = 'activos_fijos';
  static const inventario = 'inventario';
  static const planilla = 'planilla';
  static const centrosCosto = 'centros_costo';
  static const rentabilidad = 'rentabilidad';
  static const configuracionErp = 'configuracion_erp';
  static const presupuesto = 'presupuesto';
  static const cierre = 'cierre';
  static const manual = 'manual';
}

class FinModulo {
  final String id;
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final WidgetBuilder builder;
  const FinModulo(this.id, this.titulo, this.subtitulo, this.icono, this.color,
      this.builder);
}

class FinSeccion {
  final String titulo;
  final IconData icono;
  final List<FinModulo> modulos;
  const FinSeccion(this.titulo, this.icono, this.modulos);
}

const _verde = Color(0xFF5A9A00);

/// Secciones con los submódulos que el usuario tiene permiso de ver.
/// Las secciones sin módulos visibles se omiten.
List<FinSeccion> finanzasSecciones(AppSession s) {
  final secciones = <FinSeccion>[
    FinSeccion('Contabilidad', Icons.account_balance_wallet_outlined, [
      if (s.canVerContabilidad)
        FinModulo(FinId.planCuentas, 'Plan de cuentas',
            'Catálogo PCGE y balance de comprobación',
            Icons.account_tree_outlined, _verde,
            (_) => const PantallaPlanCuentas()),
      if (s.canVerContabilidad)
        FinModulo(FinId.reportes, 'Reportes financieros',
            'Balance general, resultados, comprobación',
            Icons.assessment_outlined, Colors.indigo,
            (_) => const PantallaReportesFinancieros()),
      if (s.canVerTributario)
        FinModulo(FinId.tributario, 'Tributario / IGV',
            'Registro de compras, ventas y export PLE',
            Icons.receipt_long_outlined, Colors.blueGrey,
            (_) => const PantallaTributario()),
      if (s.canVerContabilidad)
        FinModulo(FinId.cierre, 'Cierre y configuración',
            'Cierre de ejercicio y cuentas del cierre',
            Icons.event_available_outlined, Colors.deepPurple,
            (_) => const PantallaCierreContable()),
      if (s.canVerContabilidad)
        FinModulo(FinId.configuracionErp, 'Configuración ERP',
            'Facturación electrónica y multimoneda',
            Icons.settings_suggest_outlined, Colors.blueGrey,
            (_) => const PantallaConfiguracionErp()),
      if (s.canVerContabilidad)
        FinModulo(FinId.presupuesto, 'Presupuesto',
            'Presupuesto anual vs. ejecutado',
            Icons.savings_outlined, Colors.orange.shade800,
            (_) => const PantallaPresupuesto()),
    ]),
    FinSeccion('Cuentas', Icons.swap_horiz_outlined, [
      if (s.canVerCxp)
        FinModulo(FinId.cxp, 'Cuentas por Pagar',
            'Facturas de proveedores y saldos',
            Icons.shopping_cart_outlined, Colors.deepOrange,
            (_) => const PantallaCuentasPagar()),
      if (s.canVerCxc)
        FinModulo(FinId.cxc, 'Cuentas por Cobrar',
            'Comprobantes a clientes y cobros',
            Icons.point_of_sale_outlined, Colors.teal,
            (_) => const PantallaCuentasCobrar()),
    ]),
    FinSeccion('Tesorería', Icons.account_balance_outlined, [
      if (s.canVerCajaChica)
        FinModulo(FinId.cajaChica, 'Caja Chica',
            'Efectivo para gastos menores (contabilizado)',
            Icons.savings_outlined, Colors.green.shade600,
            (_) => const PantallaCajaChica()),
      if (s.canVerConciliacionBancaria)
        FinModulo(FinId.conciliacion, 'Conciliación bancaria',
            'Extracto del banco vs. libros',
            Icons.account_balance_outlined, Colors.blue.shade700,
            (_) => const PantallaConciliacionBancaria()),
    ]),
    FinSeccion('Activos e inventario', Icons.inventory_2_outlined, [
      if (s.canVerActivosFijos)
        FinModulo(FinId.activosFijos, 'Activos fijos',
            'Depreciación mensual y valor en libros',
            Icons.precision_manufacturing_outlined, Colors.brown,
            (_) => const PantallaActivosFijos()),
      if (s.canVerInventarioValorizado)
        FinModulo(FinId.inventario, 'Inventario valorizado',
            'Kardex, costo promedio y movimientos',
            Icons.inventory_2_outlined, Colors.brown.shade400,
            (_) => const PantallaInventarioValorizado()),
    ]),
    FinSeccion('Personal y controlling', Icons.groups_outlined, [
      if (s.canVerPlanilla)
        FinModulo(FinId.planilla, 'Planilla',
            'Nómina: cálculo, aprobación y pago',
            Icons.payments_outlined, _verde,
            (_) => const PantallaPlanilla()),
      if (s.canVerControlling)
        FinModulo(FinId.centrosCosto, 'Centros de costo',
            'Controlling: presupuesto vs. costo real',
            Icons.workspaces_outline, Colors.cyan.shade700,
            (_) => const PantallaCentrosCosto()),
      if (s.canVerControlling)
        FinModulo(FinId.rentabilidad, 'Rentabilidad',
            'Margen por proyecto: ingresos vs. costos',
            Icons.trending_up, Colors.green.shade700,
            (_) => const PantallaRentabilidad()),
    ]),
  ];
  // Solo secciones con al menos un módulo visible.
  return secciones.where((sec) => sec.modulos.isNotEmpty).toList();
}

/// True si el usuario puede ver algún módulo de finanzas.
bool tieneModulosFinanzas(AppSession s) => finanzasSecciones(s).isNotEmpty;

/// Módulo por id respetando el gating por permisos (null si no lo puede ver).
/// Lo usan las acciones rápidas del dashboard para navegar sin duplicar rutas.
FinModulo? moduloFinanzasPorId(AppSession s, String id) {
  for (final sec in finanzasSecciones(s)) {
    for (final m in sec.modulos) {
      if (m.id == id) return m;
    }
  }
  return null;
}

/// Botón de AppBar que abre el conmutador rápido de Finanzas. Colócalo en
/// `actions:` de cada pantalla de Finanzas; [actual] resalta la pantalla activa.
Widget accionConmutadorFinanzas(BuildContext context, {required String actual}) {
  return IconButton(
    tooltip: 'Ir a otro módulo de Finanzas',
    icon: const Icon(Icons.apps_outlined),
    onPressed: () => mostrarConmutadorFinanzas(context, actual: actual),
  );
}

/// Hoja inferior para saltar directo a otro módulo de Finanzas sin volver al
/// hub. Usa [Navigator.pushReplacement] para no apilar pantallas hermanas.
Future<void> mostrarConmutadorFinanzas(BuildContext context,
    {required String actual}) async {
  final s = AppSession.i;
  final secciones = finanzasSecciones(s);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Módulos de Finanzas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final sec in secciones) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 0, 6),
                          child: Row(
                            children: [
                              Icon(sec.icono, size: 15, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text(sec.titulo.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey,
                                      letterSpacing: 0.5)),
                            ],
                          ),
                        ),
                        for (final m in sec.modulos)
                          _itemConmutador(ctx, m, m.id == actual),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _itemConmutador(BuildContext ctx, FinModulo m, bool esActual) {
  return Opacity(
    opacity: esActual ? 0.55 : 1,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: m.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(m.icono, color: m.color, size: 21),
      ),
      title: Text(m.titulo,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(m.subtitulo,
          style: const TextStyle(fontSize: 11, color: Colors.grey)),
      trailing: esActual
          ? const Icon(Icons.check_circle, color: Color(0xFF5A9A00), size: 20)
          : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: esActual
          ? null
          : () {
              Navigator.pop(ctx); // cierra la hoja
              Navigator.pushReplacement(
                ctx,
                MaterialPageRoute(builder: m.builder),
              );
            },
    ),
  );
}

/// Acceso directo al Manual (módulo transversal, fuera de las secciones).
Widget abrirManualFinanzas(BuildContext context) {
  return IconButton(
    icon: const Icon(Icons.menu_book_outlined),
    tooltip: 'Manual de Usuario',
    onPressed: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const PantallaManualFinanzas())),
  );
}
