import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/finanzas_models.dart';
import '../../utils/app_session.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';

class PantallaCuentasPagar extends StatefulWidget {
  const PantallaCuentasPagar({super.key});
  @override
  State<PantallaCuentasPagar> createState() => _State();
}

class _State extends State<PantallaCuentasPagar>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Tab 0 — Facturas
  List<Factura> _facturas = [];
  bool _loadingFacturas = true;

  // Tab 1 — Saldos
  List<SaldoTercero> _saldos = [];
  bool _loadingSaldos = true;

  // Tab 2 — Pagos
  List<PagoProveedor> _pagos = [];
  bool _loadingPagos = true;

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
    _cargarFacturas();
    _cargarSaldos();
    _cargarPagos();
  }

  Future<void> _cargarFacturas() async {
    setState(() => _loadingFacturas = true);
    final svc = await getFinanzasService();
    final r = await svc.facturasProveedor();
    if (!mounted) return;
    setState(() {
      _loadingFacturas = false;
      if (r.ok) _facturas = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarSaldos() async {
    setState(() => _loadingSaldos = true);
    final svc = await getFinanzasService();
    final r = await svc.saldosProveedor();
    if (!mounted) return;
    setState(() {
      _loadingSaldos = false;
      if (r.ok) _saldos = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _cargarPagos() async {
    setState(() => _loadingPagos = true);
    final svc = await getFinanzasService();
    final r = await svc.listarPagos();
    if (!mounted) return;
    setState(() {
      _loadingPagos = false;
      if (r.ok) _pagos = r.data!;
    });
    if (!r.ok) mostrarError(context, r.errorMessage);
  }

  Future<void> _anular(Factura f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anular factura'),
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
    final r = await svc.anularFacturaProveedor(f.id);
    if (!mounted) return;
    if (r.ok) {
      mostrarOk(context, 'Factura anulada');
      _cargarFacturas();
      _cargarSaldos();
    } else {
      mostrarError(context, r.errorMessage);
    }
  }

  void _abrirFormFactura() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormFactura(onGuardado: () {
        _cargarFacturas();
        _cargarSaldos();
      }),
    );
  }

  void _abrirFormPago() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormPago(
        facturasPendientes: _facturas
            .where((f) => f.estado == 'pendiente' || f.estado == 'parcial')
            .toList(),
        onGuardado: () {
          _cargarFacturas();
          _cargarSaldos();
          _cargarPagos();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRegFactura = AppSession.i.canRegistrarFacturaCxp;
    final canPagar = AppSession.i.canRegistrarPagoCxp;
    final canAnular = AppSession.i.canAnularFacturaCxp;

    FloatingActionButton? fab;
    if (_tabs.index == 0 && canRegFactura) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormFactura,
        icon: const Icon(Icons.add),
        label: const Text('Nueva factura'),
      );
    } else if (_tabs.index == 2 && canPagar) {
      fab = FloatingActionButton.extended(
        onPressed: _abrirFormPago,
        icon: const Icon(Icons.payment),
        label: const Text('Registrar pago'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuentas por Pagar'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Facturas'),
            Tab(text: 'Saldos'),
            Tab(text: 'Pagos'),
          ],
        ),
      ),
      floatingActionButton: fab,
      body: TabBarView(
        controller: _tabs,
        children: [
          _TabFacturas(
            facturas: _facturas,
            loading: _loadingFacturas,
            canAnular: canAnular,
            onAnular: _anular,
            onRefresh: _cargarFacturas,
          ),
          _TabSaldos(
            saldos: _saldos,
            loading: _loadingSaldos,
            onRefresh: _cargarSaldos,
          ),
          _TabPagos(
            pagos: _pagos,
            loading: _loadingPagos,
            onRefresh: _cargarPagos,
          ),
        ],
      ),
    );
  }
}

// ── Tab Facturas ─────────────────────────────────────────────────────────────

