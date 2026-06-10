import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../models/proyecto_models.dart';
import '../services/fcm_flutter_service.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_notifiers.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';
import 'pantalla_servicios.dart';
import 'pantalla_crear_proyecto.dart';
import 'pantalla_dashboard_operaciones.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  ProyectoService? _service;
  ProyectosConKpis? _data;
  bool _isLoading = true;
  String _selectedFilter = 'Todos';
  final List<String> _filters = ['Todos', 'Pendiente', 'En Proceso', 'Completado'];

  StreamSubscription<RemoteMessage>? _fcmSub;
  DateTime? _lastLoad;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen(_onFcmMessage);
    syncCompletedNotifier.addListener(_onSyncCompleted);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    syncCompletedNotifier.removeListener(_onSyncCompleted);
    super.dispose();
  }

  void _onFcmMessage(RemoteMessage msg) {
    final tipo = msg.data['tipo'] as String? ?? '';
    if (tipo == 'asignacion_proyecto' ||
        tipo == 'asignacion_servicio' ||
        tipo == 'servicio') {
      _throttledLoad();
    }
  }

  void _onSyncCompleted() => _throttledLoad();

  void _throttledLoad() {
    if (!mounted) return;
    final ahora = DateTime.now();
    if (_lastLoad != null &&
        ahora.difference(_lastLoad!) < const Duration(seconds: 30)) {
      return;
    }
    _lastLoad = ahora;
    _loadData();
  }

  Future<void> _init() async {
    _service = await getProyectoService();
    await _loadData();
  }

  Future<void> _loadData() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getProyectos();
    if (!mounted) return;
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  List<ProyectoItem> get _filtered {
    final list = _data?.proyectos ?? [];
    if (_selectedFilter == 'Todos') return list;
    return list.where((p) => p.estado == _selectedFilter).toList();
  }

  bool get _puedeCrear =>
      AppSession.i.isJefeOperaciones || AppSession.i.isAdmin;

  Future<void> _nuevoProyecto() async {
    if (_service == null) return;
    final creado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PantallaCrearProyecto(service: _service!, mode: 'crear'),
      ),
    );
    if (creado == true) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final kpis = _data?.kpis;
    final filtered = _filtered;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TopoBackground(
      c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
      c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
      base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
      count: 18,
      amp: 10,
      stroke: 0.40,
      speed: 0.5,
      child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Operaciones',
                            style: TextStyle(
                                fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            kpis != null
                                ? '${kpis.totalProyectos} proyectos asignados'
                                : 'Cargando...',
                            style: const TextStyle(
                                fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dashboard de operaciones',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const PantallaDashboardOperaciones()),
                      ),
                      icon: const Icon(Icons.insights_outlined, size: 22),
                    ),
                    if (_puedeCrear)
                      ElevatedButton.icon(
                        onPressed: _nuevoProyecto,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8FD11B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Nuevo',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── KPI Cards 2x2 ──────────────────────────────────────────
                if (kpis != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'Proyectos\nAsignados',
                          value: '${kpis.totalProyectos}',
                          icon: Icons.work_outline,
                          iconColor: const Color(0xFF6366F1),
                          bgColor: const Color(0xFFEEF2FF),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _KpiCard(
                          label: 'Servicios\nCompletados',
                          value: '${kpis.serviciosCompletados}',
                          icon: Icons.check_circle_outline,
                          iconColor: const Color(0xFF8FD11B),
                          bgColor: const Color(0xFFEFFAE0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'Servicios\nPendientes',
                          value: '${kpis.serviciosPendientes}',
                          icon: Icons.schedule_outlined,
                          iconColor: const Color(0xFFF59E0B),
                          bgColor: const Color(0xFFFFF8E1),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _KpiCard(
                          label: 'Tasa de\nAvance',
                          value: '${kpis.tasaAvance}%',
                          icon: Icons.bar_chart_outlined,
                          iconColor: const Color(0xFF8B5CF6),
                          bgColor: const Color(0xFFF3E8FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Filtros ────────────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filters
                        .map((f) => _FilterChip(
                              label: f,
                              isSelected: _selectedFilter == f,
                              onTap: () => setState(() => _selectedFilter = f),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          // ── Lista de proyectos ─────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
                    ),
                  )
                : filtered.isEmpty
                    ? _EmptyState(
                        hasData: (_data?.proyectos ?? []).isNotEmpty,
                        filter: _selectedFilter,
                        onRefresh: _loadData,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: const Color(0xFF8FD11B),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) => _ProyectoCard(
                            proyecto: filtered[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ServiciosScreen(
                                  proyecto: filtered[i],
                                  service: _service!,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    ));
  }
}

// ─── KPI Card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark
            ? Border.all(
                color: const Color(0xFF8FD11B).withValues(alpha: 0.25))
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? iconColor.withValues(alpha: 0.15) : bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chip de filtro ───────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? green : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? green
                : (isDark
                    ? green.withValues(alpha: 0.35)
                    : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Tarjeta de proyecto ──────────────────────────────────────────────────────

class _ProyectoCard extends StatelessWidget {
  final ProyectoItem proyecto;
  final VoidCallback onTap;

  const _ProyectoCard({required this.proyecto, required this.onTap});

  Color get _statusColor => switch (proyecto.estado) {
        'En Proceso' => const Color(0xFF3B82F6),
        'Completado' => const Color(0xFF8FD11B),
        'Cancelado' => Colors.red,
        _ => const Color(0xFFF59E0B),
      };

  Color get _statusBg => switch (proyecto.estado) {
        'En Proceso' => const Color(0xFFEFF6FF),
        'Completado' => const Color(0xFFEFFAE0),
        'Cancelado' => const Color(0xFFFFEBEB),
        _ => const Color(0xFFFFF8E1),
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
              ? Border.all(color: green.withValues(alpha: 0.35), width: 1.0)
              : null,
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: green.withValues(alpha: 0.08),
                    blurRadius: 12,
                    spreadRadius: 1,
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
            // ── OT + estado ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  proyecto.ordenTrabajo.isNotEmpty
                      ? proyecto.ordenTrabajo
                      : 'Sin OT',
                  style: const TextStyle(
                    fontSize: 11,
                    color: green,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.4,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? _statusColor.withValues(alpha: 0.15)
                        : _statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    proyecto.estado,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Nombre del proyecto ────────────────────────────────────────
            Text(
              proyecto.nombreProyecto,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),

            // ── Cliente ────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.business_outlined,
                    size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    proyecto.cliente,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),

            // ── Jefe ───────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.person_outline,
                    size: 13, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    proyecto.jefeNombre,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Progreso de servicios ──────────────────────────────────────
            Row(
              children: [
                Text(
                  '${proyecto.serviciosCompletados} de ${proyecto.totalServicios} servicio${proyecto.totalServicios != 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
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
                backgroundColor: isDark
                    ? Colors.grey.shade800
                    : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  proyecto.progreso >= 1 ? green : const Color(0xFFF59E0B),
                ),
                minHeight: 5,
              ),
            ),

            // ── Fecha ──────────────────────────────────────────────────────
            if (proyecto.fechaInicio != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 12, color: Colors.grey),
                  const SizedBox(width: 5),
                  Text(
                    proyecto.fechaInicio!,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  const Spacer(),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ver servicios',
                        style: TextStyle(
                          color: green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(Icons.chevron_right, color: green, size: 14),
                    ],
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Ver servicios',
                    style: TextStyle(
                      color: green,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right, color: green, size: 14),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Estado vacío ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasData;
  final String filter;
  final VoidCallback onRefresh;

  const _EmptyState(
      {required this.hasData,
      required this.filter,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.work_outline, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            hasData
                ? 'Sin proyectos en "$filter"'
                : 'No tienes proyectos asignados',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          if (!hasData) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRefresh,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF8FD11B)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Actualizar',
                  style: TextStyle(color: Color(0xFF8FD11B))),
            ),
          ],
        ],
      ),
    );
  }
}
