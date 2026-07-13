import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_notifiers.dart';
import 'pantalla_preferencias_notificacion.dart';

class PantallaConfiguracion extends StatelessWidget {
  const PantallaConfiguracion({super.key});

  Future<void> _limpiarCache(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar caché'),
        content: const Text(
            'Se eliminarán los datos temporales en caché. '
            'Tus registros y evidencias offline no se perderán.\n\n'
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Limpiar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmar != true || !context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    // Limpia caché de selección de cámara, filtros, etc. — preserva auth y offline queue.
    final cacheKeys = prefs.getKeys().where((k) =>
        k.startsWith('campo_last_') ||
        k.startsWith('cache_') ||
        k.startsWith('filtro_'));
    for (final k in cacheKeys) {
      await prefs.remove(k);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Caché limpiada correctamente'),
            backgroundColor: Color(0xFF1E9462)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    BoxDecoration groupDeco = BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.05),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Apariencia ─────────────────────────────────────────────────
          _sectionTitle('Apariencia'),
          const SizedBox(height: 10),
          Container(
            decoration: groupDeco,
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (_, mode, _) => SwitchListTile(
                secondary: Icon(
                  mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  size: 22,
                ),
                title: const Text('Modo Oscuro',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                subtitle: Text(
                  mode == ThemeMode.dark ? 'Activado' : 'Desactivado',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                value: mode == ThemeMode.dark,
                activeThumbColor: const Color(0xFF8FD11B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                onChanged: (val) async {
                  themeNotifier.value =
                      val ? ThemeMode.dark : ThemeMode.light;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('dark_mode', val);
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Notificaciones ──────────────────────────────────────────────
          _sectionTitle('Notificaciones'),
          const SizedBox(height: 10),
          Container(
            decoration: groupDeco,
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined, size: 22),
              title: const Text('Preferencias de notificación',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text('Configura qué alertas deseas recibir',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing:
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const PreferenciasNotificacionScreen()),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Almacenamiento ──────────────────────────────────────────────
          _sectionTitle('Almacenamiento'),
          const SizedBox(height: 10),
          Container(
            decoration: groupDeco,
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_outlined, size: 22),
              title: const Text('Limpiar caché',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text(
                  'Elimina datos temporales sin borrar tus registros',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing:
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onTap: () => _limpiarCache(context),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t.toUpperCase(),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
            letterSpacing: 0.8),
      );
}
