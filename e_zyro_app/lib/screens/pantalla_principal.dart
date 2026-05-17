import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dashboard_service.dart';
import '../services/fcm_flutter_service.dart';
import '../models/dashboard_models.dart';
import '../widgets/stat_card.dart';
import '../utils/app_notifiers.dart';
import '../utils/api_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DashboardService? _dashboardService;
  bool _isLoading = true;
  bool _hasError = false;

  String _userName = '';
  DashboardResumen _resumen = const DashboardResumen(
    activos: 0,
    pendientes: 0,
    completados: 0,
  );
  List<ProximoServicio> _servicios = [];
  List<NotificacionDashboard> _notificaciones = [];

  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_name') ?? 'Usuario';
    _dashboardService = await getDashboardService();
    await _loadData();
  }

  Future<void> _loadData() async {
    if (_dashboardService == null) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      late DashboardResumen resumen;
      late List<ProximoServicio> servicios;
      late List<NotificacionDashboard> notifs;

      await Future.wait([
        _dashboardService!.getResumen().then((v) => resumen = v),
        _dashboardService!.getProximosServicios().then((v) => servicios = v),
        _dashboardService!.getNotificaciones().then((v) => notifs = v),
      ]);

      if (!mounted) return;
      setState(() {
        _resumen = resumen;
        _servicios = servicios;
        _notificaciones = notifs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('Sesión expirada')) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: Colors.grey),
            const SizedBox(height: 14),
            const Text(
              'Error al cargar los datos',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8FD11B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFF8FD11B),
      child: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Saludo ─────────────────────────────────────────────────
              _buildGreeting(),
              const SizedBox(height: 24),

              // ── KPIs ───────────────────────────────────────────────────
              _buildStatsRow(),
              const SizedBox(height: 20),

              // ── Próximos Servicios ──────────────────────────────────────
              _buildProximosServicios(),
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
              ..._buildNotificationsList(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Saludo ──────────────────────────────────────────────────────────────────
  String get _firstName {
    final parts = _userName.trim().split(' ');
    return parts.isNotEmpty ? parts.first : 'Usuario';
  }

  Widget _buildGreeting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hola, $_firstName 👋',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Bienvenido de nuevo',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ],
    );
  }

  // ── KPIs ────────────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Activos',
            value: '${_resumen.activos}',
            iconData: Icons.access_time,
            color: const Color(0xFFFFF3CD),
            iconColor: const Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Pendientes',
            value: '${_resumen.pendientes}',
            iconData: Icons.build_outlined,
            color: const Color(0xFFF3F3F3),
            iconColor: Colors.grey,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatCard(
            label: 'Completados',
            value: '${_resumen.completados}',
            iconData: Icons.check_circle_outline,
            color: const Color(0xFFEFFAE0),
            iconColor: const Color(0xFF8FD11B),
            isHighlighted: true,
          ),
        ),
      ],
    );
  }

  // ── Helper: decoración adaptativa con efecto neon en modo oscuro ───────────
  BoxDecoration _neonDecoration({double radius = 14}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: isDark
          ? Border.all(color: green.withValues(alpha: 0.55), width: 1.0)
          : null,
      boxShadow: isDark
          ? [
              BoxShadow(
                color: green.withValues(alpha: 0.14),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  // ── Próximos Servicios ──────────────────────────────────────────────────────
  Widget _buildProximosServicios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Próximos Servicios',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (_servicios.isEmpty)
          _buildEmptyCard('Sin servicios próximos programados')
        else
          ..._servicios.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildServicioCard(s),
            ),
          ),
      ],
    );
  }

  Widget _buildServicioCard(ProximoServicio s) {
    final Color estadoColor = switch (s.estado) {
      'Activo' => const Color(0xFF8FD11B),
      'Pendiente' => const Color(0xFFF59E0B),
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _neonDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.tipo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.fecha}  •  ${s.hora}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: estadoColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              s.estado,
              style: TextStyle(
                color: estadoColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: _neonDecoration(),
      child: Text(
        mensaje,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }

  // ── Acciones Rápidas ────────────────────────────────────────────────────────
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
          onTap: () => Navigator.pushNamed(context, '/asistencia'),
        ),
        _QuickActionButton(
          label: 'Calendario',
          icon: Icons.calendar_today_outlined,
          onTap: () => Navigator.pushNamed(context, '/calendario'),
        ),
        _QuickActionButton(
          label: 'Operaciones',
          icon: Icons.build_outlined,
          onTap: () => tabNotifier.value = 1,
        ),
        _QuickActionButton(
          label: 'Evidencia',
          icon: Icons.camera_alt_outlined,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Evidencia disponible próximamente'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Notificaciones ──────────────────────────────────────────────────────────
  void _abrirNotificaciones() {
    Navigator.pushNamed(context, '/notificaciones').then((_) => _loadData());
  }

  Widget _buildNotificationsHeader() {
    final count = _notificaciones.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Notificaciones',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        GestureDetector(
          onTap: _abrirNotificaciones,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                color: Colors.grey,
                size: 26,
              ),
              if (count > 0)
                Positioned(
                  top: -5,
                  right: -5,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildNotificationsList() {
    if (_notificaciones.isEmpty) {
      return [
        GestureDetector(
          onTap: _abrirNotificaciones,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: _neonDecoration(radius: 12),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded,
                    color: Colors.grey.shade400, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Sin notificaciones recientes',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final preview = _notificaciones.take(3).toList();
    final hasMore = _notificaciones.length > 3;

    return [
      ...preview.map(
        (n) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildNotificationItem(n),
        ),
      ),
      if (hasMore)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: GestureDetector(
            onTap: _abrirNotificaciones,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Ver todas las notificaciones',
                  style: TextStyle(
                    color: Color(0xFF8FD11B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF8FD11B), size: 12),
              ],
            ),
          ),
        )
      else if (_notificaciones.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: GestureDetector(
            onTap: _abrirNotificaciones,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Gestionar notificaciones',
                  style: TextStyle(
                    color: Color(0xFF8FD11B),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded,
                    color: Color(0xFF8FD11B), size: 12),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _buildNotificationItem(NotificacionDashboard n) {
    final (color, icon) = switch (n.tipo) {
      'servicio'     => (const Color(0xFF3B82F6), Icons.build_rounded),
      'comunicado'   => (const Color(0xFFF59E0B), Icons.campaign_rounded),
      'recordatorio' => (const Color(0xFF8B5CF6), Icons.event_note_rounded),
      _              => (const Color(0xFF8FD11B), Icons.notifications_rounded),
    };

    return GestureDetector(
      onTap: _abrirNotificaciones,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: _neonDecoration(radius: 12),
        child: Row(
          children: [
            // Icono circular con color por tipo
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            // Texto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.tiempo,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Punto no leído (en home todas son no leídas)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Botón de Acción Rápida ───────────────────────────────────────────────────
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
      child: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final surface = Theme.of(context).colorScheme.surface;
          const green = Color(0xFF8FD11B);
          return Container(
            decoration: BoxDecoration(
              color: isActive ? green : surface,
              borderRadius: BorderRadius.circular(14),
              border: (!isActive && isDark)
                  ? Border.all(color: green.withValues(alpha: 0.45), width: 1.0)
                  : null,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: green.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ]
                  : isDark
                  ? [
                      BoxShadow(
                        color: green.withValues(alpha: 0.10),
                        blurRadius: 8,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
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
          );
        },
      ),
    );
  }
}
