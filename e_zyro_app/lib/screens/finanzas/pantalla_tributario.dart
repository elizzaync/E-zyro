import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';

/// Tributario / IGV: registro de compras y de ventas del periodo.
class PantallaTributario extends StatefulWidget {
  const PantallaTributario({super.key});

  @override
  State<PantallaTributario> createState() => _PantallaTributarioState();
}

class _PantallaTributarioState extends State<PantallaTributario> {
  FinanzasService? _svc;
  List<RegistroTributarioFila> _compras = [];
  List<RegistroTributarioFila> _ventas = [];
  String _periodo = periodoActual();
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
    final c = await _svc!.registroCompras(_periodo);
    final v = await _svc!.registroVentas(_periodo);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (c.ok) {
        _compras = c.data ?? [];
      } else {
        _error = c.errorMessage;
      }
      if (v.ok) _ventas = v.data ?? [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tributario / IGV', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Compras'), Tab(text: 'Ventas')]),
          actions: [
            IconButton(
              tooltip: 'Periodo',
              icon: const Icon(Icons.edit_calendar),
              onPressed: () async {
                final parts = _periodo.split('-');
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime(int.parse(parts[0]), int.parse(parts[1]), 1),
                  firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) {
                  setState(() => _periodo = '${d.year}-${d.month.toString().padLeft(2, '0')}');
                  await _cargar();
                }
              },
            ),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [
                    _registro(_compras, 'IGV crédito fiscal', Colors.deepOrange),
                    _registro(_ventas, 'IGV débito fiscal', Colors.teal),
                  ]),
      ),
    );
  }

  Widget _registro(List<RegistroTributarioFila> filas, String etiquetaIgv, Color color) {
    final base = filas.fold<double>(0, (a, f) => a + f.baseImponible);
    final igv = filas.fold<double>(0, (a, f) => a + f.igv);
    final total = filas.fold<double>(0, (a, f) => a + f.total);
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.07),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Periodo $_periodo', style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: _mini('Base', money(base), color)),
              const SizedBox(width: 8),
              Expanded(child: _mini(etiquetaIgv, money(igv), color)),
              const SizedBox(width: 8),
              Expanded(child: _mini('Total', money(total), color)),
            ],
          ),
        ),
        Expanded(
          child: filas.isEmpty
              ? const Center(child: Text('Sin documentos en el periodo.'))
              : ListView.separated(
                  itemCount: filas.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final f = filas[i];
                    return ListTile(
                      dense: true,
                      title: Text('${f.tipoDocumento.toUpperCase()} ${f.numeroDocumento}',
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text('${f.fecha} · ${f.tercero}${f.ruc != null ? ' · ${f.ruc}' : ''}',
                          style: const TextStyle(fontSize: 11)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(money(f.total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('IGV ${money(f.igv)}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _mini(String label, String valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(valor, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
