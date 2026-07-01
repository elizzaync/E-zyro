import 'package:flutter/material.dart';
import '../../models/finanzas_models.dart';
import '../../utils/app_session.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

class PantallaPlanilla extends StatefulWidget {
  const PantallaPlanilla({super.key});
  @override
  State<PantallaPlanilla> createState() => _State();
}

class _State extends State<PantallaPlanilla> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  List<Planilla> _planillas = [];
  bool _loadingPlanillas = true;

  List<ConceptoRemunerativo> _conceptos = [];
  bool _loadingConceptos = true;

  bool? _descTardanzaAuto; // null mientras carga
  bool _togglingConfig = false;

  List<EmpleadoPlanilla> _empleados = [];
  List<AsignacionConcepto> _asignaciones = [];
  bool _loadingSueldos = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _cargarPlanillas();
    _cargarConceptos();
    _cargarSueldos();
    _cargarConfig();
  }

  Future<void> _cargarConfig() async {
    final svc = await getFinanzasService();
    final r = await svc.getDescuentoTardanzaAuto();
    if (!mounted) return;
    setState(() {
      if (r.ok) _descTardanzaAuto = r.data!;
    });
  }

  Future<void> _toggleDescTardanza(bool v) async {
    setState(() => _togglingConfig = true);
    final svc = await getFinanzasService();
    final r = await svc.setDescuentoTardanzaAuto(v);
    if (!mounted) return;
    setState(() {
      _togglingConfig = false;
      if (r.ok) _descTardanzaAuto = r.data!;
    });
    if (r.ok) {
      mostrarOk(context, v
          ? 'Las tardanzas se descontarán automáticamente.'
          : 'Descuento automático de tardanzas desactivado.');
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _abrirAjustes() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ajustes de planilla', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (_descTardanzaAuto == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Descontar tardanzas automáticamente'),
                  subtitle: const Text(
                    'Al calcular la planilla, descuenta las tardanzas registradas en asistencia.',
                  ),
                  value: _descTardanzaAuto!,
                  onChanged: _togglingConfig
                      ? null
                      : (v) async {
                          await _toggleDescTardanza(v);
                          if (ctx.mounted) setSt(() {});
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _marcarBase(ConceptoRemunerativo c) async {
    if (c.esBase) return;
    final svc = await getFinanzasService();
    final r = await svc.marcarConceptoBase(c.id, true);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, '"${c.nombre}" marcado como concepto base (sueldo).');
      _cargarConceptos();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarPlanillas() async {
    setState(() => _loadingPlanillas = true);
    final svc = await getFinanzasService();
    final r = await svc.planillas();
    if (!mounted) return;
    setState(() {
      _loadingPlanillas = false;
      if (r.ok) _planillas = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarConceptos() async {
    setState(() => _loadingConceptos = true);
    final svc = await getFinanzasService();
    final r = await svc.conceptosPlanilla();
    if (!mounted) return;
    setState(() {
      _loadingConceptos = false;
      if (r.ok) _conceptos = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarSueldos() async {
    setState(() => _loadingSueldos = true);
    final svc = await getFinanzasService();
    final re = await svc.empleadosPlanilla();
    final ra = await svc.asignacionesPlanilla();
    if (!mounted) return;
    setState(() {
      _loadingSueldos = false;
      if (re.ok) _empleados = re.data!;
      if (ra.ok) _asignaciones = ra.data!;
    });
    if (!re.ok) mostrarError(context, re.errorMessage);
  }

  Future<void> _calcular() async {
    String periodo = periodoActual();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Calcular planilla'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selecciona el periodo a calcular:'),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final parts = periodo.split('-');
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime(int.parse(parts[0]), int.parse(parts[1]), 1),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) {
                    setSt(() => periodo =
                        '${d.year}-${d.month.toString().padLeft(2, '0')}');
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Periodo',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(periodo),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Calcular')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.calcularPlanilla(periodo);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Planilla $periodo calculada (estado: calculada).');
      _cargarPlanillas();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  Future<void> _accion(Planilla p, String accion) async {
    final textos = {
      'aprobar': ('Aprobar planilla', 'Se generará el asiento de provisión (62 → 41/40).', 'Aprobar'),
      'pagar': ('Marcar pagada', 'Se generará el asiento de pago (41/40 → 10 Caja).', 'Pagar'),
      'anular': ('Anular planilla', '¿Anular esta planilla? Esta acción no se puede deshacer.', 'Anular'),
    };
    final t = textos[accion]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.$1),
        content: Text(t.$2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: accion == 'anular' ? FilledButton.styleFrom(backgroundColor: Colors.red) : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.$3),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = switch (accion) {
      'aprobar' => await svc.aprobarPlanilla(p.id),
      'pagar' => await svc.pagarPlanilla(p.id),
      _ => await svc.anularPlanilla(p.id),
    };
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, switch (accion) {
        'aprobar' => 'Planilla aprobada (provisión contabilizada).',
        'pagar' => 'Planilla pagada (pago contabilizado).',
        _ => 'Planilla anulada.',
      });
      _cargarPlanillas();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _abrirDetalle(Planilla p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => _PantallaDetallePlanilla(planilla: p)));
  }

  void _abrirFormConcepto() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormConcepto(onGuardado: _cargarConceptos),
    );
  }

  @override
  Widget build(BuildContext context) {
    final puedeCalcular = AppSession.i.canCalcularPlanilla;

    FloatingActionButton? fab;
    if (_tabs.index == 0 && puedeCalcular) {
      fab = FloatingActionButton.extended(
        onPressed: _calcular,
        icon: const Icon(Icons.calculate),
        label: const Text('Calcular'),
      );
    } else if (_tabs.index == 1 && puedeCalcular) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormConcepto,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo concepto'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planilla'),
        actions: [
          IconButton(
            tooltip: 'Ajustes de planilla',
            icon: const Icon(Icons.tune),
            onPressed: _abrirAjustes,
          ),
          accionConmutadorFinanzas(context, actual: FinId.planilla),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [Tab(text: 'Planillas'), Tab(text: 'Conceptos'), Tab(text: 'Sueldos')],
        ),
      ),
      floatingActionButton: fab,
      body: TabBarView(
        controller: _tabs,
        children: [
          _tabPlanillas(),
          _tabConceptos(),
          _tabSueldos(),
        ],
      ),
    );
  }

  Widget _tabSueldos() {
    if (_loadingSueldos || _loadingConceptos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_empleados.isEmpty) {
      return const EstadoVacio(
        icono: Icons.badge_outlined,
        titulo: 'Sin empleados activos',
        subtitulo: 'Registra empleados activos para incluirlos en la planilla.',
      );
    }
    final puedeEditar = AppSession.i.canCalcularPlanilla;
    return RefreshIndicator(
      onRefresh: _cargarSueldos,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _empleados.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final e = _empleados[i];
          final asigs = _asignaciones.where((a) => a.empleadoId == e.id).toList();
          final neto = _netoEstimado(asigs);
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(e.nombre ?? 'Empleado ${e.id}'),
              subtitle: Text(e.cargo ?? '—'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(asigs.isEmpty ? 'Sin asignar' : money(neto),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: asigs.isEmpty ? Colors.grey : Colors.purple)),
                  Text(asigs.isEmpty ? 'usa referencial' : 'neto estimado',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
              onTap: puedeEditar ? () => _abrirSueldos(e) : null,
            ),
          );
        },
      ),
    );
  }

  /// Neto estimado con los montos asignados (ingresos − descuentos).
  double _netoEstimado(List<AsignacionConcepto> asigs) {
    double neto = 0;
    for (final a in asigs) {
      final matches = _conceptos.where((x) => x.id == a.conceptoId);
      if (matches.isEmpty) continue;
      final tipo = matches.first.tipo;
      if (tipo == 'ingreso') {
        neto += a.monto;
      } else if (tipo == 'descuento') {
        neto -= a.monto;
      }
    }
    return neto;
  }

  void _abrirSueldos(EmpleadoPlanilla e) {
    final asigs = {
      for (final a in _asignaciones.where((a) => a.empleadoId == e.id)) a.conceptoId: a.monto
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormSueldos(
        empleado: e,
        conceptos: _conceptos,
        montosActuales: asigs,
        onGuardado: _cargarSueldos,
      ),
    );
  }

  Widget _tabPlanillas() {
    if (_loadingPlanillas) return const Center(child: CircularProgressIndicator());
    if (_planillas.isEmpty) {
      return const EstadoVacio(
        icono: Icons.payments,
        titulo: 'Sin planillas procesadas',
        subtitulo: 'Calcula tu primera planilla para ver sueldos, aportes y descuentos.',
      );
    }
    final puedeAprobar = AppSession.i.canAprobarPlanilla;
    final puedeAnular = AppSession.i.isAdmin;
    return RefreshIndicator(
      onRefresh: _cargarPlanillas,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _planillas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = _planillas[i];
          final surface = Theme.of(context).colorScheme.surface;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _abrirDetalle(p),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_note, color: Colors.purple),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Proceso ${p.fechaProceso}',
                          style: const TextStyle(fontWeight: FontWeight.bold))),
                      chipEstado(p.estado),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  const Divider(height: 18),
                  _filaMonto('Ingresos', p.totalIngresos, Colors.green),
                  _filaMonto('Descuentos', p.totalDescuentos, Colors.deepOrange),
                  _filaMonto('Aportes empleador', p.totalAportes, Colors.blueGrey),
                  const Divider(height: 14),
                  _filaMonto('Neto a pagar', p.totalNeto, Colors.purple, negrita: true),
                  if ((puedeAprobar || puedeAnular) &&
                      (p.estado == 'calculada' || p.estado == 'aprobada')) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (puedeAnular)
                          TextButton.icon(
                            onPressed: () => _accion(p, 'anular'),
                            icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                            label: const Text('Anular', style: TextStyle(color: Colors.red)),
                          ),
                        if (puedeAprobar && p.estado == 'calculada')
                          FilledButton.tonalIcon(
                            onPressed: () => _accion(p, 'aprobar'),
                            icon: const Icon(Icons.verified, size: 18),
                            label: const Text('Aprobar'),
                          ),
                        if (puedeAprobar && p.estado == 'aprobada') ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => _accion(p, 'pagar'),
                            icon: const Icon(Icons.payments, size: 18),
                            label: const Text('Marcar pagada'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _filaMonto(String label, double valor, Color color, {bool negrita = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: TextStyle(
              fontSize: 13, fontWeight: negrita ? FontWeight.bold : FontWeight.normal)),
          const Spacer(),
          Text(money(valor), style: TextStyle(
              fontSize: 13, color: color, fontWeight: negrita ? FontWeight.bold : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _tabConceptos() {
    if (_loadingConceptos) return const Center(child: CircularProgressIndicator());
    if (_conceptos.isEmpty) {
      return const EstadoVacio(
        icono: Icons.list_alt_outlined,
        titulo: 'Sin conceptos remunerativos registrados',
        subtitulo: 'Registra los conceptos que forman parte de la planilla.',
      );
    }
    final puedeEditar = AppSession.i.canCalcularPlanilla;
    final hayBase = _conceptos.any((c) => c.esBase);
    return RefreshIndicator(
      onRefresh: _cargarConceptos,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _conceptos.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          if (i == 0) {
            if (hayBase) return const SizedBox.shrink();
            return Card(
              color: Colors.amber.withValues(alpha: 0.12),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ningún concepto está marcado como Base (sueldo). '
                        'Los descuentos por asistencia (faltas/tardanzas) no se '
                        'calcularán hasta marcar uno.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final c = _conceptos[i - 1];
          final color = switch (c.tipo) {
            'ingreso' => Colors.green,
            'descuento' => Colors.deepOrange,
            _ => Colors.blueGrey,
          };
          // Solo un concepto de tipo ingreso tiene sentido como base (sueldo).
          final puedeSerBase = c.tipo == 'ingreso';
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(c.codigo, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              ),
              title: Row(
                children: [
                  Flexible(child: Text(c.nombre)),
                  if (c.esBase) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.withValues(alpha: 0.5)),
                      ),
                      child: const Text('Base (sueldo)',
                          style: TextStyle(color: Colors.purple, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
              subtitle: Text(c.tipo.replaceAll('_', ' ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.montoReferencial != null)
                    Text(money(c.montoReferencial!), style: const TextStyle(fontWeight: FontWeight.w600))
                  else if (!c.activo)
                    const Icon(Icons.visibility_off_outlined, size: 18, color: Colors.grey),
                  if (puedeEditar && puedeSerBase && !c.esBase) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Marcar como base (sueldo)',
                      icon: const Icon(Icons.star_outline, size: 20),
                      onPressed: () => _marcarBase(c),
                    ),
                  ] else if (c.esBase)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.star, size: 20, color: Colors.purple),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Detalle de planilla: boletas de pago por empleado ─────────────────────────

class _PantallaDetallePlanilla extends StatefulWidget {
  final Planilla planilla;
  const _PantallaDetallePlanilla({required this.planilla});

  @override
  State<_PantallaDetallePlanilla> createState() => _PantallaDetallePlanillaState();
}

// Códigos de descuento que provienen del módulo de asistencia.
const _codigosAsistencia = {'DESC_FALTA', 'DESC_TARDANZA'};

class _PantallaDetallePlanillaState extends State<_PantallaDetallePlanilla> {
  List<BoletaPago> _boletas = [];
  bool _loading = true;
  late Planilla _planilla; // mutable: se actualiza tras un override

  bool get _editable => _planilla.estado == 'calculada';

  @override
  void initState() {
    super.initState();
    _planilla = widget.planilla;
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final svc = await getFinanzasService();
    final rb = await svc.listarBoletas(_planilla.id);
    final rp = await svc.obtenerPlanilla(_planilla.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (rb.ok) _boletas = rb.data!;
      if (rp.ok) _planilla = rp.data!;
    });
    if (!rb.ok) mostrarError(context, rb.errorMessage);
  }

  Future<void> _editarDetalle(BoletaPago b, BoletaPagoDetalle d) async {
    final ctrl = TextEditingController(text: d.monto.toStringAsFixed(2));
    final esAsistencia = _codigosAsistencia.contains(d.conceptoCodigo);
    final nuevo = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(d.conceptoNombre ?? 'Concepto ${d.conceptoId}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (esAsistencia)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Descuento por asistencia. Ajusta o pon 0 para eliminarlo.',
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
              ),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Monto',
                helperText: '0 elimina el concepto de la boleta',
                border: OutlineInputBorder(),
                prefixText: 'S/ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.'));
              if (v == null || v < 0) {
                mostrarError(ctx, 'Ingresa un monto válido (≥ 0).');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (nuevo == null || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.editarDetalleBoleta(_planilla.id, b.id, d.conceptoId, nuevo);
    if (!mounted) return;
    if (r.ok) {
      setState(() => _planilla = r.data!);
      mostrarOk(context, 'Concepto actualizado. Totales recalculados.');
      _cargar(); // refresca boletas con los nuevos detalles
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _planilla;
    return Scaffold(
      appBar: AppBar(title: Text('Planilla ${p.fechaProceso}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              chipEstado(p.estado),
                              const Spacer(),
                              Text('Neto total', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(money(p.totalNeto),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _editable
                                ? 'Puedes ajustar (override) los conceptos de cada boleta antes de aprobar.'
                                : 'Solo lectura: la planilla ya no está en estado "calculada".',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Boletas de pago (${_boletas.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (_boletas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: EstadoVacio(
                        icono: Icons.receipt_long,
                        titulo: 'Sin boletas generadas',
                        subtitulo: 'Las boletas de pago aparecerán aquí cuando se generen.',
                      ),
                    )
                  else
                    ..._boletas.map(_buildBoleta),
                ],
              ),
            ),
    );
  }

  Widget _buildBoleta(BoletaPago b) {
    final ingresos = b.detalles.where((d) {
      final cod = d.conceptoCodigo ?? '';
      return !_codigosAsistencia.contains(cod) && d.monto >= 0 && !cod.startsWith('DESC');
    }).toList();
    final descuentos = b.detalles
        .where((d) => !ingresos.contains(d))
        .toList();
    return Card(
      child: ExpansionTile(
        leading: const CircleAvatar(child: Icon(Icons.badge_outlined)),
        title: Text(b.empleadoNombre ?? 'Empleado ${b.empleadoId}'),
        subtitle: Text('Neto: ${money(b.totalNeto)}'),
        children: [
          ListTile(
            dense: true,
            title: const Text('Ingresos'),
            trailing: Text(money(b.totalIngresos), style: const TextStyle(color: Colors.green)),
          ),
          ListTile(
            dense: true,
            title: const Text('Descuentos'),
            trailing: Text(money(b.totalDescuentos), style: const TextStyle(color: Colors.deepOrange)),
          ),
          ListTile(
            dense: true,
            title: const Text('Aportes empleador'),
            trailing: Text(money(b.totalAportes)),
          ),
          const Divider(height: 1),
          if (ingresos.isNotEmpty) ...[
            _seccionTitulo('Ingresos'),
            ...ingresos.map((d) => _filaDetalle(b, d)),
          ],
          if (descuentos.isNotEmpty) ...[
            _seccionTitulo('Descuentos'),
            ...descuentos.map((d) => _filaDetalle(b, d)),
          ],
        ],
      ),
    );
  }

  Widget _seccionTitulo(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600, letterSpacing: 0.5)),
      );

  Widget _filaDetalle(BoletaPago b, BoletaPagoDetalle d) {
    final esAsistencia = _codigosAsistencia.contains(d.conceptoCodigo);
    return ListTile(
      dense: true,
      leading: esAsistencia
          ? const Icon(Icons.event_busy, size: 16, color: Colors.deepOrange)
          : const Icon(Icons.fiber_manual_record, size: 10),
      title: Row(
        children: [
          Flexible(
            child: Text(
              d.conceptoNombre ?? 'Concepto ${d.conceptoId}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (esAsistencia) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Asistencia',
                  style: TextStyle(fontSize: 9.5, color: Colors.deepOrange, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(money(d.monto), style: const TextStyle(fontSize: 12)),
          if (_editable) ...[
            const SizedBox(width: 2),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Ajustar monto',
              icon: const Icon(Icons.edit, size: 16),
              onPressed: () => _editarDetalle(b, d),
            ),
          ],
        ],
      ),
      onTap: _editable ? () => _editarDetalle(b, d) : null,
    );
  }
}

// ── Formulario nuevo concepto remunerativo ────────────────────────────────────

class _FormConcepto extends StatefulWidget {
  final VoidCallback onGuardado;
  const _FormConcepto({required this.onGuardado});

  @override
  State<_FormConcepto> createState() => _FormConceptoState();
}

class _FormConceptoState extends State<_FormConcepto> {
  final _form = GlobalKey<FormState>();
  final _codigoCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  String _tipo = 'ingreso';
  bool _guardando = false;

  static const _tipos = ['ingreso', 'descuento', 'aporte_empleador'];

  @override
  void dispose() {
    _codigoCtrl.dispose();
    _nombreCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final monto = double.tryParse(_montoCtrl.text);
    final r = await svc.crearConceptoPlanilla(
      codigo: _codigoCtrl.text.trim(),
      nombre: _nombreCtrl.text.trim(),
      tipo: _tipo,
      montoReferencial: monto,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Concepto registrado');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nuevo concepto remunerativo', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codigoCtrl,
                decoration: const InputDecoration(labelText: 'Código', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                items: _tipos.map((t) => DropdownMenuItem(value: t, child: Text(t.replaceAll('_', ' ')))).toList(),
                onChanged: (v) => setState(() => _tipo = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Monto referencial (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Editor de sueldos por empleado (montos por concepto) ──────────────────────

class _FormSueldos extends StatefulWidget {
  final EmpleadoPlanilla empleado;
  final List<ConceptoRemunerativo> conceptos;
  final Map<String, double> montosActuales; // conceptoId -> monto override
  final VoidCallback onGuardado;
  const _FormSueldos({
    required this.empleado,
    required this.conceptos,
    required this.montosActuales,
    required this.onGuardado,
  });

  @override
  State<_FormSueldos> createState() => _FormSueldosState();
}

class _FormSueldosState extends State<_FormSueldos> {
  late final Map<String, TextEditingController> _ctrls;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final c in widget.conceptos)
        c.id: TextEditingController(
          text: widget.montosActuales.containsKey(c.id)
              ? widget.montosActuales[c.id]!.toStringAsFixed(2)
              : '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final items = <Map<String, dynamic>>[];
    for (final c in widget.conceptos) {
      final txt = _ctrls[c.id]!.text.trim();
      final tenia = widget.montosActuales.containsKey(c.id);
      if (txt.isEmpty) {
        // vacío: si tenía override lo eliminamos (vuelve al referencial)
        if (tenia) items.add({'concepto_id': c.id, 'monto': null});
        continue;
      }
      final monto = double.tryParse(txt.replaceAll(',', '.'));
      if (monto == null) continue;
      items.add({'concepto_id': c.id, 'monto': monto});
    }
    final svc = await getFinanzasService();
    final r = await svc.guardarAsignaciones(widget.empleado.id, items);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Sueldo de ${widget.empleado.nombre ?? 'empleado'} guardado');
      Navigator.pop(context);
      widget.onGuardado();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activos = widget.conceptos.where((c) => c.activo).toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.empleado.nombre ?? 'Empleado',
                style: Theme.of(context).textTheme.titleLarge),
            Text(widget.empleado.cargo ?? '',
                style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text(
              'Monto por concepto para este empleado. Vacío = usa el monto referencial del catálogo.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            if (activos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No hay conceptos activos')),
              )
            else
              ...activos.map((c) {
                final color = switch (c.tipo) {
                  'ingreso' => Colors.green,
                  'descuento' => Colors.deepOrange,
                  _ => Colors.blueGrey,
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _ctrls[c.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: c.nombre,
                      helperText: c.tipo.replaceAll('_', ' '),
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(Icons.circle, size: 12, color: color),
                      hintText: c.montoReferencial != null
                          ? 'ref: ${c.montoReferencial!.toStringAsFixed(2)}'
                          : null,
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Guardar sueldo'),
            ),
          ],
        ),
      ),
    );
  }
}
