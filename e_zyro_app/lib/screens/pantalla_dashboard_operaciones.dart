import 'package:flutter/material.dart';
import '../models/intervencion_models.dart';
import '../services/intervencion_service.dart';
import '../utils/api_provider.dart';

const _green = Color(0xFF8FD11B);
const _amber = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);

/// Dashboard de Operaciones del técnico. Réplica de las tarjetas KPI del
/// frontend Angular (`operaciones-cards`) consumiendo GET /operaciones/dashboard:
/// métricas (Pendientes / En Proceso / Completados / Para Hoy) y la lista de
/// servicios asignados con semáforo de prioridad (verde/amarillo/rojo).
class PantallaDashboardOperaciones extends StatefulWidget {
  const PantallaDashboardOperaciones({super.key});

  @override
  State<PantallaDashboardOperaciones> createState() =>
      _PantallaDashboardOperacionesState();
}

class _PantallaDashboardOperacionesState
    extends State<PantallaDashboardOperaciones> {
  IntervencionService? _svc;
  DashboardOperaciones? _data;
  bool _cargando = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getIntervencionService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = false;
    });
    final res = await _svc!.getDashboard();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (res.ok && res.data != null) {
        _data = res.data;
      } else {
        _error = true;
      }
    });
  }

  static Color _hex(String hex) {
    final h = hex.replaceFirst('#', '');
    return h.length == 6 ? Color(int.parse('FF$h', radix: 16)) : _green;
  }

  static Color _semaforo(String color) => switch (color) {
        'verde' => _green,
        'rojo' => _danger,
        _ => _amber,
      };

  static IconData _iconoMetrica(String id) => switch (id) {
        'pendientes' => Icons.schedule_outlined,
        'activos' => Icons.bolt_outlined,
        'hechos' => Icons.check_circle_outline,
        'hoy' => Icons.today_outlined,
        _ => Icons.insights_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard de Operaciones',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, size: 20),
            onPressed: _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : _error || _data == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('No se pudo cargar el dashboard',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      OutlinedButton(
                          onPressed: _cargar, child: const Text('Reintentar')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: _green,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      // ── Métricas (mismas 4 tarjetas que la web) ─────────────
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.1,
                        children: [
                          for (final m in _data!.metricas)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _hex(m.colorIcono)
                                    .withValues(alpha: m.resaltado ? 0.18 : 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _hex(m.colorIcono)
                                      .withValues(alpha: m.resaltado ? 0.6 : 0.25),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(_iconoMetrica(m.id),
                                      size: 26, color: _hex(m.colorIcono)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${m.valor}',
                                            style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800)),
                                        Text(m.titulo,
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('Mis servicios (${_data!.servicios.length})',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      if (_data!.servicios.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text('No tienes servicios asignados.',
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 13)),
                          ),
                        ),
                      for (final s in _data!.servicios)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                                color: Colors.grey.withValues(alpha: 0.2)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _semaforo(s.estadoColor),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(s.tipoServicio,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                      Text(s.cliente,
                                          style: TextStyle(
                                              fontSize: 11.5,
                                              color: Colors.grey.shade600)),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(Icons.place_outlined,
                                              size: 11,
                                              color: Colors.grey.shade500),
                                          const SizedBox(width: 2),
                                          Flexible(
                                            child: Text(s.ubicacion,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color:
                                                        Colors.grey.shade600),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(Icons.event_outlined,
                                              size: 11,
                                              color: Colors.grey.shade500),
                                          const SizedBox(width: 2),
                                          Text('${s.fechaStr} · ${s.horaStr}',
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color:
                                                      Colors.grey.shade600)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _semaforo(s.estadoColor)
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(s.estado,
                                          style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  _semaforo(s.estadoColor))),
                                    ),
                                    if (s.alerta) ...[
                                      const SizedBox(height: 4),
                                      const Icon(Icons.warning_amber_rounded,
                                          size: 16, color: _danger),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
