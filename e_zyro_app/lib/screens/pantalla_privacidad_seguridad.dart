import 'package:flutter/material.dart';
import 'pantalla_mis_sesiones.dart';
import 'pantalla_editar_perfil.dart';

class PantallaPrivacidadSeguridad extends StatelessWidget {
  const PantallaPrivacidadSeguridad({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Privacidad y Seguridad')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Acceso y sesiones ────────────────────────────────────────────
          _buildSectionTitle('Acceso y sesiones'),
          const SizedBox(height: 10),
          _buildGroup(surface: surface, isDark: isDark, items: [
            _Tile(
              icon: Icons.devices_other_outlined,
              label: 'Mis sesiones activas',
              subtitle: 'Ver y cerrar sesiones en otros dispositivos',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PantallaMisSesiones())),
            ),
            _Tile(
              icon: Icons.lock_outline,
              label: 'Cambiar contraseña',
              subtitle: 'Actualizar tu contraseña de acceso',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen())),
            ),
          ]),
          const SizedBox(height: 24),

          // ── Política de privacidad ────────────────────────────────────────
          _buildSectionTitle('Política de privacidad'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Protección de tus datos',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                SizedBox(height: 10),
                Text(
                  'E-System TIC protege tu información personal conforme a la '
                  'Ley N.º 29733 (Protección de Datos Personales) del Perú.\n\n'
                  'Tus datos (nombre, foto, ubicación GPS, registros de asistencia '
                  'y evidencias fotográficas) son usados exclusivamente para la '
                  'operación de los servicios de campo.\n\n'
                  'No compartimos tu información con terceros sin tu consentimiento '
                  'explícito, salvo requerimiento legal.',
                  style: TextStyle(fontSize: 13, height: 1.6, color: Colors.grey),
                ),
                SizedBox(height: 10),
                Text(
                  'Para ejercer tus derechos de acceso, rectificación o cancelación '
                  'de datos, contacta a: privacidad@esystemtic.com',
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Seguridad de la cuenta ────────────────────────────────────────
          _buildSectionTitle('Seguridad de la cuenta'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _SecurityRow(
                  icon: Icons.shield_outlined,
                  label: 'Cifrado de datos',
                  valor: 'TLS 1.3',
                  color: const Color(0xFF1E9462),
                ),
                const Divider(height: 20),
                _SecurityRow(
                  icon: Icons.key_outlined,
                  label: 'Autenticación',
                  valor: 'Token JWT',
                  color: const Color(0xFF1E9462),
                ),
                const Divider(height: 20),
                _SecurityRow(
                  icon: Icons.history_outlined,
                  label: 'Auditoría de accesos',
                  valor: 'Activa',
                  color: const Color(0xFF1E9462),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Text(
        title.toUpperCase(),
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey,
            letterSpacing: 0.8),
      );

  Widget _buildGroup({
    required Color surface,
    required bool isDark,
    required List<_Tile> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 56),
            items[i],
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, size: 22),
        title: Text(label,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: onTap,
      );
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({
    required this.icon,
    required this.label,
    required this.valor,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String valor;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13))),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(valor,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ),
        ],
      );
}
