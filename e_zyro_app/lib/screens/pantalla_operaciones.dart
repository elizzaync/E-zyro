import 'package:flutter/material.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';
import '../widgets/stat_card.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  ProyectoService? _service;
  List<ProyectoServicio> _proyectos = [];
  bool _isLoading = true;
  String _selectedFilter = 'Todos';
  final List<String> _filters = ['Todos', 'Pendiente', 'Activo', 'Completado'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getProyectoService();
    await _loadData();
  }

  Future<void> _loadData() async {
    if (_service == null) return;
    setState(() => _isLoading = true);
    final data = await _service!.getMisServicios();
    if (!mounted) return;
    setState(() {
      _proyectos = data;
      _isLoading = false;
    });
  }

  List<ProyectoServicio> get _filtered => _selectedFilter == 'Todos'
      ? _proyectos
      : _proyectos.where((p) => p.estado == _selectedFilter).toList();

  int _count(String estado) =>
      _proyectos.where((p) => p.estado == estado).length;

  void _openDetail(ProyectoServicio item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServiceDetailSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Encabezado ─────────────────────────────────────────
                const Text(
                  'Mis Proyectos',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Servicios asignados',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),

                // ── Estadísticas ────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        label: 'Pendientes',
                        value: '${_count("Pendiente")}',
                        iconData: Icons.access_time,
                        color: const Color(0xFFF3F3F3),
                        iconColor: Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: 'Activos',
                        value: '${_count("Activo")}',
                        iconData: Icons.build_outlined,
                        color: const Color(0xFFFFF3CD),
                        iconColor: const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: 'Hechos',
                        value: '${_count("Completado")}',
                        iconData: Icons.check_circle_outline,
                        color: const Color(0xFFEFFAE0),
                        iconColor: const Color(0xFF8FD11B),
                        isHighlighted: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Filtros ─────────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filters
                        .map((f) => _FilterChip(
                              label: f,
                              isSelected: _selectedFilter == f,
                              onTap: () =>
                                  setState(() => _selectedFilter = f),
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          // ── Lista ──────────────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.work_outline,
                              size: 56,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _proyectos.isEmpty
                                  ? 'No tienes servicios asignados'
                                  : 'Sin servicios en "$_selectedFilter"',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 14),
                            ),
                            if (_proyectos.isEmpty) ...[
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _loadData,
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFF8FD11B)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                child: const Text(
                                  'Actualizar',
                                  style:
                                      TextStyle(color: Color(0xFF8FD11B)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: const Color(0xFF8FD11B),
                        child: ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ServiceCard(
                            item: filtered[i],
                            onTap: () => _openDetail(filtered[i]),
                          ),
                        ),
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
      {required this.label,
      required this.isSelected,
      required this.onTap});

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

// ─── Tarjeta de servicio ──────────────────────────────────────────────────────
class _ServiceCard extends StatelessWidget {
  final ProyectoServicio item;
  final VoidCallback onTap;

  const _ServiceCard({required this.item, required this.onTap});

  Color get _statusColor => switch (item.estado) {
        'Activo' => const Color(0xFFF59E0B),
        'Completado' => const Color(0xFF8FD11B),
        _ => Colors.grey,
      };

  Color get _statusBg => switch (item.estado) {
        'Activo' => const Color(0xFFFFF3CD),
        'Completado' => const Color(0xFFEFFAE0),
        _ => const Color(0xFFF3F3F3),
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
                  color: green.withValues(alpha: 0.45), width: 1.0)
              : null,
          boxShadow: isDark
              ? [
                  BoxShadow(
                      color: green.withValues(alpha: 0.10),
                      blurRadius: 12,
                      spreadRadius: 1)
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.empresa,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.urgente)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _statusColor.withValues(alpha: 0.15)
                            : _statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.estado,
                        style: TextStyle(
                          color: _statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.tipoServicio,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(item.ubicacion,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            if (item.fechaFin != null || item.fechaInicio != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    item.fechaFin != null
                        ? 'Hasta ${item.fechaFin}'
                        : 'Desde ${item.fechaInicio}',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right,
                      color: Colors.grey, size: 18),
                ],
              ),
            ] else ...[
              const SizedBox(height: 4),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: Detalle de proyecto ───────────────────────────────────────
class _ServiceDetailSheet extends StatelessWidget {
  final ProyectoServicio item;
  const _ServiceDetailSheet({required this.item});

  Color get _statusColor => switch (item.estado) {
        'Activo' => const Color(0xFFF59E0B),
        'Completado' => const Color(0xFF8FD11B),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.empresa,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(item.tipoServicio,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 14)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor
                        .withValues(alpha: isDark ? 0.15 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    item.estado,
                    style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Detalles
            _DetailRow(Icons.location_on_outlined, 'Ubicación',
                item.ubicacion),
            if (item.supervisor != null && item.supervisor!.isNotEmpty)
              _DetailRow(Icons.person_outline, 'Supervisor / Jefe',
                  item.supervisor!),
            if (item.fechaInicio != null)
              _DetailRow(Icons.play_arrow_outlined, 'Inicio',
                  item.fechaInicio!),
            if (item.fechaFin != null)
              _DetailRow(Icons.flag_outlined, 'Plazo', item.fechaFin!),
            if (item.telefono != null && item.telefono!.isNotEmpty)
              _DetailRow(Icons.phone_outlined, 'Contacto', item.telefono!),
            if (item.urgente) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Text('Requiere atención urgente',
                        style: TextStyle(
                            color: Colors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Acción
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Entendido',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF8FD11B).withValues(alpha: 0.12)
                  : const Color(0xFFEFFAE0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF8FD11B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
