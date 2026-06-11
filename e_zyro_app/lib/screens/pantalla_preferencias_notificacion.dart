import 'package:flutter/material.dart';
import '../services/notificacion_service.dart';
import '../utils/api_provider.dart';

class PreferenciasNotificacionScreen extends StatefulWidget {
  const PreferenciasNotificacionScreen({super.key});

  @override
  State<PreferenciasNotificacionScreen> createState() =>
      _PreferenciasNotificacionScreenState();
}

class _PreferenciasNotificacionScreenState
    extends State<PreferenciasNotificacionScreen> {
  NotificacionService? _service;
  List<PreferenciaNotif> _items = [];
  bool _loading = true;
  bool _saving = false;

  // Iconos y descripción por categoría.
  static const _meta = <String, (IconData, String)>{
    'general':     (Icons.notifications_rounded,   'Avisos generales del sistema'),
    'almuerzo':    (Icons.restaurant_rounded,      'Inicio y fin de tu descanso'),
    'alertas':     (Icons.warning_amber_rounded,   'Vencimientos, mantenimiento y asistencia'),
    'comunicados': (Icons.campaign_rounded,        'Comunicados de la empresa y proyectos'),
    'servicios':   (Icons.build_rounded,           'Asignaciones y cambios de servicios'),
    'chat':        (Icons.chat_bubble_rounded,     'Mensajes del chat en vivo de tus servicios'),
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getNotificacionService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    try {
      final items = await _service!.getPreferencias();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(PreferenciaNotif p, bool value) async {
    setState(() {
      p.activo = value;
      _saving = true;
    });
    try {
      await _service?.guardarPreferencias({p.categoria: value});
    } catch (_) {
      if (mounted) {
        setState(() => p.activo = !value); // revertir
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF8FD11B);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                  child: Text(
                    'Elige qué notificaciones quieres recibir en tu dispositivo.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ..._items.map(_buildTile),
              ],
            ),
    );
  }

  Widget _buildTile(PreferenciaNotif p) {
    final accent = const Color(0xFF8FD11B);
    final meta = _meta[p.categoria] ?? (Icons.notifications_rounded, '');
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        value: p.activo,
        activeThumbColor: accent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(meta.$1, color: accent, size: 20),
        ),
        title: Text(
          p.etiqueta,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          meta.$2,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        onChanged: (v) => _toggle(p, v),
      ),
    );
  }
}
