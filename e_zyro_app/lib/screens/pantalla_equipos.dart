import 'package:flutter/material.dart';
import '../models/mantenimiento_models.dart';
import '../services/mantenimiento_service.dart';
import '../utils/api_provider.dart';
import 'pantalla_checklist.dart';
import 'pantalla_historial_equipo.dart';

class EquiposTab extends StatefulWidget {
  final String proyectoId;

  const EquiposTab({super.key, required this.proyectoId});

  @override
  State<EquiposTab> createState() => _EquiposTabState();
}

class _EquiposTabState extends State<EquiposTab>
    with AutomaticKeepAliveClientMixin {
  List<EquipoItem> _equipos = [];
  bool _isLoading = true;
  MantenimientoService? _service;

  static const _green = Color(0xFF8FD11B);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getMantenimientoService();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data =
        await _service!.getEquiposProyecto(widget.proyectoId);
    if (!mounted) return;
    setState(() {
      _equipos = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(_green),
        ),
      );
    }

    if (_equipos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.precision_manufacturing_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Sin equipos en este proyecto',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        itemCount: _equipos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _EquipoCard(
          equipo: _equipos[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChecklistScreen(equipo: _equipos[i]),
            ),
          ),
          onHistorial: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PantallaHistorialEquipo(
                equipoId: _equipos[i].id,
                equipoNombre: _equipos[i].nombre,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Equipment card ───────────────────────────────────────────────────────────

class _EquipoCard extends StatelessWidget {
  final EquipoItem equipo;
  final VoidCallback onTap;
  final VoidCallback onHistorial;

  const _EquipoCard({
    required this.equipo,
    required this.onTap,
    required this.onHistorial,
  });

  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFF59E0B);

  Color get _estadoColor => switch (equipo.estado.toLowerCase()) {
        'completado' => _green,
        'en_proceso' => const Color(0xFF3B82F6),
        _ => _amber,
      };

  String get _estadoLabel => switch (equipo.estado.toLowerCase()) {
        'completado' => 'Completado',
        'en_proceso' => 'En Proceso',
        _ => 'Pendiente',
      };

  String get _tipoLabel => switch ((equipo.tipo ?? '').toLowerCase()) {
        'tablero' => 'Tablero Eléctrico',
        'ups' => 'UPS',
        'pozo_tierra' => 'Pozo a Tierra',
        'generador' => 'Generador',
        'transformador' => 'Transformador',
        String t when t.isNotEmpty => t[0].toUpperCase() + t.substring(1),
        _ => '',
      };

  IconData get _iconForTipo => switch ((equipo.tipo ?? '').toLowerCase()) {
        'tablero' => Icons.electrical_services_outlined,
        'ups' => Icons.battery_charging_full_outlined,
        'pozo_tierra' => Icons.settings_input_component_outlined,
        'generador' => Icons.energy_savings_leaf_outlined,
        'transformador' => Icons.transform_outlined,
        _ => Icons.precision_manufacturing_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(
                  color: _green.withValues(alpha: 0.30), width: 1.0)
              : null,
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.07),
                    blurRadius: 10,
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? _estadoColor.withValues(alpha: 0.15)
                        : _estadoColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconForTipo,
                    color: _estadoColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        equipo.nombre,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (equipo.tipo != null && equipo.tipo!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _tipoLabel,
                            style: TextStyle(
                                color: _estadoColor.withValues(alpha: 0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      if (equipo.descripcion != null &&
                          equipo.descripcion!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            equipo.descripcion!,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (equipo.ubicacion != null &&
                          equipo.ubicacion!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on_outlined,
                                  size: 11, color: Colors.grey),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  equipo.ubicacion!,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
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
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _estadoColor.withValues(alpha: 0.15)
                            : _estadoColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _estadoLabel,
                        style: TextStyle(
                          color: _estadoColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // HU-19: Botón historial
                    GestureDetector(
                      onTap: onHistorial,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.history_rounded,
                          color: Colors.grey.shade400,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // HU-18: Barra de progreso si hay porcentaje disponible
            if (equipo.progresoPorcentaje != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (equipo.progresoPorcentaje! / 100).clamp(0.0, 1.0),
                        backgroundColor: isDark
                            ? Colors.grey.shade800
                            : Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(_estadoColor),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${equipo.progresoPorcentaje!.round()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _estadoColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
