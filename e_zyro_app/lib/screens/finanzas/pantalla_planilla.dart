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
        actions: [accionConmutadorFinanzas(context, actual: FinId.planilla)],
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
    if (_empleados.isEmpty) return const Center(child: Text('Sin empleados activos'));
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
    if (_planillas.isEmpty) return const Center(child: Text('Sin planillas procesadas'));
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
    if (_conceptos.isEmpty) return const Center(child: Text('Sin conceptos remunerativos registrados'));
    return RefreshIndicator(
      onRefresh: _cargarConceptos,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _conceptos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final c = _conceptos[i];
          final color = switch (c.tipo) {
            'ingreso' => Colors.green,
            'descuento' => Colors.deepOrange,
            _ => Colors.blueGrey,
          };
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Text(c.codigo, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
              ),
              title: Text(c.nombre),
              subtitle: Text(c.tipo.replaceAll('_', ' ')),
              trailing: c.montoReferencial != null
                  ? Text(money(c.montoReferencial!), style: const TextStyle(fontWeight: FontWeight.w600))
                  : (c.activo ? null : const Icon(Icons.visibility_off_outlined, size: 18, color: Colors.grey)),
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

class _PantallaDetallePlanillaState extends State<_PantallaDetallePlanilla> {
  List<BoletaPago> _boletas = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final svc = await getFinanzasService();
    final r = await svc.listarBoletas(widget.planilla.id);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) _boletas = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.planilla;
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
                      child: Center(child: Text('Sin boletas generadas', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    ..._boletas.map((b) => Card(
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
                              ...b.detalles.map((d) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.fiber_manual_record, size: 10),
                                    title: Text(
                                      d.conceptoNombre ?? 'Concepto ${d.conceptoId}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: Text(money(d.monto), style: const TextStyle(fontSize: 12)),
                                  )),
                            ],
                          ),
                        )),
                ],
              ),
            ),
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
