import 'package:flutter/material.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import 'pantalla_detalle_servicio.dart';
import 'pantalla_equipos.dart';
import 'pantalla_gantt.dart';

class ServiciosScreen extends StatefulWidget {
  final ProyectoItem proyecto;
  final ProyectoService service;

  const ServiciosScreen({
    super.key,
    required this.proyecto,
    required this.service,
  });

  @override
  State<ServiciosScreen> createState() => _ServiciosScreenState();
}

class _ServiciosScreenState extends State<ServiciosScreen>
    with SingleTickerProviderStateMixin {
  List<ServicioItem> _servicios = [];
  bool _isLoading = true;
  late TabController _tabController;

  static const _green = Color(0xFF8FD11B);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final data =
        await widget.service.getServiciosProyecto(widget.proyecto.id);
    if (!mounted) return;
    setState(() {
      _servicios = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final proyecto = widget.proyecto;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          proyecto.ordenTrabajo.isNotEmpty
              ? proyecto.ordenTrabajo
              : proyecto.nombreProyecto,
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          Tooltip(
            message: 'Diagrama de Gantt',
            child: IconButton(
              icon: const Icon(Icons.view_timeline_outlined),
              color: _green,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GanttScreen(
                    proyecto: proyecto,
                    service: widget.service,
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: _green,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _green,
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: [
            Tab(text: 'Servicios (${_servicios.length})'),
            const Tab(text: 'Equipos'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header del proyecto ──────────────────────────────────────────
          _ProyectoHeader(proyecto: proyecto),

          // ── Tabs ─────────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // ── Tab Servicios ──────────────────────────────────────────
                _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(_green),
                        ),
                      )
                    : _servicios.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.build_outlined,
                                    size: 48,
                                    color: Colors.grey.shade400),
                                const SizedBox(height: 12),
                                const Text(
                                    'Sin servicios en este proyecto',
                                    style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 14)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: _green,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 8, 20, 24),
                              itemCount: _servicios.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _ServicioCard(
                                servicio: _servicios[i],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetalleServicioScreen(
                                      servicioId: _servicios[i].id,
                                      proyectoId: widget.proyecto.id,
                                      nombreServicio:
                                          _servicios[i].nombre,
                                      service: widget.service,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                // ── Tab Equipos ────────────────────────────────────────────
                EquiposTab(proyectoId: proyecto.id),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header con datos del proyecto ───────────────────────────────────────────

class _ProyectoHeader extends StatelessWidget {
  final ProyectoItem proyecto;
  const _ProyectoHeader({required this.proyecto});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF8FD11B);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(color: green.withValues(alpha: 0.30))
            : null,
        boxShadow: isDark
            ? null
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
          Text(
            proyecto.nombreProyecto,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.business_outlined,
                  size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Expanded(
                child: Text(proyecto.cliente,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 13, color: Colors.grey),
              const SizedBox(width: 5),
              Expanded(
                child: Text(proyecto.jefeNombre,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${proyecto.serviciosCompletados}/${proyecto.totalServicios} completados',
                style:
                    const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const Spacer(),
              Text(
                '${(proyecto.progreso * 100).round()}%',
                style: TextStyle(
                  color: proyecto.progreso >= 1
                      ? green
                      : const Color(0xFFF59E0B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: proyecto.progreso,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                proyecto.progreso >= 1 ? green : const Color(0xFFF59E0B),
              ),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tarjeta de servicio ──────────────────────────────────────────────────────

class _ServicioCard extends StatelessWidget {
  final ServicioItem servicio;
  final VoidCallback onTap;

  const _ServicioCard({required this.servicio, required this.onTap});

  Color get _dotColor => switch (servicio.estadoColor) {
        'verde' => const Color(0xFF8FD11B),
        'rojo' => Colors.red,
        _ => const Color(0xFFF59E0B),
      };

  Color get _statusColor => switch (servicio.estado) {
        'Completado' => const Color(0xFF8FD11B),
        'En_Proceso' => const Color(0xFF3B82F6),
        'Cancelado' => Colors.red,
        _ => const Color(0xFFF59E0B),
      };

  String get _estadoLabel => switch (servicio.estado) {
        'En_Proceso' => 'En Proceso',
        _ => servicio.estado,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark
              ? Border.all(
                  color: green.withValues(alpha: 0.35), width: 1.0)
              : null,
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: green.withValues(alpha: 0.08),
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
        child: Row(
          children: [
            // ── Número de orden ──────────────────────────────────────────
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark
                    ? _dotColor.withValues(alpha: 0.15)
                    : _dotColor.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${servicio.orden}',
                  style: TextStyle(
                    color: _dotColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // ── Nombre y fecha ───────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    servicio.nombre,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  if (servicio.descripcion != null &&
                      servicio.descripcion!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      servicio.descripcion!,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (servicio.fechaProgramada != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 11, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          servicio.fechaProgramada!,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ── Estado + chevron ─────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? _statusColor.withValues(alpha: 0.15)
                        : _statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _estadoLabel,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
