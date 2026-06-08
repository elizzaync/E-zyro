import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/finanzas_models.dart';
import '../../utils/app_session.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';

class PantallaCuentasCobrar extends StatefulWidget {
  const PantallaCuentasCobrar({super.key});
  @override
  State<PantallaCuentasCobrar> createState() => _State();
}

class _State extends State<PantallaCuentasCobrar>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Tab 0 — Comprobantes
  List<Factura> _comprobantes = [];
  bool _loadingComp = true;

  // Tab 1 — Saldos
  List<SaldoTercero> _saldos = [];
  bool _loadingSaldos = true;

  // Tab 2 — Cobros
  List<CobroCliente> _cobros = [];
  bool _loadingCobros = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _cargarTodo();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo() async {
    _cargarComprobantes();
    _cargarSaldos();
    _cargarCobros();
  }

  Future<void> _cargarComprobantes() async {
    setState(() => _loadingComp = true);
    final svc = await getFinanzasService();
    final r = await svc.facturasCliente();
    if (!mounted) return;
    setState(() {
      _loadingComp = false;
      if (r.ok) _comprobantes = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarSaldos() async {
    setState(() => _loadingSaldos = true);
    final svc = await getFinanzasService();
    final r = await svc.saldosCliente();
    if (!mounted) return;
    setState(() {
      _loadingSaldos = false;
      if (r.ok) _saldos = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarCobros() async {
    setState(() => _loadingCobros = true);
    final svc = await getFinanzasService();
    final r = await svc.listarCobros();
    if (!mounted) return;
    setState(() {
      _loadingCobros = false;
      if (r.ok) _cobros = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _anular(Factura f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular comprobante'),
        content: Text(
            '¿Anular ${f.numeroDocumento}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final svc = await getFinanzasService();
    final r = await svc.anularComprobante(f.id);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Comprobante anulado');
      _cargarComprobantes();
      _cargarSaldos();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _abrirFormComprobante() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormComprobante(onGuardado: () {
        _cargarComprobantes();
        _cargarSaldos();
      }),
    );
  }

  void _abrirFormCobro() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormCobro(
        comprobantesPendientes: _comprobantes
            .where((f) => f.estado == 'pendiente' || f.estado == 'parcial')
            .toList(),
        onGuardado: () {
          _cargarComprobantes();
          _cargarSaldos();
          _cargarCobros();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEmitir = AppSession.i.canEmitirComprobante;
    final canCobrar = AppSession.i.canRegistrarCobro;
    final canAnular = AppSession.i.isAdmin;

    FloatingActionButton? fab;
    if (_tabs.index == 0 && canEmitir) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormComprobante,
        icon: const Icon(Icons.add),
        label: const Text('Emitir comprobante'),
      );
    } else if (_tabs.index == 2 && canCobrar) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormCobro,
        icon: const Icon(Icons.attach_money),
        label: const Text('Registrar cobro'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas por Cobrar'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Comprobantes'),
            Tab(text: 'Saldos'),
            Tab(text: 'Cobros'),
          ],
        ),
      ),
      floatingActionButton: fab,
      body: TabBarView(
        controller: _tabs,
        children: [
          _TabComprobantes(
            comprobantes: _comprobantes,
            loading: _loadingComp,
            canAnular: canAnular,
            onAnular: _anular,
            onRefresh: _cargarComprobantes,
          ),
          _TabSaldos(
            saldos: _saldos,
            loading: _loadingSaldos,
            onRefresh: _cargarSaldos,
          ),
          _TabCobros(
            cobros: _cobros,
            loading: _loadingCobros,
            onRefresh: _cargarCobros,
          ),
        ],
      ),
    );
  }
}

// ── Tab Comprobantes ─────────────────────────────────────────────────────────

class _TabComprobantes extends StatelessWidget {
  final List<Factura> comprobantes;
  final bool loading;
  final bool canAnular;
  final void Function(Factura) onAnular;
  final Future<void> Function() onRefresh;

  const _TabComprobantes({
    required this.comprobantes,
    required this.loading,
    required this.canAnular,
    required this.onAnular,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (comprobantes.isEmpty) {
      return const Center(child: Text('Sin comprobantes emitidos'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: comprobantes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final f = comprobantes[i];
          return Card(
            child: ListTile(
              title: Text(f.numeroDocumento),
              subtitle: Text(
                '${f.tipoDocumento} · Vence ${f.fechaVencimiento}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money(f.total),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      chipEstado(f.estado),
                    ],
                  ),
                  if (canAnular && f.estado == 'pendiente')
                    IconButton(
                      icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                      tooltip: 'Anular',
                      onPressed: () => onAnular(f),
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

// ── Tab Saldos ───────────────────────────────────────────────────────────────

class _TabSaldos extends StatelessWidget {
  final List<SaldoTercero> saldos;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _TabSaldos({
    required this.saldos,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (saldos.isEmpty) {
      return const Center(child: Text('Sin saldos pendientes'));
    }
    final total = saldos.fold(0.0, (s, e) => s + e.saldoTotal);
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Column(
        children: [
          TarjetaResumen(
            titulo: 'Total por cobrar',
            valor: money(total),
            color: Colors.green.shade700,
            icono: Icons.account_balance_wallet,
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: saldos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = saldos[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(s.nombre),
                    subtitle:
                        Text('${s.facturasAbiertas} comprobante(s) pendiente(s)'),
                    trailing: Text(
                      money(s.saldoTotal),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab Cobros ───────────────────────────────────────────────────────────────

class _TabCobros extends StatelessWidget {
  final List<CobroCliente> cobros;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _TabCobros({
    required this.cobros,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (cobros.isEmpty) {
      return const Center(child: Text('Sin cobros registrados'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: cobros.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = cobros[i];
          return Card(
            child: ExpansionTile(
              leading: const CircleAvatar(child: Icon(Icons.attach_money)),
              title: Text(money(c.monto),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${c.fechaCobro} · ${c.medioPago}'
                '${c.referencia != null ? ' · ${c.referencia}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              children: c.aplicaciones
                  .map((a) => ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.receipt_outlined, size: 16),
                        title: Text('Comprobante ${a.facturaId}'),
                        trailing: Text(money(a.montoAplicado)),
                      ))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

// ── Formulario emitir comprobante ─────────────────────────────────────────────

class _FormComprobante extends StatefulWidget {
  final VoidCallback onGuardado;
  const _FormComprobante({required this.onGuardado});

  @override
  State<_FormComprobante> createState() => _FormComprobanteState();
}

class _FormComprobanteState extends State<_FormComprobante> {
  final _form = GlobalKey<FormState>();
  List<Tercero> _clientes = [];
  String? _clienteId;
  final _numCtrl = TextEditingController();
  String _tipo = 'factura';
  DateTime _emision = DateTime.now();
  DateTime? _vencimiento;
  final _subtotalCtrl = TextEditingController();
  final _igvCtrl = TextEditingController(text: '18');
  bool _alContado = false;
  bool _guardando = false;

  static const _tipos = ['factura', 'boleta', 'nota_credito'];

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    final svc = await getFinanzasService();
    final r = await svc.clientes();
    if (mounted && r.ok) setState(() => _clientes = r.data!);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_clienteId == null) {
      mostrarError(context, 'Selecciona un cliente');
      return;
    }
    setState(() => _guardando = true);
    final subtotal = double.tryParse(_subtotalCtrl.text) ?? 0;
    final igvPct = double.tryParse(_igvCtrl.text) ?? 18;
    final igv = subtotal * igvPct / 100;
    final fmt = DateFormat('yyyy-MM-dd');
    final svc = await getFinanzasService();
    final r = await svc.emitirComprobante(
      clienteId: _clienteId!,
      numeroDocumento: _numCtrl.text.trim(),
      tipoDocumento: _tipo,
      fechaEmision: fmt.format(_emision),
      fechaVencimiento:
          _vencimiento != null ? fmt.format(_vencimiento!) : null,
      subtotal: subtotal,
      igv: igv,
      alContado: _alContado,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Comprobante emitido');
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
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Emitir comprobante',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _clienteId,
                decoration: const InputDecoration(
                  labelText: 'Cliente',
                  border: OutlineInputBorder(),
                ),
                items: _clientes
                    .map((c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.razonSocial),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _clienteId = v),
                validator: (v) => v == null ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numCtrl,
                decoration: const InputDecoration(
                  labelText: 'N° documento',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo documento',
                  border: OutlineInputBorder(),
                ),
                items: _tipos
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _tipo = v!),
              ),
              const SizedBox(height: 12),
              _DateField(
                label: 'Fecha emisión',
                value: _emision,
                onChanged: (d) => setState(() => _emision = d),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Al contado'),
                value: _alContado,
                onChanged: (v) => setState(() {
                  _alContado = v;
                  if (v) _vencimiento = null;
                }),
                contentPadding: EdgeInsets.zero,
              ),
              if (!_alContado) ...[
                const SizedBox(height: 12),
                _DateField(
                  label: 'Fecha vencimiento',
                  value: _vencimiento ??
                      DateTime.now().add(const Duration(days: 30)),
                  onChanged: (d) => setState(() => _vencimiento = d),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _subtotalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Subtotal (S/)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final d = double.tryParse(v ?? '');
                        if (d == null || d <= 0) return 'Monto inválido';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _igvCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'IGV %',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Emitir'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Formulario registrar cobro ─────────────────────────────────────────────────

class _FormCobro extends StatefulWidget {
  final List<Factura> comprobantesPendientes;
  final VoidCallback onGuardado;

  const _FormCobro({
    required this.comprobantesPendientes,
    required this.onGuardado,
  });

  @override
  State<_FormCobro> createState() => _FormCobroState();
}

class _FormCobroState extends State<_FormCobro> {
  List<Tercero> _clientes = [];
  String? _clienteId;
  List<Factura> _comprobantesCliente = [];

  final Map<String, TextEditingController> _montos = {};
  final Set<String> _seleccionados = {};

  String _medioPago = 'efectivo';
  final _refCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  static const _medios = ['efectivo', 'transferencia', 'cheque'];

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  @override
  void dispose() {
    for (final c in _montos.values) c.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    final svc = await getFinanzasService();
    final r = await svc.clientes();
    if (mounted && r.ok) setState(() => _clientes = r.data!);
  }

  void _seleccionarCliente(String? id) {
    setState(() {
      _clienteId = id;
      _seleccionados.clear();
      for (final c in _montos.values) c.dispose();
      _montos.clear();
      _comprobantesCliente = id == null
          ? []
          : widget.comprobantesPendientes
              .where((f) => f.terceroId == id)
              .toList();
    });
  }

  double get _totalAplicado {
    double t = 0;
    for (final id in _seleccionados) {
      t += double.tryParse(_montos[id]?.text ?? '') ?? 0;
    }
    return t;
  }

  Future<void> _guardar() async {
    if (_clienteId == null) {
      mostrarError(context, 'Selecciona un cliente');
      return;
    }
    if (_seleccionados.isEmpty) {
      mostrarError(context, 'Selecciona al menos un comprobante');
      return;
    }
    final aplicaciones = <Map<String, dynamic>>[];
    for (final id in _seleccionados) {
      final m = double.tryParse(_montos[id]?.text ?? '') ?? 0;
      if (m <= 0) {
        mostrarError(
            context, 'Ingresa el monto para cada comprobante seleccionado');
        return;
      }
      aplicaciones.add({'factura_id': id, 'monto_aplicado': m});
    }
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.registrarCobro(
      clienteId: _clienteId!,
      fechaCobro: DateFormat('yyyy-MM-dd').format(_fecha),
      medioPago: _medioPago,
      aplicaciones: aplicaciones,
      referencia:
          _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Cobro registrado');
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
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Registrar cobro de cliente',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _clienteId,
              decoration: const InputDecoration(
                labelText: 'Cliente',
                border: OutlineInputBorder(),
              ),
              items: _clientes
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.razonSocial)))
                  .toList(),
              onChanged: _seleccionarCliente,
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Fecha de cobro',
              value: _fecha,
              onChanged: (d) => setState(() => _fecha = d),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _medioPago,
              decoration: const InputDecoration(
                labelText: 'Medio de pago',
                border: OutlineInputBorder(),
              ),
              items: _medios
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) => setState(() => _medioPago = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_comprobantesCliente.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Comprobantes pendientes',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._comprobantesCliente.map((f) {
                final sel = _seleccionados.contains(f.id);
                _montos.putIfAbsent(
                  f.id,
                  () => TextEditingController(
                      text: f.saldoPendiente.toStringAsFixed(2)),
                );
                return Card(
                  child: CheckboxListTile(
                    value: sel,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _seleccionados.add(f.id);
                      } else {
                        _seleccionados.remove(f.id);
                      }
                    }),
                    title: Text(f.numeroDocumento),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Saldo: ${money(f.saldoPendiente)}',
                            style: const TextStyle(fontSize: 12)),
                        if (sel)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: TextField(
                              controller: _montos[f.id],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Monto a cobrar (S/)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ] else if (_clienteId != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Este cliente no tiene comprobantes pendientes',
                style: TextStyle(color: Colors.grey),
              ),
            ],
            if (_seleccionados.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total a cobrar',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(money(_totalAplicado),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _guardando ? null : _guardar,
              child: _guardando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Registrar cobro'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget reutilizable DateField ─────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
        ),
        child: Text(DateFormat('dd/MM/yyyy').format(value)),
      ),
    );
  }
}
