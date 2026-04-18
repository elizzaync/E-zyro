import 'package:flutter/material.dart';
import '../widgets/stat_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Saludo ──────────────────────────────────────────────────
            _buildGreeting(),
            const SizedBox(height: 24),

            // ── Tarjetas de estadísticas ─────────────────────────────────
            _buildStatsRow(),
            const SizedBox(height: 16),

            // ── Próxima actualización ───────────────────────────────────
            _buildNextUpdate(),
            const SizedBox(height: 28),

            // ── Acciones Rápidas ────────────────────────────────────────
            const Text(
              'Acciones Rápidas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            _buildQuickActions(context),
            const SizedBox(height: 28),

            // ── Notificaciones ──────────────────────────────────────────
            _buildNotificationsHeader(),
            const SizedBox(height: 12),
            _buildNotificationItem(
              title: 'Nuevo servicio asignado',
              subtitle: 'Hace 5 min',
            ),
            const SizedBox(height: 8),
            _buildNotificationItem(
              title: 'Materiales aprobados',
              subtitle: 'Hace 1 hora',
            ),
          ],
        ),
      ),
    );
  }

  // ── Widgets privados ──────────────────────────────────────────────────────

  Widget _buildGreeting() {
    // TODO: Reemplazar con el nombre real del usuario desde el estado/servicio
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Hola, Alex 👋',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 4),
        Text(
          'Bienvenido de nuevo',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    // TODO: Reemplazar los valores con datos reales desde el proveedor/bloc
    return Row(
      children: const [
        Expanded(
          child: StatCard(
            label: 'Activos',
            value: '–', // <-- coloca aquí tu variable
            iconData: Icons.access_time,
            color: Color(0xFFFFF3CD),
            iconColor: Color(0xFFF59E0B),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Pendientes',
            value: '–',
            iconData: Icons.build_outlined,
            color: Color(0xFFF3F3F3),
            iconColor: Colors.grey,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Completados',
            value: '–',
            iconData: Icons.check_circle_outline,
            color: Color(0xFFEFFAE0),
            iconColor: Color(0xFF8FD11B),
            isHighlighted: true,
          ),
        ),
      ],
    );
  }

  Widget _buildNextUpdate() {
    // TODO: Conectar con datos reales del próximo evento/servicio
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
        children: const [
          Text(
            'Actualización',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          SizedBox(height: 4),
          Text(
            'Mañana  •  08:00 AM', // <-- reemplazar con fecha real
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: [
        _QuickActionButton(
          label: 'Asistencia',
          icon: Icons.access_time,
          isActive: true,
          onTap: () {
            // TODO: Navegar o ejecutar lógica de Asistencia
          },
        ),
        _QuickActionButton(
          label: 'Calendario',
          icon: Icons.calendar_today_outlined,
          onTap: () {
            // TODO: Navegar a Calendario
          },
        ),
        _QuickActionButton(
          label: 'Operaciones',
          icon: Icons.build_outlined,
          onTap: () {
            // TODO: Navegar a Operaciones
          },
        ),
        _QuickActionButton(
          label: 'Evidencia',
          icon: Icons.camera_alt_outlined,
          onTap: () {
            // TODO: Abrir cámara o galería de evidencias
          },
        ),
      ],
    );
  }

  Widget _buildNotificationsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        Text(
          'Notificaciones',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Icon(Icons.notifications_none, color: Colors.grey),
      ],
    );
  }

  Widget _buildNotificationItem({
    required String title,
    required String subtitle,
  }) {
    // TODO: Reemplazar con lista dinámica de notificaciones
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón de Acción Rápida (privado, solo usado en HomeScreen)
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF8FD11B) : Colors.white,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.grey.shade700,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
