import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../utils/app_session.dart';
import 'finanzas_comun.dart';

/// Cuentas por Cobrar (AR): comprobantes a clientes, emisión y saldos.
class PantallaCuentasCobrar extends StatefulWidget {
  const PantallaCuentasCobrar({super.key});

  @override
  State<PantallaCuentasCobrar> createState() => _PantallaCuentasCobrarState();
}

class _PantallaCuentasCobrarState extends State<PantallaCuentasCobrar> {
  FinanzasService? _svc;
  List<Factura> _comprobantes = [];
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
    final fac = await _svc!.facturasCliente();
    final sal = await _svc!.saldosCliente();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (fac.ok) {
        _comprobantes = fac.data ?? [];
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
          title: const Text('Cuentas por Cobrar', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Comprobantes'), Tab(text: 'Saldos')]),
          actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
        ),
        floatingActionButton: AppSession.i.canEmitirComprobante
            ? FloatingActionButton.extended(
                onPressed: _nuevoComprobante,
                icon: const Icon(Icons.add),
                label: const Text('Emitir'),
              )
            : null,
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_tabComprobantes(), _tabSaldos()]),
      ),
    );
  }

  Widget _tabComprobantes() {
    if (_comprobantes.isEmpty) {
      return const Center(child: Text('Sin comprobantes emitidos.'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _comprobantes.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final f = _comprobantes[i];
          return ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text('${f.tipoDocumento.toUpperCase()} ${f.numeroDocumento}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('Emite ${f.fechaEmision}\n'
                'Total ${money(f.total)} · Saldo ${money(f.saldoPendiente)}',
                style: const TextStyle(fontSize: 11)),
            isThreeLine: true,
            trailing: chipEstado(f.estado),
          );
        },
      ),
    );
  }

  Widget _tabSaldos() {
    if (_saldos.isEmpty) {
      return const Center(child: Text('Sin saldos por cobrar.'));
    }
    final total = _saldos.fold<double>(0, (a, s) => a + s.saldoTotal);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TarjetaResumen(
            titulo: 'Total por cobrar',
            valor: money(total),
            color: Colors.teal,
            icono: Icons.savings_outlined,
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _saldos.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = _saldos[i];
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(s.nombre),
                subtitle: Text('${s.facturasAbiertas} comprobante(s) abierto(s)'),
                trailing: Text(money(s.saldoTotal),
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _nuevoComprobante() async {
    final clientes = await _svc!.clientes();
    if (!mounted) return;
    if (!clientes.ok || (clientes.data ?? []).isEmpty) {
      mostrarError(context, 'No hay clientes disponibles.');
      return;
    }
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormComprobante(svc: _svc!, clientes: clientes.data!),
    );
    if (creado == true) _cargar();
  }
}

/// Formulario de emisión de comprobante a cliente (crédito o contado).
class _FormComprobante extends StatefulWidget {
  final FinanzasService svc;
  final List<Tercero> clientes;
  const _FormComprobante({required this.svc, required this.clientes});

  @override
  State<_FormComprobante> createState() => _FormComprobanteState();
}

class _FormComprobanteState extends State<_FormComprobante> {
  String? _clienteId;
  String _tipoDoc = 'factura';
  bool _alContado = false;
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
    _clienteId = widget.clientes.first.id;
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
            const Text('Emitir comprobante',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _clienteId,
              decoration: const InputDecoration(labelText: 'Cliente', border: OutlineInputBorder()),
              items: widget.clientes.map((c) =>
                  DropdownMenuItem(value: c.id, child: Text(c.razonSocial, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _clienteId = v),
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
                    decoration: const InputDecoration(labelText: 'N° (serie-número)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Venta al contado'),
              subtitle: const Text('Carga caja en vez de cuentas por cobrar'),
              value: _alContado,
              onChanged: (v) => setState(() => _alContado = v),
            ),
            Row(
              children: [
                Expanded(child: _fechaTile('Emisión', _emision, (d) => setState(() => _emision = d))),
                const SizedBox(width: 12),
                Expanded(
                  child: _alContado
                      ? const SizedBox()
                      : _fechaTile('Vence', _vencimiento, (d) => setState(() => _vencimiento = d)),
                ),
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
                    : const Icon(Icons.send),
                label: const Text('Emitir (genera asiento)'),
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
    if (_clienteId == null || _numCtrl.text.trim().isEmpty || sub <= 0) {
      mostrarError(context, 'Completa cliente, número y subtotal > 0.');
      return;
    }
    setState(() => _guardando = true);
    final res = await widget.svc.emitirComprobante(
      clienteId: _clienteId!,
      numeroDocumento: _numCtrl.text.trim(),
      tipoDocumento: _tipoDoc,
      fechaEmision: _iso(_emision),
      fechaVencimiento: _alContado ? null : _iso(_vencimiento),
      subtotal: sub,
      igv: double.tryParse(_igvCtrl.text) ?? 0,
      alContado: _alContado,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      mostrarOk(context, 'Comprobante emitido y contabilizado.');
      Navigator.pop(context, true);
    } else {
      mostrarError(context, res.errorMessage);
    }
  }
}