class _TabFacturas extends StatelessWidget {
  final List<Factura> facturas;
  final bool loading;
  final bool canAnular;
  final void Function(Factura) onAnular;
  final Future<void> Function() onRefresh;

  const _TabFacturas({
    required this.facturas,
    required this.loading,
    required this.canAnular,
    required this.onAnular,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (facturas.isEmpty) {
      return const Center(child: Text('Sin facturas registradas'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: facturas.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final f = facturas[i];
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
            titulo: 'Total por pagar',
            valor: money(total),
            color: Colors.red.shade700,
            icono: Icons.account_balance_wallet,
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: saldos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final s = saldos[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.business)),
                    title: Text(s.nombre),
                    subtitle:
                        Text('${s.facturasAbiertas} factura(s) pendiente(s)'),
                    trailing: Text(
                      money(s.saldoTotal),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
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

// ── Tab Pagos ────────────────────────────────────────────────────────────────

class _TabPagos extends StatelessWidget {
  final List<PagoProveedor> pagos;
  final bool loading;
  final Future<void> Function() onRefresh;

  const _TabPagos({
    required this.pagos,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (pagos.isEmpty) {
      return const Center(child: Text('Sin pagos registrados'));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: pagos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final p = pagos[i];
          return Card(
            child: ExpansionTile(
              leading: const CircleAvatar(child: Icon(Icons.payment)),
              title: Text(money(p.monto),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${p.fechaPago} · ${p.medioPago}'
                '${p.referencia != null ? ' · ${p.referencia}' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              children: p.aplicaciones
                  .map((a) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.receipt_outlined, size: 16),
                        title: Text('Factura ${a.facturaId}'),
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

// ── Formulario nueva factura ─────────────────────────────────────────────────

class _FormFactura extends StatefulWidget {
  final VoidCallback onGuardado;
  const _FormFactura({required this.onGuardado});

  @override
  State<_FormFactura> createState() => _FormFacturaState();
}

class _FormFacturaState extends State<_FormFactura> {
  final _form = GlobalKey<FormState>();
  List<Tercero> _proveedores = [];
  String? _proveedorId;
  final _numCtrl = TextEditingController();
  String _tipo = 'factura';
  DateTime _emision = DateTime.now();
  DateTime _vencimiento = DateTime.now().add(const Duration(days: 30));
  final _subtotalCtrl = TextEditingController();
  final _igvCtrl = TextEditingController(text: '18');
  bool _guardando = false;

  static const _tipos = ['factura', 'boleta', 'nota_debito', 'nota_credito'];

  @override
  void initState() {
    super.initState();
    _cargarProveedores();
  }

  Future<void> _cargarProveedores() async {
    final svc = await getFinanzasService();
    final r = await svc.proveedores();
    if (mounted && r.ok) setState(() => _proveedores = r.data!);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    if (_proveedorId == null) {
      mostrarError(context, 'Selecciona un proveedor');
      return;
    }
    setState(() => _guardando = true);
    final subtotal = double.tryParse(_subtotalCtrl.text) ?? 0;
    final igvPct = double.tryParse(_igvCtrl.text) ?? 18;
    final igv = subtotal * igvPct / 100;
    final fmt = DateFormat('yyyy-MM-dd');
    final svc = await getFinanzasService();
    final r = await svc.registrarFacturaProveedor(
      proveedorId: _proveedorId!,
      numeroDocumento: _numCtrl.text.trim(),
      tipoDocumento: _tipo,
      fechaEmision: fmt.format(_emision),
      fechaVencimiento: fmt.format(_vencimiento),
      subtotal: subtotal,
      igv: igv,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Factura registrada');
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
              Text('Nueva factura de proveedor',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _proveedorId,
                decoration: const InputDecoration(
                  labelText: 'Proveedor',
                  border: OutlineInputBorder(),
                ),
                items: _proveedores
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.razonSocial),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _proveedorId = v),
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
                initialValue: _tipo,
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
              _DateField(
                label: 'Fecha vencimiento',
                value: _vencimiento,
                onChanged: (d) => setState(() => _vencimiento = d),
              ),
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
                    : const Text('Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Formulario registrar pago ─────────────────────────────────────────────────

class _FormPago extends StatefulWidget {
  final List<Factura> facturasPendientes;
  final VoidCallback onGuardado;

  const _FormPago({
    required this.facturasPendientes,
    required this.onGuardado,
  });

  @override
  State<_FormPago> createState() => _FormPagoState();
}

class _FormPagoState extends State<_FormPago> {
  List<Tercero> _proveedores = [];
  String? _proveedorId;
  List<Factura> _facturasProveedor = [];

  final Map<String, TextEditingController> _montos = {};
  final Set<String> _seleccionadas = {};

  String _medioPago = 'efectivo';
  final _refCtrl = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  static const _medios = ['efectivo', 'transferencia', 'cheque'];

  @override
  void initState() {
    super.initState();
    _cargarProveedores();
  }

  @override
  void dispose() {
    for (final c in _montos.values) {
      c.dispose();
    }
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarProveedores() async {
    final svc = await getFinanzasService();
    final r = await svc.proveedores();
    if (mounted && r.ok) setState(() => _proveedores = r.data!);
  }

  void _seleccionarProveedor(String? id) {
    setState(() {
      _proveedorId = id;
      _seleccionadas.clear();
      for (final c in _montos.values) {
        c.dispose();
      }
      _montos.clear();
      _facturasProveedor = id == null
          ? []
          : widget.facturasPendientes
              .where((f) => f.terceroId == id)
              .toList();
    });
  }

  double get _totalAplicado {
    double t = 0;
    for (final id in _seleccionadas) {
      t += double.tryParse(_montos[id]?.text ?? '') ?? 0;
    }
    return t;
  }

  Future<void> _guardar() async {
    if (_proveedorId == null) {
      mostrarError(context, 'Selecciona un proveedor');
      return;
    }
    if (_seleccionadas.isEmpty) {
      mostrarError(context, 'Selecciona al menos una factura');
      return;
    }
    final aplicaciones = <Map<String, dynamic>>[];
    for (final id in _seleccionadas) {
      final m = double.tryParse(_montos[id]?.text ?? '') ?? 0;
      if (m <= 0) {
        mostrarError(
            context, 'Ingresa el monto para cada factura seleccionada');
        return;
      }
      aplicaciones.add({'factura_id': id, 'monto_aplicado': m});
    }
    setState(() => _guardando = true);
    final svc = await getFinanzasService();
    final r = await svc.registrarPagoProveedor(
      proveedorId: _proveedorId!,
      fechaPago: DateFormat('yyyy-MM-dd').format(_fecha),
      medioPago: _medioPago,
      aplicaciones: aplicaciones,
      referencia:
          _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      mostrarOk(context, 'Pago registrado');
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
            Text('Registrar pago a proveedor',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _proveedorId,
              decoration: const InputDecoration(
                labelText: 'Proveedor',
                border: OutlineInputBorder(),
              ),
              items: _proveedores
                  .map((p) =>
                      DropdownMenuItem(value: p.id, child: Text(p.razonSocial)))
                  .toList(),
              onChanged: _seleccionarProveedor,
            ),
            const SizedBox(height: 12),
            _DateField(
              label: 'Fecha de pago',
              value: _fecha,
              onChanged: (d) => setState(() => _fecha = d),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _medioPago,
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
            if (_facturasProveedor.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Facturas pendientes',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._facturasProveedor.map((f) {
                final sel = _seleccionadas.contains(f.id);
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
                        _seleccionadas.add(f.id);
                      } else {
                        _seleccionadas.remove(f.id);
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
                                labelText: 'Monto a aplicar (S/)',
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
            ] else if (_proveedorId != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Este proveedor no tiene facturas pendientes',
                style: TextStyle(color: Colors.grey),
              ),
            ],
            if (_seleccionadas.isNotEmpty) ...[
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
                    const Text('Total a pagar',
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
                  : const Text('Registrar pago'),
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
