import 'package:flutter/material.dart';

import '../models/indicadores_models.dart';
import '../services/indicadores_service.dart';
import '../utils/api_provider.dart';

/// Indicadores de desempeño (Punto 3.4): resumen de empresa + ranking por
/// empleado (evaluaciones, puntualidad, vacaciones, score global).
class PantallaIndicadores extends StatefulWidget {
  const PantallaIndicadores({super.key});

  @override
  State<PantallaIndicadores> createState() => _PantallaIndicadoresState();
}

class _PantallaIndicadoresState extends State<PantallaIndicadores> {
  IndicadoresService? _svc;
  ResumenDesempeno? _resumen;
  List<IndicadorEmpleado> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getIndicadoresService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final res = await _svc!.resumen();
    final lst = await _svc!.desempeno();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok) _resumen = res.data;
      if (lst.ok) {
        _items = lst.data ?? [];
      } else {
        _error = lst.errorMessage;
      }
    });
  }

  Color _scoreColor(double? s) {
    if (s == null) return Colors.grey;
    if (s >= 80) return Colors.green;
    if (s >= 60) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indicadores de desempeño', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (_resumen != null) _tarjetasResumen(_resumen!),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('RANKING POR EMPLEADO',
                            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Sin datos de empleados.', style: TextStyle(color: Colors.black54)),
                        )
                      else
                        ..._items.asMap().entries.map((e) => _fila(e.key + 1, e.value)),
                    ],
                  ),
                ),
    );
  }

  Widget _tarjetasResumen(ResumenDesempeno r) {
    Widget card(String titulo, String valor, IconData icon, Color color) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 8),
                Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                Text(titulo, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
        );
    return Column(children: [
      Row(children: [
        card('Empleados', '${r.empleados}', Icons.groups_2_outlined, Colors.blueGrey),
        card('Prom. evaluación', r.promedioEvaluaciones?.toStringAsFixed(1) ?? '—', Icons.assessment_outlined, Colors.indigo),
      ]),
      Row(children: [
        card('Puntualidad', r.puntualidadPromedio != null ? '${r.puntualidadPromedio!.toStringAsFixed(0)}%' : '—', Icons.access_time, Colors.teal),
        card('Calif. cliente', r.calificacionCliente?.toStringAsFixed(1) ?? '—', Icons.star_outline, Colors.amber),
      ]),
    ]);
  }

  Widget _fila(int pos, IndicadorEmpleado i) {
    final color = _scoreColor(i.scoreGlobal);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(i.scoreGlobal?.toStringAsFixed(0) ?? '—',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        title: Text('$pos. ${i.empleadoNombre ?? i.empleadoId}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (i.cargo != null) Text(i.cargo!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            Wrap(spacing: 12, runSpacing: 2, children: [
              _metric('Eval', i.promedioEvaluaciones != null ? '${i.promedioEvaluaciones!.toStringAsFixed(1)}/10' : '—'),
              _metric('Puntualidad', i.puntualidadPct != null ? '${i.puntualidadPct!.toStringAsFixed(0)}%' : '—'),
              _metric('Asist.', '${i.asistenciaValidados}/${i.asistenciaTotal}'),
              _metric('Vac. disp.', i.vacacionesDisponible.toStringAsFixed(0)),
            ]),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _metric(String k, String v) => RichText(
        text: TextSpan(style: const TextStyle(fontSize: 12, color: Colors.black87), children: [
          TextSpan(text: '$k: ', style: const TextStyle(color: Colors.black45)),
          TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
