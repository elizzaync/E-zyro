import 'package:flutter/material.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Encabezado ──────────────────────────────────────────────
            const Text(
              'Más',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // ── Banner de usuario ────────────────────────────────────────
            _buildUserBanner(),
            const SizedBox(height: 24),

            // ── Sección Cuenta ───────────────────────────────────────────
            _buildSectionTitle('Cuenta'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              items: [
                _MenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Configuración',
                  onTap: () {
                    // TODO: Navegar a Configuración
                  },
                ),
                _MenuItem(
                  icon: Icons.notifications_outlined,
                  label: 'Notificaciones',
                  badge: '3', // TODO: badge dinámico
                  onTap: () {
                    // TODO: Navegar a Notificaciones
                  },
                ),
                _MenuItem(
                  icon: Icons.person_outline,
                  label: 'Mi Perfil',
                  onTap: () {
                    // TODO: Navegar a Mi Perfil
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Sección Recursos ─────────────────────────────────────────
            _buildSectionTitle('Recursos'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              items: [
                _MenuItem(
                  icon: Icons.description_outlined,
                  label: 'Documentación',
                  onTap: () {
                    // TODO: Abrir documentación
                  },
                ),
                _MenuItem(
                  icon: Icons.help_outline,
                  label: 'Centro de Ayuda',
                  onTap: () {
                    // TODO: Abrir centro de ayuda
                  },
                ),
                _MenuItem(
                  icon: Icons.security_outlined,
                  label: 'Privacidad y Seguridad',
                  onTap: () {
                    // TODO: Abrir política de privacidad
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Cerrar sesión ────────────────────────────────────────────
            _buildLogoutButton(context),
            const SizedBox(height: 28),

            // ── Footer ───────────────────────────────────────────────────
            const Center(
              child: Column(
                children: [
                  Text(
                    'E-System TIC',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Plataforma de Servicios de Campo',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildUserBanner() {
    // TODO: Reemplazar con datos reales del usuario autenticado
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF8FD11B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withOpacity(0.3),
            child: const Icon(Icons.person, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alex Rodriguez', // TODO: nombre real
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                'Técnico Senior', // TODO: cargo real
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildMenuGroup({required List<_MenuItem> items}) {
    return Container(
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
        children: List.generate(items.length, (i) {
          return Column(
            children: [
              items[i],
              if (i < items.length - 1)
                Divider(height: 1, indent: 52, color: Colors.grey.shade100),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Container(
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
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text(
          'Cerrar Sesión',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.red),
        onTap: () {
          // TODO: Ejecutar lógica de cierre de sesión (limpiar tokens, navegar a login)
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

// ─── Item de menú ─────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? badge;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade700, size: 22),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF8FD11B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: Colors.grey.shade400),
        ],
      ),
      onTap: onTap,
    );
  }
}
