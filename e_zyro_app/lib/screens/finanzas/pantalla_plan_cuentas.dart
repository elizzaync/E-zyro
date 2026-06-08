import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';

/// Plan de cuentas (PCGE) + balance de comprobación del periodo.
class PantallaPlanCuentas extends StatefulWidget {
  const PantallaPlanCuentas({super.key});

  @override
  State<PantallaPlanCuentas> createState() => _PantallaPlanCuentasState();
}

class _PantallaPlanCuentasState extends State<PantallaPlanCuentas> {
  FinanzasService? _svc;
  List<CuentaContable> _cuentas = [];
  BalanceComprobacion? _balance;
  String _periodo = periodoActual();
  bool _cargando = true;
  String? _error;
  String _filtroTipo = 'todos';

  static const _tipos = ['todos', 'activo', 'pasivo', 'patrimonio', 'ingreso', 'gasto'];

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
    final cuentas = await _svc!.planCuentas(soloActivas: false);
    final balance = await _svc!.balanceComprobacion(_periodo);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (cuentas.ok) {
        _cuentas = cuentas.data ?? [];
      } else {
        _error = cuentas.errorMessage;
      }
      _balance = balance.ok ? balance.data : null;
    });
  }

  List<CuentaContable> get _filtradas => _filtroTipo == 'todos'
      ? _cuentas
      : _cuentas.where((c) => c.tipo == _filtroTipo).toList();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Plan de cuentas', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Cuentas'), Tab(text: 'Comprobación')]),
          actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_tabCuentas(), _tabBalance()]),
      ),
    );
  }

  Widget _tabCuentas() {
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: _tipos.map((t) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(t),
                selected: _filtroTipo == t,
                onSelected: (_) => setState(() => _filtroTipo = t),
              ),
            )).toList(),
          ),
        ),
        Expanded(
          child: _filtradas.isEmpty
              ? const Center(child: Text('Sin cuentas.'))
              : ListView.separated(
                  itemCount: _filtradas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = _filtradas[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 18,
                        backgroundColor: c.esDetalle ? Colors.green.shade100 : Colors.grey.shade200,
                        child: Text(c.codigo.length > 4 ? c.codigo.substring(0, 4) : c.codigo,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(c.nombre, style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${c.codigo} · ${c.tipo} · ${c.naturaleza}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: c.esDetalle
                          ? const Icon(Icons.edit_note, size: 18, color: Colors.green)
                          : const Icon(Icons.folder_outlined, size: 18, color: Colors.grey),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _tabBalance() {
    final b = _balance;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.calendar_month, size: 18),
              const SizedBox(width: 8),
              Text('Periodo: $_periodo'),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.edit_calendar, size: 18),
                label: const Text('Cambiar'),
                onPressed: _elegirPeriodo,
              ),
            ],
          ),
        ),
        if (b != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (b.cuadrado ? Colors.green : Colors.red).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(b.cuadrado ? Icons.check_circle : Icons.error,
                    color: b.cuadrado ? Colors.green : Colors.red),
                const SizedBox(width: 10),
                Expanded(child: Text(b.cuadrado
                    ? 'Balance cuadrado: Debe = Haber'
                    : 'DESCUADRE detectado')),
                Text(money(b.totalDeudor), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        Expanded(
          child: (b == null || b.cuentas.isEmpty)
              ? const Center(child: Text('Sin movimientos en el periodo.'))
              : ListView.separated(
                  padding: const EdgeInsets.only(top: 8),
                  itemCount: b.cuentas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = b.cuentas[i];
                    return ListTile(
                      dense: true,
                      title: Text('${f.codigo} · ${f.nombre}', style: const TextStyle(fontSize: 12)),
                      subtitle: Text('Debe ${money(f.totalDebito)} · Haber ${money(f.totalCredito)}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (f.saldoDeudor > 0)
                            Text(money(f.saldoDeudor),
                                style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                          if (f.saldoAcreedor > 0)
                            Text(money(f.saldoAcreedor),
                                style: const TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _elegirPeriodo() async {
    final elegido = await _pickPeriodo(context, _periodo);
    if (elegido != null && elegido != _periodo) {
      setState(() => _periodo = elegido);
      await _cargar();
    }
  }
}

/// Selector simple de periodo 'YYYY-MM' vía date picker (se toma año-mes).
Future<String?> pickPeriodoMes(BuildContext context, String actual) => _pickPeriodo(context, actual);

Future<String?> _pickPeriodo(BuildContext context, String actual) async {
  final parts = actual.split('-');
  final inicial = DateTime(int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1, 1);
  final d = await showDatePicker(
    context: context,
    initialDate: inicial,
    firstDate: DateTime(2020, 1, 1),
    lastDate: DateTime(2100, 12, 31),
    helpText: 'Elige cualquier día del mes',
  );
  if (d == null) return null;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}';
}
