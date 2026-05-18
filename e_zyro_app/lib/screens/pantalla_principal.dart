import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dashboard_service.dart';
import '../services/notificacion_service.dart';
import '../services/fcm_flutter_service.dart';
import '../models/dashboard_models.dart';
import '../widgets/stat_card.dart';
import '../widgets/topo_background.dart';
import '../utils/app_notifiers.dart';
import '../utils/api_provider.dart';
import 'pantalla_notificaciones.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DashboardService? _dashboardService;
  NotificacionService? _notificacionService;
  bool _isLoading = true;
  bool _hasError = false;

  String _userName = '';
  DashboardResumen _resumen = const DashboardResumen(
    activos: 0,
    pendientes: 0,
    completados: 0,
  );
  List<ProximoServicio> _servicios = [];
  int _unreadCount = 0;

  // Banner
  bool _bannerVisible = false;
  String _bannerTitle = '';
  String _bannerBody = '';
  String _bannerTipo = '';
  Timer? _bannerTimer;

  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen(_silentRefresh);
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('user_name') ?? 'Usuario';
    _dashboardService = await getDashboardService();
    _notificacionService = await getNotificacionService();
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
      int unread = 0;

      await Future.wait([
        _dashboardService!.getResumen().then((v) => resumen = v),
        _dashboardService!.getProximosServicios().then((v) => servicios = v),
        if (_notificacionService != null)
          _notificacionService!.getUnreadCount().then((v) => unread = v),
      ]);

      if (!mounted) return;
      setState(() {
        _resumen = resumen;
        _servicios = servicios;
        _unreadCount = unread;
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

  Future<void> _refreshUnreadCount() async {
    if (_notificacionService == null || !mounted) return;
    try {
      final count = await _notificacionService!.getUnreadCount();
      if (!mounted) return;
      setState(() => _unreadCount = count);
    } catch (_) {}
  }

  Future<void> _silentRefresh(RemoteMessage msg) async {
    await _refreshUnreadCount();
    if (!mounted) return;

    final title = msg.notification?.title ??
        msg.data['titulo'] as String? ??
        'Nueva notificación';
    final body = msg.notification?.body ?? msg.data['mensaje'] as String? ?? '';
    final tipo = msg.data['tipo'] as String? ?? '';

    _bannerTimer?.cancel();
    setState(() {
      _bannerTitle = title;
      _bannerBody = body;
      _bannerTipo = tipo;
      _bannerVisible = true;
    });
    _bannerTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _bannerVisible = false);
    });
  }

  void _openNotificacionesSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, controller) => NotificacionesScreen(
          isSheet: true,
          scrollController: controller,
        ),
      ),
    ).then((_) => _refreshUnreadCount());
  }

  // ── Banner de notificación ─────────────────────────────────────────────────

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

  Widget _buildBanner() {
    final color = _colorForTipo(_bannerTipo);
    return AnimatedSlide(
      offset: _bannerVisible ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _bannerVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: SafeArea(
          child: GestureDetector(
            onTap: () {
              _bannerTimer?.cancel();
              setState(() => _bannerVisible = false);
              _openNotificacionesSheet();
            },
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.18),
                    blurRadius: 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(_iconForTipo(_bannerTipo), color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _bannerTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_bannerBody.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            _bannerBody,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      _bannerTimer?.cancel();
                      setState(() => _bannerVisible = false);
                    },
                    child: Icon(Icons.close_rounded,
                        color: Colors.grey.shade400, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TopoBackground(
      c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
      c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
      base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
      count: 20,
      amp: 12,
      stroke: 0.45,
      speed: 0.6,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
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

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          color: const Color(0xFF8FD11B),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGreeting(),
                  const SizedBox(height: 24),
                  _buildStatsRow(),
                  const SizedBox(height: 20),
                  _buildProximosServicios(),
                  const SizedBox(height: 28),
                  const Text(
                    'Acciones Rápidas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  _buildQuickActions(context),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildBanner(),
        ),
      ],
    );
  }

  // ── Saludo ──────────────────────────────────────────────────────────────────
  String get _firstName {
    final parts = _userName.trim().split(' ');
    return parts.isNotEmpty ? parts.first : 'Usuario';
  }

  Widget _buildGreeting() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola, $_firstName 👋',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Bienvenido de nuevo',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _openNotificacionesSheet,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.notifications_none_rounded,
                    size: 24, color: Colors.grey),
              ),
              if (_unreadCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
