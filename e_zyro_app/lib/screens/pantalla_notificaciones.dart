import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../models/dashboard_models.dart';
import '../services/fcm_flutter_service.dart';
import '../services/notificacion_service.dart';
import '../utils/api_provider.dart';

class NotificacionesScreen extends StatefulWidget {
  final bool isSheet;
  final ScrollController? scrollController;

  const NotificacionesScreen({
    super.key,
    this.isSheet = false,
    this.scrollController,
  });

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}

class _NotificacionesScreenState extends State<NotificacionesScreen> {
  NotificacionService? _service;
  List<NotificacionItem> _items = [];
  bool _loading = true;
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen((_) => _load());
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getNotificacionService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    try {
      final items = await _service!.getAll();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('expirada')) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      setState(() => _loading = false);
    }
  }

  Future<void> _marcarLeida(NotificacionItem item) async {
    if (item.leido) return;
    try {
      await _service?.marcarLeida(item.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      final idx = _items.indexWhere((e) => e.id == item.id);
      if (idx != -1) _items[idx] = _items[idx].copyWith(leido: true);
    });
  }

  void _eliminar(NotificacionItem item) {
    setState(() => _items.removeWhere((e) => e.id == item.id));
    _service?.eliminar(item.id).catchError((_) {
      if (mounted) {
        setState(() => _items.insert(0, item));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo eliminar. Intenta de nuevo.'),
          ),
        );
      }
    });
  }

  Future<void> _marcarTodasLeidas() async {
    try {
      await _service?.marcarTodasLeidas();
      if (!mounted) return;
      setState(
        () => _items = _items.map((e) => e.copyWith(leido: true)).toList(),
      );
    } catch (_) {}
  }

  Future<void> _eliminarLeidas() async {
    final leidas = _items.where((e) => e.leido).length;
    if (leidas == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay notificaciones leídas para eliminar.'),
        ),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Eliminar leídas',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text('Se eliminarán $leidas notificaciones leídas.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _service?.eliminarLeidas();
      if (!mounted) return;
      setState(() => _items.removeWhere((e) => e.leido));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al eliminar. Intenta de nuevo.')),
        );
      }
    }
  }

  void _onTap(NotificacionItem item) {
    _marcarLeida(item);
    switch (item.tipo) {
      case 'servicio':
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/operations',
          (r) => r.isFirst,
        );
      case 'comunicado':
        Navigator.pushNamedAndRemoveUntil(context, '/more', (r) => r.isFirst);
      case 'recordatorio':
        Navigator.pushNamed(context, '/calendario');
      default:
        break;
    }
  }

  Map<String, List<NotificacionItem>> get _grupos {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    final groups = <String, List<NotificacionItem>>{
      'Hoy': [],
      'Ayer': [],
      'Esta semana': [],
      'Antes': [],
    };
    for (final item in _items) {
      final d = DateTime(
        item.createdAt.year,
        item.createdAt.month,
        item.createdAt.day,
      );
      if (d == today) {
        groups['Hoy']!.add(item);
      } else if (d == yesterday)
        groups['Ayer']!.add(item);
      else if (d.isAfter(weekAgo))
        groups['Esta semana']!.add(item);
      else
        groups['Antes']!.add(item);
    }
    groups.removeWhere((_, v) => v.isEmpty);
    return groups;
  }

  int get _unreadCount => _items.where((e) => !e.leido).length;

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return widget.isSheet ? _buildSheet(context) : _buildFullScreen(context);
  }

  // Pantalla completa (ruta /notificaciones)
  Widget _buildFullScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notificaciones',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (_unreadCount > 0)
              Text(
                '$_unreadCount sin leer',
                style: const TextStyle(fontSize: 12, color: Color(0xFF8FD11B)),
              ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: _buildActions(),
      ),
      body: _buildBody(),
    );
  }

  // Modal sheet (desde la campana del home)
  Widget _buildSheet(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Cabecera
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notificaciones',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (_unreadCount > 0)
                        Text(
                          '$_unreadCount sin leer',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8FD11B),
                          ),
                        ),
                    ],
                  ),
                ),
                ..._buildActions(),
              ],
            ),
          ),
          const Divider(height: 1),
          // Lista
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  List<Widget> _buildActions() => [
    if (_unreadCount > 0)
      IconButton(
        icon: const Icon(Icons.done_all_rounded),
        tooltip: 'Marcar todo leído',
        onPressed: _marcarTodasLeidas,
      ),
    IconButton(
      icon: const Icon(Icons.delete_sweep_outlined),
      tooltip: 'Eliminar leídas',
      onPressed: _eliminarLeidas,
    ),
  ];

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
        ),
      );
    }
    if (_items.isEmpty) return _buildEmpty();

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF8FD11B),
      child: ListView(
        controller: widget.scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          for (final entry in _grupos.entries) ...[
            _GroupHeader(label: entry.key),
            ...entry.value.map(
              (item) => _NotifTile(
                key: Key(item.id),
                item: item,
                onTap: () => _onTap(item),
                onDismiss: () => _eliminar(item),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 20),
          Text(
            'Todo al día',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No tienes notificaciones pendientes',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

// ── Cabecera de grupo ──────────────────────────────────────────────────────────
class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ── Tile de notificación ───────────────────────────────────────────────────────
class _NotifTile extends StatelessWidget {
  final NotificacionItem item;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotifTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismiss,
  });

  static IconData _iconForTipo(String tipo) => switch (tipo) {
    'servicio' => Icons.build_rounded,
    'comunicado' => Icons.campaign_rounded,
    'recordatorio' => Icons.event_note_rounded,
    _ => Icons.notifications_rounded,
  };

  static Color _colorForTipo(String tipo) => switch (tipo) {
    'servicio' => const Color(0xFF3B82F6),
    'comunicado' => const Color(0xFFF59E0B),
    'recordatorio' => const Color(0xFF8B5CF6),
    _ => const Color(0xFF8FD11B),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colorForTipo(item.tipo);
    final isUnread = !item.leido;
    final surface = Theme.of(context).colorScheme.surface;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: Colors.red.shade400,
        padding: const EdgeInsets.only(right: 24),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline_rounded, color: Colors.white, size: 26),
            SizedBox(height: 4),
            Text(
              'Eliminar',
              style: TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDismiss(),
      child: Material(
        color: isUnread ? color.withValues(alpha: 0.05) : surface,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 3,
                  color: isUnread ? color : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _iconForTipo(item.tipo),
                            color: color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.titulo,
                                      style: TextStyle(
                                        fontWeight: isUnread
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        fontSize: 14,
                                        color: isUnread
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onSurface
                                            : Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    item.tiempoRelativo,
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.mensaje,
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 8),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
