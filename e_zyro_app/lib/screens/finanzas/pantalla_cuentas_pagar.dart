import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';

/// Cuentas por Pagar (AP): facturas de proveedores, registro y saldos.
class PantallaCuentasPagar extends StatefulWidget {
  const PantallaCuentasPagar({super.key});

  @override
  State<PantallaCuentasPagar> createState() => _PantallaCuentasPagarState();
}

class _PantallaCuentasPagarState extends State<PantallaCuentasPagar> {
  FinanzasService? _svc;
  List<Factura> _facturas = [];
  List<SaldoTercero> _saldos = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getFinanzasService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final fac = await _svc!.facturasProveedor();
    final sal = await _svc!.saldosProveedor();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (fac.ok) {
        _facturas = fac.data ?? [];
      } else {
        _error = fac.errorMessage;
      }
      if (sal.ok) _saldos = sal.data ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cuentas por Pagar', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Facturas'), Tab(text: 'Saldos')]),
          actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
        ),
        floatingActionButton: AppSession.i.canRegistrarFacturaCxp
            ? FloatingActionButton.extended(
                onPressed: _nuevaFactura,
                icon: const Icon(Icons.add),
                label: const Text('Nueva factura'),
              )
            : null,
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_tabFacturas(), _tabSaldos()]),
      ),
    );
  }

  Widget _tabFacturas() {
    if (_facturas.isEmpty) {
      return const Center(child: Text('Sin facturas de proveedor.'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _facturas.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final f = _facturas[i];
          return ListTile(
            leading: const Icon(Icons.receipt_outlined),
            title: Text('${f.tipoDocumento.toUpperCase()} ${f.numeroDocumento}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('Emite ${f.fechaEmision} · Vence ${f.fechaVencimiento}\n'
                'Total ${money(f.total)} · Saldo ${money(f.saldoPendiente)}',
                style: const TextStyle(fontSize: 11)),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                chipEstado(f.estado),
                if (AppSession.i.canAnularFacturaCxp && f.estado == 'pendiente')
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 28)),
                    onPressed: () => _anular(f),
                    child: const Text('Anular', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tabSaldos() {
    if (_saldos.isEmpty) {
      return const Center(child: Text('Sin saldos pendientes.'));
    }
    final total = _saldos.fold<double>(0, (a, s) => a + s.saldoTotal);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TarjetaResumen(
            titulo: 'Total por pagar',
            valor: money(total),
            color: Colors.deepOrange,
            icono: Icons.account_balance_wallet_outlined,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _saldos.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = _saldos[i];
              return ListTile(
                leading: const Icon(Icons.business_outlined),
                title: Text(s.nombre),
                subtitle: Text('${s.facturasAbiertas} factura(s) abierta(s)'),
                trailing: Text(money(s.saldoTotal),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _anular(Factura f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular factura'),
        content: Text('¿Anular ${f.numeroDocumento}? Se generará un asiento de reversión.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Anular', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _svc!.anularFacturaProveedor(f.id);
    if (!mounted) return;
    if (res.ok) {
      mostrarOk(context, 'Factura anulada (reversión contable generada).');
      _cargar();
    } else {
      mostrarError(context, res.errorMessage);
    }
  }

  Future<void> _nuevaFactura() async {
    final provs = await _svc!.proveedores();
    if (!mounted) return;
    if (!provs.ok || (provs.data ?? []).isEmpty) {
      mostrarError(context, 'No hay proveedores disponibles.');
      return;
    }
    final creada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormFacturaProveedor(svc: _svc!, proveedores: provs.data!),
    );
    if (creada == true) _cargar();
  }
}

/// Formulario de registro de factura de proveedor.
class _FormFacturaProveedor extends StatefulWidget {
  final FinanzasService svc;
  final List<Tercero> proveedores;
  const _FormFacturaProveedor({required this.svc, required this.proveedores});

  @override
  State<_FormFacturaProveedor> createState() => _FormFacturaProveedorState();
}

class _FormFacturaProveedorState extends State<_FormFacturaProveedor> {
  String? _proveedorId;
  String _tipoDoc = 'factura';
  final _numCtrl = TextEditingController();
  final _subtotalCtrl = TextEditingController();
  final _igvCtrl = TextEditingController();
  DateTime _emision = DateTime.now();
  DateTime _vencimiento = DateTime.now().add(const Duration(days: 30));
  bool _guardando = false;

  static const _tiposDoc = ['factura', 'boleta', 'nota_credito', 'nota_debito'];

  @override
  void initState() {
    super.initState();
    _proveedorId = widget.proveedores.first.id;
    // Calcula IGV 18% automáticamente al cambiar el subtotal.
    _subtotalCtrl.addListener(_recalcularIgv);
  }

  void _recalcularIgv() {
    final sub = double.tryParse(_subtotalCtrl.text) ?? 0;
    _igvCtrl.text = (sub * 0.18).toStringAsFixed(2);
    setState(() {});
  }

  double get _total =>
      (double.tryParse(_subtotalCtrl.text) ?? 0) + (double.tryParse(_igvCtrl.text) ?? 0);

  @override
  void dispose() {
    _numCtrl.dispose();
    _subtotalCtrl.dispose();
    _igvCtrl.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nueva factura de proveedor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _proveedorId,
              decoration: const InputDecoration(labelText: 'Proveedor', border: OutlineInputBorder()),
              items: widget.proveedores.map((p) =>
                  DropdownMenuItem(value: p.id, child: Text(p.razonSocial, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _proveedorId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _tipoDoc,
                    decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                    items: _tiposDoc.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => _tipoDoc = v ?? 'factura'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _numCtrl,
                    decoration: const InputDecoration(labelText: 'N° documento', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _fechaTile('Emisión', _emision, (d) => setState(() => _emision = d))),
                const SizedBox(width: 12),
                Expanded(child: _fechaTile('Vence', _vencimiento, (d) => setState(() => _vencimiento = d))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtotalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Subtotal', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _igvCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'IGV (18%)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Total: ${money(_total)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save),
                label: const Text('Registrar (genera asiento)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fechaTile(String label, DateTime val, ValueChanged<DateTime> onPick) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
          context: context, initialDate: val,
          firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (d != null) onPick(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Text(_iso(val), style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Future<void> _guardar() async {
    final sub = double.tryParse(_subtotalCtrl.text) ?? 0;
    if (_proveedorId == null || _numCtrl.text.trim().isEmpty || sub <= 0) {
      mostrarError(context, 'Completa proveedor, número y subtotal > 0.');
      return;
    }
    setState(() => _guardando = true);
    final res = await widget.svc.registrarFacturaProveedor(
      proveedorId: _proveedorId!,
      numeroDocumento: _numCtrl.text.trim(),
      tipoDocumento: _tipoDoc,
      fechaEmision: _iso(_emision),
      fechaVencimiento: _iso(_vencimiento),
      subtotal: sub,
      igv: double.tryParse(_igvCtrl.text) ?? 0,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      mostrarOk(context, 'Factura registrada y contabilizada.');
      Navigator.pop(context, true);
    } else {
      mostrarError(context, res.errorMessage);
    }
  }
}
