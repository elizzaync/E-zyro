import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';

/// Reportes financieros: balance general y estado de resultados, calculados en
/// vivo sobre el libro mayor.
class PantallaReportesFinancieros extends StatefulWidget {
  const PantallaReportesFinancieros({super.key});

  @override
  State<PantallaReportesFinancieros> createState() => _PantallaReportesFinancierosState();
}

class _PantallaReportesFinancierosState extends State<PantallaReportesFinancieros> {
  FinanzasService? _svc;
  BalanceGeneral? _balance;
  EstadoResultados? _resultados;
  DateTime _fecha = DateTime.now();
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

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final fechaStr = _iso(_fecha);
    final inicioMes = '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-01';
    final bg = await _svc!.balanceGeneral(fechaStr);
    final er = await _svc!.estadoResultados(inicioMes, fechaStr);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (bg.ok) {
        _balance = bg.data;
      } else {
        _error = bg.errorMessage;
      }
      _resultados = er.ok ? er.data : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reportes financieros', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Balance general'), Tab(text: 'Resultados')]),
          actions: [
            IconButton(
              tooltip: 'Fecha de corte',
              icon: const Icon(Icons.event),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context, initialDate: _fecha,
                  firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) { setState(() => _fecha = d); await _cargar(); }
              },
            ),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_tabBalance(), _tabResultados()]),
      ),
    );
  }

  Widget _bannerCorte() => Container(
        width: double.infinity,
        color: Colors.indigo.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Al ${_iso(_fecha)}', style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _tabBalance() {
    final b = _balance;
    if (b == null) return const Center(child: Text('Sin datos.'));
    return ListView(
      children: [
        _bannerCorte(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: TarjetaResumen(
                titulo: 'Activo', valor: money(b.totalActivo),
                color: Colors.green, icono: Icons.trending_up)),
              const SizedBox(width: 10),
              Expanded(child: TarjetaResumen(
                titulo: 'Pas. + Patrim.', valor: money(b.totalPasivoPatrimonio),
                color: Colors.deepOrange, icono: Icons.trending_down)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (b.cuadrado ? Colors.green : Colors.red).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Icon(b.cuadrado ? Icons.verified : Icons.error,
                  color: b.cuadrado ? Colors.green : Colors.red),
              const SizedBox(width: 10),
              Expanded(child: Text(b.cuadrado
                  ? 'Ecuación contable cumplida: Activo = Pasivo + Patrimonio'
                  : 'La ecuación contable NO cuadra')),
            ]),
          ),
        ),
        _seccion('ACTIVO', b.activo, Colors.green),
        _seccion('PASIVO', b.pasivo, Colors.deepOrange),
        _seccion('PATRIMONIO', b.patrimonio, Colors.indigo),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _seccion(String titulo, List<SeccionSaldo> filas, Color color) {
    if (filas.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
        ),
        ...filas.map((f) => ListTile(
              dense: true,
              title: Text(f.nombre, style: const TextStyle(fontSize: 13)),
              subtitle: Text(f.codigo, style: const TextStyle(fontSize: 11)),
              trailing: Text(money(f.saldo), style: const TextStyle(fontWeight: FontWeight.w600)),
            )),
      ],
    );
  }

  Widget _tabResultados() {
    final r = _resultados;
    if (r == null) return const Center(child: Text('Sin datos.'));
    final esGanancia = r.resultado >= 0;
    return ListView(
      children: [
        _bannerCorte(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TarjetaResumen(
            titulo: esGanancia ? 'Utilidad del periodo' : 'Pérdida del periodo',
            valor: money(r.resultado),
            color: esGanancia ? Colors.green : Colors.red,
            icono: esGanancia ? Icons.celebration_outlined : Icons.warning_amber_outlined,
          ),
        ),
        _seccionResultado('INGRESOS', r.ingresos, r.totalIngresos, Colors.green),
        _seccionResultado('GASTOS', r.gastos, r.totalGastos, Colors.deepOrange),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _seccionResultado(String titulo, List<LineaResultado> filas, double total, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text(titulo, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              const Spacer(),
              Text(money(total), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
        if (filas.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('— sin movimientos —',
              style: TextStyle(color: Colors.grey, fontSize: 12)))
        else
          ...filas.map((f) => ListTile(
                dense: true,
                title: Text(f.nombre, style: const TextStyle(fontSize: 13)),
                subtitle: Text(f.codigo, style: const TextStyle(fontSize: 11)),
                trailing: Text(money(f.monto)),
              )),
      ],
    );
  }
}
