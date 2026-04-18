import 'package:flutter/material.dart';
import '../widgets/stat_card.dart';

class OperationsScreen extends StatefulWidget {
  const OperationsScreen({super.key});

  @override
  State<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends State<OperationsScreen> {
  // TODO: Reemplazar con un estado real (Provider / Bloc / Riverpod)
  String _selectedFilter = 'Todos';

  final List<String> _filters = [
    'Todos',
    'Pendiente',
    'Activos',
    'Completados',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Encabezado ───────────────────────────────────────────
                const Text(
                  'Operaciones',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Gestión de servicios',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),

                // ── Estadísticas ─────────────────────────────────────────
                Row(
                  children: const [
                    Expanded(
                      child: StatCard(
                        label: 'Pendientes',
                        value: '–',
                        iconData: Icons.access_time,
                        color: Color(0xFFF3F3F3),
                        iconColor: Colors.grey,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: 'Activos',
                        value: '–',
                        iconData: Icons.build_outlined,
                        color: Color(0xFFFFF3CD),
                        iconColor: Color(0xFFF59E0B),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: 'Hechos',
                        value: '–',
                        iconData: Icons.check_circle_outline,
                        color: Color(0xFFF3F3F3),
                        iconColor: Colors.grey,
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: StatCard(
                        label: 'Hoy',
                        value: '–',
                        iconData: Icons.calendar_today,
                        color: Color(0xFFEFFAE0),
                        iconColor: Color(0xFF8FD11B),
                        isHighlighted: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Filtros ──────────────────────────────────────────────
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _filters
                        .map(
                          (f) => _FilterChip(
                            label: f,
                            isSelected: _selectedFilter == f,
                            onTap: () => setState(() => _selectedFilter = f),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          // ── Lista de servicios ──────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: const [
                // TODO: Reemplazar con ListView.builder + datos reales
                _ServiceCard(
                  company: 'TechCorp Inc.',
                  serviceType: 'Reparación de Red',
                  location: 'Oficina Centro, Piso 12',
                  dateTime: 'Hoy  •  09:00 AM',
                  status: 'Activo',
                  hasAlert: true,
                ),
                SizedBox(height: 10),
                _ServiceCard(
                  company: 'Global Systems',
                  serviceType: 'Instalación de Servidor',
                  location: 'Parque Industrial, Edificio A',
                  dateTime: 'Hoy  •  02:00 PM',
                  status: 'Pendiente',
                ),
                SizedBox(height: 10),
                _ServiceCard(
                  company: 'DataFlow Ltd.',
                  serviceType: 'Mantenimiento',
                  location: 'Campus Principal',
                  dateTime: 'Ayer  •  10:00 AM',
                  status: 'Completado',
                ),
                SizedBox(height: 20),
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

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8FD11B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF8FD11B) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
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
  final String company;
  final String serviceType;
  final String location;
  final String dateTime;
  final String status;
  final bool hasAlert;

  const _ServiceCard({
    required this.company,
    required this.serviceType,
    required this.location,
    required this.dateTime,
    required this.status,
    this.hasAlert = false,
  });

  Color get _statusColor {
    switch (status) {
      case 'Activo':
        return const Color(0xFFFFF3CD);
      case 'Pendiente':
        return const Color(0xFFF3F3F3);
      case 'Completado':
        return const Color(0xFFEFFAE0);
      default:
        return const Color(0xFFF3F3F3);
    }
  }

  Color get _statusTextColor {
    switch (status) {
      case 'Activo':
        return const Color(0xFFF59E0B);
      case 'Pendiente':
        return Colors.grey;
      case 'Completado':
        return const Color(0xFF8FD11B);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Empresa + ícono de alerta
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                company,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              if (hasAlert)
                const Icon(Icons.error_outline, color: Colors.red, size: 20),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            serviceType,
            style: const TextStyle(color: Colors.black87, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                location,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateTime,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              // Badge de estado
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _statusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: _statusTextColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
