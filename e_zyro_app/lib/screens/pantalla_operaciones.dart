import 'package:flutter/material.dart';
import '../widgets/stat_card.dart';

// ── Modelo de datos ───────────────────────────────────────────────────────────
class _ServiceItem {
  final String company;
  final String serviceType;
  final String location;
  final String dateTime;
  final String status;
  final String phone;
  final bool hasAlert;

  const _ServiceItem({
    required this.company,
    required this.serviceType,
    required this.location,
    required this.dateTime,
    required this.status,
    this.phone = '',
    this.hasAlert = false,
  });
}

const _allServices = [
  _ServiceItem(
    company: 'TechCorp Inc.',
    serviceType: 'Reparación de Red',
    location: 'Oficina Centro, Piso 12',
    dateTime: 'Hoy  •  09:00 AM',
    status: 'Activo',
    phone: '+51 999 111 222',
    hasAlert: true,
  ),
  _ServiceItem(
    company: 'Global Systems',
    serviceType: 'Instalación de Servidor',
    location: 'Parque Industrial, Edificio A',
    dateTime: 'Hoy  •  02:00 PM',
    status: 'Pendiente',
    phone: '+51 999 333 444',
  ),
  _ServiceItem(
    company: 'DataFlow Ltd.',
    serviceType: 'Mantenimiento Preventivo',
    location: 'Campus Principal, Sala TI',
    dateTime: 'Ayer  •  10:00 AM',
    status: 'Completado',
    phone: '+51 999 555 666',
  ),
  _ServiceItem(
    company: 'NetSolutions SAC',
    serviceType: 'Configuración de Firewall',
    location: 'Torre Norte, Piso 8',
    dateTime: 'Mañana  •  08:00 AM',
    status: 'Pendiente',
    phone: '+51 999 777 888',
  ),
];

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  String _selectedFilter = 'Todos';
  final List<String> _filters = ['Todos', 'Pendiente', 'Activo', 'Completado'];

  List<_ServiceItem> get _filtered {
    if (_selectedFilter == 'Todos') return _allServices;
    return _allServices.where((s) => s.status == _selectedFilter).toList();
  }

  void _openDetail(_ServiceItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServiceDetailSheet(item: item),
    );
  }

  void _showNewServiceDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewServiceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final pending = _allServices.where((s) => s.status == 'Pendiente').length;
    final active = _allServices.where((s) => s.status == 'Activo').length;
    final done = _allServices.where((s) => s.status == 'Completado').length;

    return SafeArea(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Encabezado ────────────────────────────────────────
                    const Text('Operaciones',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const Text('Gestión de servicios',
                        style: TextStyle(fontSize: 14, color: Colors.grey)),
                    const SizedBox(height: 20),

                    // ── Estadísticas ──────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            label: 'Pendientes',
                            value: '$pending',
                            iconData: Icons.access_time,
                            color: const Color(0xFFF3F3F3),
                            iconColor: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            label: 'Activos',
                            value: '$active',
                            iconData: Icons.build_outlined,
                            color: const Color(0xFFFFF3CD),
                            iconColor: const Color(0xFFF59E0B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            label: 'Hechos',
                            value: '$done',
                            iconData: Icons.check_circle_outline,
                            color: const Color(0xFFEFFAE0),
                            iconColor: const Color(0xFF8FD11B),
                            isHighlighted: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: StatCard(
                            label: 'Hoy',
                            value: '${_allServices.where((s) => s.dateTime.startsWith('Hoy')).length}',
                            iconData: Icons.calendar_today,
                            color: const Color(0xFFEFFAE0),
                            iconColor: const Color(0xFF8FD11B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Filtros ───────────────────────────────────────────
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _filters.map((f) => _FilterChip(
                          label: f,
                          isSelected: _selectedFilter == f,
                          onTap: () => setState(() => _selectedFilter = f),
                        )).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),

              // ── Lista ───────────────────────────────────────────────────
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined, size: 52, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'Sin servicios en "$_selectedFilter"',
                              style: const TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _ServiceCard(
                          item: filtered[i],
                          onTap: () => _openDetail(filtered[i]),
                        ),
                      ),
              ),
            ],
          ),

          // ── FAB ────────────────────────────────────────────────────────
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton.extended(
              onPressed: _showNewServiceDialog,
              backgroundColor: const Color(0xFF8FD11B),
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add),
              label: const Text('Nueva', style: TextStyle(fontWeight: FontWeight.w600)),
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

  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

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
            color: isSelected ? green : (isDark ? green.withValues(alpha: 0.35) : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface,
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
  final _ServiceItem item;
  final VoidCallback onTap;

  const _ServiceCard({required this.item, required this.onTap});

  Color get _statusColor => switch (item.status) {
        'Activo' => const Color(0xFFF59E0B),
        'Completado' => const Color(0xFF8FD11B),
        _ => Colors.grey,
      };

  Color get _statusBg => switch (item.status) {
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
          border: isDark ? Border.all(color: green.withValues(alpha: 0.45), width: 1.0) : null,
          boxShadow: isDark
              ? [BoxShadow(color: green.withValues(alpha: 0.10), blurRadius: 12, spreadRadius: 1)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.company,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.hasAlert)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(Icons.error_outline, color: Colors.red, size: 18),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? _statusColor.withValues(alpha: 0.15) : _statusBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        item.status,
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
              item.serviceType,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(item.location,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(item.dateTime, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: Detalle de servicio ────────────────────────────────────────
class _ServiceDetailSheet extends StatelessWidget {
  final _ServiceItem item;
  const _ServiceDetailSheet({required this.item});

  Color get _statusColor => switch (item.status) {
        'Activo' => const Color(0xFFF59E0B),
        'Completado' => const Color(0xFF8FD11B),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    final isActive = item.status == 'Activo';
    final isPending = item.status == 'Pendiente';

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
                      Text(item.company,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 3),
                      Text(item.serviceType,
                          style: const TextStyle(color: Colors.grey, fontSize: 14)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: isDark ? 0.15 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    item.status,
                    style: TextStyle(color: _statusColor, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Detalles
            _DetailRow(Icons.location_on_outlined, 'Ubicación', item.location),
            _DetailRow(Icons.schedule_outlined, 'Fecha y hora', item.dateTime),
            if (item.phone.isNotEmpty)
              _DetailRow(Icons.phone_outlined, 'Contacto', item.phone),
            if (item.hasAlert) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Text('Requiere atención urgente',
                        style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Acciones
            Row(
              children: [
                if (item.phone.isNotEmpty) ...[
                  Expanded(
                    child: _ActionBtn(
                      icon: Icons.phone_outlined,
                      label: 'Llamar',
                      color: Colors.blue,
                      onTap: () => _snack(context, 'Llamando a ${item.company}...'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.map_outlined,
                    label: 'Ver mapa',
                    color: Colors.orange,
                    onTap: () => _snack(context, 'Abriendo mapa...'),
                  ),
                ),
                if (isActive || isPending) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionBtn(
                      icon: isPending ? Icons.play_arrow_rounded : Icons.check_circle_outlined,
                      label: isPending ? 'Iniciar' : 'Completar',
                      color: isPending ? const Color(0xFFF59E0B) : green,
                      onTap: () {
                        Navigator.pop(context);
                        _snack(context, isPending ? 'Servicio iniciado' : 'Servicio completado');
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: Nueva operación ───────────────────────────────────────────
class _NewServiceSheet extends StatelessWidget {
  const _NewServiceSheet();

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
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? green.withValues(alpha: 0.12) : const Color(0xFFEFFAE0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.add_task, color: green, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nueva Operación',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Registro de nuevo servicio',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? green.withValues(alpha: 0.06) : const Color(0xFFF9FDF0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: green.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF8FD11B), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'El registro de nuevas operaciones estará disponible en la próxima versión con integración al sistema central.',
                      style: TextStyle(fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Entendido', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
