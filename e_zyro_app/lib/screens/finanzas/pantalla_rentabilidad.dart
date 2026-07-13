import 'package:flutter/material.dart';

import '../../models/finanzas_models.dart';
import '../../services/finanzas_service.dart';
import '../../utils/api_provider.dart';
import '../../theme/ez_theme.dart';
import 'finanzas_comun.dart';
import 'finanzas_navegacion.dart';

/// Rentabilidad por proyecto: ingresos facturados − costos imputados −
/// mano de obra estimada (horas de asistencia × sueldo base). Solo lectura.
class PantallaRentabilidad extends StatefulWidget {
  const PantallaRentabilidad({super.key});
  @override
  State<PantallaRentabilidad> createState() => _PantallaRentabilidadState();
}

class _PantallaRentabilidadState extends State<PantallaRentabilidad> {
  FinanzasService? _svc;
  List<RentabilidadProyecto> _filas = [];
  bool _cargando = true;
  String? _error;
  DateTimeRange? _rango;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getFinanzasService();
    await _cargar();
  }

  String? _iso(DateTime? d) => d?.toIso8601String().substring(0, 10);

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final r = await _svc!.rentabilidadProyectos(
        desde: _iso(_rango?.start), hasta: _iso(_rango?.end));
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _filas = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _rango,
    );
    if (r != null || _rango != null) {
      setState(() => _rango = r);
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rentabilidad', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          accionConmutadorFinanzas(context, actual: FinId.rentabilidad),
          IconButton(
            tooltip: 'Filtrar por fechas',
            icon: Icon(_rango == null ? Icons.date_range_outlined : Icons.date_range),
            onPressed: _elegirRango,
          ),
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _filas.isEmpty
                  ? const EstadoVacio(
                      icono: Icons.trending_up,
                      titulo: 'Sin proyectos',
                      subtitulo: 'Cuando existan proyectos con facturas o costos imputados aparecerán aquí.',
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _resumenGlobal(),
                          const SizedBox(height: 8),
                          for (final f in _filas) ...[
                            _tarjeta(f),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _resumenGlobal() {
    final ing = _filas.fold<double>(0, (a, f) => a + f.ingresos);
    final cos = _filas.fold<double>(0, (a, f) => a + f.costosImputados + f.manoObra);
    final margen = ing - cos;
    return Card(
      color: (margen >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _kpi('Ingresos', ing, Colors.teal),
            _kpi('Costos', cos, Colors.deepOrange),
            _kpi('Margen', margen, margen >= 0 ? Colors.green : Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _kpi(String titulo, double v, Color c) {
    return Expanded(
      child: Column(
        children: [
          Text(titulo, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(money(v),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta(RentabilidadProyecto f) {
    final c = f.margen >= 0 ? Colors.green : Colors.red;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: c.withValues(alpha: 0.15),
          child: Icon(f.margen >= 0 ? Icons.trending_up : Icons.trending_down,
              color: c, size: 20),
        ),
        title: Text(f.nombreProyecto,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          '${f.cliente}\n'
          'Ingresos ${money(f.ingresos)}  ·  Costos ${money(f.costosImputados + f.manoObra)}',
          style: const TextStyle(fontSize: 11),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(money(f.margen),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c)),
            if (f.margenPct != null)
              Text('${f.margenPct!.toStringAsFixed(1)} %',
                  style: TextStyle(fontSize: 11, color: c)),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _PantallaDetalleRentabilidad(
                proyectoId: f.proyectoId, svc: _svc!, rango: _rango),
          ),
        ),
      ),
    );
  }
}

class _PantallaDetalleRentabilidad extends StatefulWidget {
  final String proyectoId;
  final FinanzasService svc;
  final DateTimeRange? rango;
  const _PantallaDetalleRentabilidad(
      {required this.proyectoId, required this.svc, this.rango});

  @override
  State<_PantallaDetalleRentabilidad> createState() =>
      _PantallaDetalleRentabilidadState();
}

class _PantallaDetalleRentabilidadState
    extends State<_PantallaDetalleRentabilidad> {
  RentabilidadProyecto? _f;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String? _iso(DateTime? d) => d?.toIso8601String().substring(0, 10);

  Future<void> _cargar() async {
    final r = await widget.svc.rentabilidadProyecto(widget.proyectoId,
        desde: _iso(widget.rango?.start), hasta: _iso(widget.rango?.end));
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _f = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    return Scaffold(
      appBar: AppBar(
        title: Text(f?.nombreProyecto ?? 'Rentabilidad',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(f!.cliente,
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.grey)),
                        ),
                        chipEstado(f.estado, context.ez),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _fila('Ingresos facturados (sin IGV)', f.ingresos, Colors.teal),
                    _fila('Costos imputados', -f.costosImputados, Colors.deepOrange),
                    _fila(
                        'Mano de obra estimada (${f.horasManoObra.toStringAsFixed(1)} h)',
                        -f.manoObra,
                        Colors.purple),
                    const Divider(height: 24),
                    _fila('Margen', f.margen,
                        f.margen >= 0 ? Colors.green : Colors.red,
                        destacado: true),
                    if (f.margenPct != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Margen: ${f.margenPct!.toStringAsFixed(1)} % sobre ingresos',
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ),
                    if (f.centros.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text('COSTOS POR CENTRO',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      for (final c in f.centros)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.workspaces_outline, size: 18),
                          title: Text('${c.codigo} — ${c.nombre}',
                              style: const TextStyle(fontSize: 12.5)),
                          trailing: Text(money(c.costoReal),
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                    ],
                    if (f.empleados.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Text('MANO DE OBRA POR EMPLEADO',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      for (final e in f.empleados)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_outline, size: 18),
                          title: Text(e.nombre, style: const TextStyle(fontSize: 12.5)),
                          subtitle: Text('${e.horas.toStringAsFixed(1)} h',
                              style: const TextStyle(fontSize: 11)),
                          trailing: Text(money(e.costo),
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        'La mano de obra es estimada: horas de asistencia en el '
                        'proyecto × valor-hora del sueldo base (sueldo/240).',
                        style: TextStyle(fontSize: 10.5, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
    );
  }

  Widget _fila(String titulo, double v, Color c, {bool destacado = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo,
                style: TextStyle(
                    fontSize: destacado ? 14 : 12.5,
                    fontWeight: destacado ? FontWeight.w700 : FontWeight.w400)),
          ),
          Text(money(v),
              style: TextStyle(
                  fontSize: destacado ? 15 : 12.5,
                  fontWeight: FontWeight.w700,
                  color: c)),
        ],
      ),
    );
  }
}
