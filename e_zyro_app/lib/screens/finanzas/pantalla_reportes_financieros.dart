import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

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

  DateTime _periodoFecha = DateTime.now();
  Map<String, dynamic>? _flujo;
  List<dynamic>? _libroDiario;
  bool _cargandoPeriodo = true;

  List<CuentaContable> _cuentas = [];
  String? _cuentaId;
  Map<String, dynamic>? _libroMayor;
  bool _cargandoMayor = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getFinanzasService();
    await Future.wait([_cargar(), _cargarPeriodo(), _cargarCuentas()]);
  }

  String _iso(DateTime d) => d.toIso8601String().substring(0, 10);
  String get _periodo => '${_periodoFecha.year}-${_periodoFecha.month.toString().padLeft(2, '0')}';

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

  Future<void> _cargarPeriodo() async {
    if (_svc == null) return;
    setState(() => _cargandoPeriodo = true);
    final periodo = _periodo;
    final fe = await _svc!.flujoEfectivo(periodo);
    final ld = await _svc!.libroDiario(periodo);
    if (!mounted) return;
    setState(() {
      _cargandoPeriodo = false;
      _flujo = fe.ok ? fe.data : null;
      _libroDiario = ld.ok ? ld.data : null;
    });
  }

  Future<void> _cargarCuentas() async {
    if (_svc == null) return;
    final r = await _svc!.planCuentas(soloActivas: true);
    if (!mounted || !r.ok) return;
    setState(() => _cuentas = r.data!.where((c) => c.esDetalle).toList());
  }

  Future<void> _cargarLibroMayor() async {
    if (_svc == null || _cuentaId == null) return;
    setState(() => _cargandoMayor = true);
    final r = await _svc!.libroMayor(_cuentaId!, _periodo);
    if (!mounted) return;
    setState(() {
      _cargandoMayor = false;
      _libroMayor = r.ok ? r.data : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reportes financieros', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Balance general'),
            Tab(text: 'Resultados'),
            Tab(text: 'Flujo de efectivo'),
            Tab(text: 'Libro diario'),
            Tab(text: 'Libro mayor'),
          ]),
          actions: [
            accionConmutadorFinanzas(context, actual: FinId.reportes),
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
            IconButton(
              tooltip: 'Periodo (libros y flujo)',
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context, initialDate: _periodoFecha,
                  firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) {
                  setState(() => _periodoFecha = DateTime(d.year, d.month));
                  await _cargarPeriodo();
                  if (_cuentaId != null) await _cargarLibroMayor();
                }
              },
            ),
            IconButton(onPressed: () async {
              await _cargar();
              await _cargarPeriodo();
              if (_cuentaId != null) await _cargarLibroMayor();
            }, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [
                    _tabBalance(),
                    _tabResultados(),
                    _tabFlujoEfectivo(),
                    _tabLibroDiario(),
                    _tabLibroMayor(),
                  ]),
      ),
    );
  }

  Widget _bannerPeriodo() => Container(
        width: double.infinity,
        color: Colors.indigo.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Periodo $_periodo', style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _tabFlujoEfectivo() {
    if (_cargandoPeriodo) return const Center(child: CircularProgressIndicator());
    final f = _flujo;
    if (f == null) return const Center(child: Text('Sin datos.'));
    final detalle = (f['detalle'] as List<dynamic>? ?? []);
    return ListView(
      children: [
        _bannerPeriodo(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TarjetaResumen(
                titulo: 'Entradas', valor: money(_toNum(f['total_entradas'])),
                color: Colors.green, icono: Icons.arrow_downward)),
            const SizedBox(width: 10),
            Expanded(child: TarjetaResumen(
                titulo: 'Salidas', valor: money(_toNum(f['total_salidas'])),
                color: Colors.deepOrange, icono: Icons.arrow_upward)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TarjetaResumen(
            titulo: 'Flujo neto', valor: money(_toNum(f['flujo_neto'])),
            color: _toNum(f['flujo_neto']) >= 0 ? Colors.green : Colors.red,
            icono: Icons.account_balance_wallet_outlined,
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('POR ORIGEN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        ),
        if (detalle.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('— sin movimientos —',
              style: TextStyle(color: Colors.grey, fontSize: 12)))
        else
          ...detalle.map((d) => ListTile(
                dense: true,
                title: Text((d['origen'] ?? '').toString()),
                subtitle: Text('Entradas: ${money(_toNum(d['entradas']))}   ·   Salidas: ${money(_toNum(d['salidas']))}',
                    style: const TextStyle(fontSize: 11)),
                trailing: Text(money(_toNum(d['neto'])), style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _tabLibroDiario() {
    if (_cargandoPeriodo) return const Center(child: CircularProgressIndicator());
    final asientos = _libroDiario;
    if (asientos == null) return const Center(child: Text('Sin datos.'));
    if (asientos.isEmpty) {
      return ListView(children: [_bannerPeriodo(), const Padding(
        padding: EdgeInsets.all(16),
        child: Text('— sin asientos en el periodo —', style: TextStyle(color: Colors.grey)),
      )]);
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: asientos.length + 1,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i == 0) return _bannerPeriodo();
        final a = asientos[i - 1] as Map<String, dynamic>;
        final lineas = (a['lineas'] as List<dynamic>? ?? []);
        return ExpansionTile(
          title: Text('N° ${a['numero']}  ·  ${(a['fecha'] ?? '').toString()}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          subtitle: Text('${a['descripcion'] ?? ''}  ·  ${a['origen'] ?? ''}',
              style: const TextStyle(fontSize: 11)),
          children: lineas.map((l) {
            final m = l as Map<String, dynamic>;
            return ListTile(
              dense: true,
              title: Text('${m['codigo']}  ${m['nombre']}', style: const TextStyle(fontSize: 12)),
              trailing: Text(
                '${_toNum(m['debito']) > 0 ? 'D ${money(_toNum(m['debito']))}' : ''}'
                '${_toNum(m['credito']) > 0 ? 'H ${money(_toNum(m['credito']))}' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _tabLibroMayor() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            initialValue: _cuentaId,
            decoration: const InputDecoration(labelText: 'Cuenta', border: OutlineInputBorder(), isDense: true),
            items: _cuentas.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.codigo} — ${c.nombre}',
                overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) {
              setState(() => _cuentaId = v);
              if (v != null) _cargarLibroMayor();
            },
          ),
        ),
        Expanded(child: _cuerpoLibroMayor()),
      ],
    );
  }

  Widget _cuerpoLibroMayor() {
    if (_cuentaId == null) return const Center(child: Text('Seleccione una cuenta.'));
    if (_cargandoMayor) return const Center(child: CircularProgressIndicator());
    final m = _libroMayor;
    if (m == null) return const Center(child: Text('Sin datos.'));
    final movimientos = (m['movimientos'] as List<dynamic>? ?? []);
    return ListView(
      children: [
        _bannerPeriodo(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TarjetaResumen(
                titulo: '${m['cuenta_codigo']} — ${m['cuenta_nombre']}',
                valor: 'Saldo final: ${money(_toNum(m['saldo_final']))}',
                color: Colors.indigo, icono: Icons.menu_book_outlined)),
          ]),
        ),
        if (movimientos.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('— sin movimientos —',
              style: TextStyle(color: Colors.grey, fontSize: 12)))
        else
          ...movimientos.map((mv) {
            final v = mv as Map<String, dynamic>;
            return ListTile(
              dense: true,
              title: Text('N° ${v['numero']}  ·  ${(v['fecha'] ?? '').toString()}', style: const TextStyle(fontSize: 12)),
              subtitle: Text((v['descripcion'] ?? '').toString(), style: const TextStyle(fontSize: 11)),
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_toNum(v['debito']) > 0 ? 'D ${money(_toNum(v['debito']))}' : ''}'
                    '${_toNum(v['credito']) > 0 ? 'H ${money(_toNum(v['credito']))}' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text('Saldo: ${money(_toNum(v['saldo']))}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          }),
        const SizedBox(height: 24),
      ],
    );
  }

  double _toNum(dynamic v) => v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  Widget _bannerCorte() => Container(
        width: double.infinity,
        color: Colors.indigo.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('Al ${_iso(_fecha)}', style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _tabBalance() {
    final b = _balance;
    if (b == null) return const Center(child: Text('Sin datos.'));
    final sinSaldos = b.activo.isEmpty && b.pasivo.isEmpty && b.patrimonio.isEmpty;
    return Column(
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
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: sinSaldos
                ? Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                          child: Text('Detalle por rubro',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        const Expanded(
                          child: EstadoVacio(
                            icono: Icons.bar_chart,
                            titulo: 'Aún sin saldos para desglosar',
                            subtitulo: 'Registra asientos contables para ver el detalle por rubro del balance.',
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    children: [
                      _seccion('ACTIVO', b.activo, Colors.green),
                      _seccion('PASIVO', b.pasivo, Colors.deepOrange),
                      _seccion('PATRIMONIO', b.patrimonio, Colors.indigo),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ),
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
