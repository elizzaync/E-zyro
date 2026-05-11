import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_notifiers.dart';
import 'pantalla_comunicados.dart';
import 'pantalla_editar_perfil.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _userName = '';
  String _userRol = '';
  String _fotoUrl = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Usuario';
        _userRol = prefs.getString('user_rol') ?? '';
        _fotoUrl = prefs.getString('user_foto_url') ?? '';
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_name');
    await prefs.remove('user_rol');
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  void _showInfoDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Título ─────────────────────────────────────────────────
            const Text(
              'Más',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // ── Banner de usuario ───────────────────────────────────────
            _buildUserBanner(),
            const SizedBox(height: 24),

            // ── Apariencia ─────────────────────────────────────────────
            _buildSectionTitle('Apariencia'),
            const SizedBox(height: 10),
            _buildCard(
              surface: surface,
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (_, mode, _) => SwitchListTile(
                  secondary: Icon(
                    mode == ThemeMode.dark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    size: 22,
                  ),
                  title: const Text(
                    'Modo Oscuro',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  value: mode == ThemeMode.dark,
                  activeThumbColor: const Color(0xFF8FD11B),
                  onChanged: (val) async {
                    themeNotifier.value =
                        val ? ThemeMode.dark : ThemeMode.light;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('dark_mode', val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Cuenta ─────────────────────────────────────────────────
            _buildSectionTitle('Cuenta'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              surface: surface,
              items: [
                _MenuItem(
                  icon: Icons.person_outline,
                  label: 'Mi Perfil',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.campaign_outlined,
                  label: 'Comunicados',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ComunicadosScreen()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Configuración',
                  onTap: () => _showInfoDialog(
                    'Configuración',
                    'Las opciones de configuración avanzada estarán disponibles próximamente.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Recursos ───────────────────────────────────────────────
            _buildSectionTitle('Recursos'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              surface: surface,
              items: [
                _MenuItem(
                  icon: Icons.description_outlined,
                  label: 'Documentación',
                  onTap: () => _showInfoDialog(
                    'Documentación',
                    'Accede a manuales y guías de operación en el portal web de E-System TIC.',
                  ),
                ),
                _MenuItem(
                  icon: Icons.help_outline,
                  label: 'Centro de Ayuda',
                  onTap: () => _showInfoDialog(
                    'Centro de Ayuda',
                    'Para soporte técnico contáctanos:\nsoporte@esystemtic.com',
                  ),
                ),
                _MenuItem(
                  icon: Icons.security_outlined,
                  label: 'Privacidad y Seguridad',
                  onTap: () => _showInfoDialog(
                    'Privacidad y Seguridad',
                    'Tu información está protegida. Los datos son cifrados y almacenados de forma segura conforme a nuestra política de privacidad.',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Cerrar sesión ───────────────────────────────────────────
            _buildCard(
              surface: surface,
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.red),
                onTap: _handleLogout,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Footer ─────────────────────────────────────────────────
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
                  SizedBox(height: 2),
                  Text(
                    'Plataforma de Servicios de Campo',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  SizedBox(height: 2),
                  Text('v1.0.0', style: TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ── Widgets privados ────────────────────────────────────────────────────────

  Widget _buildUserBanner() {
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
            backgroundColor: Colors.white.withValues(alpha: 0.3),
            backgroundImage: _fotoUrl.isNotEmpty ? NetworkImage(_fotoUrl) : null,
            child: _fotoUrl.isEmpty
                ? const Icon(Icons.person, color: Colors.white, size: 28)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (_userRol.isNotEmpty)
                  Text(
                    _userRol,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildCard({required Color surface, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildMenuGroup({
    required Color surface,
    required List<_MenuItem> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
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
                const Divider(height: 1, indent: 52),
            ],
          );
        }),
      ),
    );
  }
}

// ── Item de menú ──────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        size: 22,
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
