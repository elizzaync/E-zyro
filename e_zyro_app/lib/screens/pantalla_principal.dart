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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header card flotante ──────────────────────────────
                  _buildHeaderCard(),
                  // ── Contenido ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProximosServicios(),
                        const SizedBox(height: 28),
                        const Text(
                          'Acciones Rápidas',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
                        _buildQuickActions(context),
                        const SizedBox(height: 28),
                        _buildResumenMes(),
                      ],
                    ),
                  ),
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

  // ── Header card (superficie con esquinas redondeadas abajo) ────────────────
  Widget _buildHeaderCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGreeting(),
          const SizedBox(height: 18),
          _buildStatsRow(),
        ],
      ),
    );
  }

  // ── Saludo ──────────────────────────────────────────────────────────────────
  String get _firstName {
    final parts = _userName.trim().split(' ');
    return parts.isNotEmpty ? parts.first : 'Usuario';
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 18) return 'Buenas tardes';
    return 'Buenas noches';
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
                '$_greeting, $_firstName 👋',
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 3),
              Text(
                _subtitleDate(),
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: _openNotificacionesSheet,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  _unreadCount > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  size: 24,
                  color: _unreadCount > 0
                      ? const Color(0xFF8FD11B)
                      : Colors.grey,
                ),
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

  String _subtitleDate() {
    const months = [
      'enero','febrero','marzo','abril','mayo','junio',
      'julio','agosto','septiembre','octubre','noviembre','diciembre',
    ];
    const days = ['lunes','martes','miércoles','jueves','viernes','sábado','domingo'];
    final now = DateTime.now();
    final dayName = days[now.weekday - 1];
    final monthName = months[now.month - 1];
    return '${dayName[0].toUpperCase()}${dayName.substring(1)}, ${now.day} de $monthName';
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
    final bool isActivo = s.estado.toLowerCase() == 'activo';
    final Color estadoColor = isActivo
        ? const Color(0xFFF59E0B)   // amber — en proceso
        : s.estado.toLowerCase() == 'pendiente'
            ? Colors.grey
            : const Color(0xFF8FD11B);
    final Color estadoBg = isActivo
        ? const Color(0xFFFFF3CD)
        : s.estado.toLowerCase() == 'pendiente'
            ? const Color(0xFFF3F3F3)
            : const Color(0xFFEFFAE0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _neonDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.empresa.isNotEmpty)
                      Text(
                        s.empresa,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (s.empresa.isNotEmpty) const SizedBox(height: 2),
                    Text(
                      s.tipo,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: s.empresa.isNotEmpty ? 12 : 14,
                        fontWeight: s.empresa.isNotEmpty
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: estadoBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  s.estado,
                  style: TextStyle(
                    color: estadoColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.schedule_outlined, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                '${s.fecha}  ·  ${s.hora}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Resumen del Mes ─────────────────────────────────────────────────────────
  Widget _buildResumenMes() {
    final total =
        _resumen.activos + _resumen.pendientes + _resumen.completados;
    if (total == 0) return const SizedBox.shrink();

    final tasaExito =
        total > 0 ? (_resumen.completados / total * 100).round() : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen del Mes',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: _neonDecoration(radius: 16),
          child: Column(
            children: [
              _buildResumenRow(
                  'Completados', _resumen.completados, total,
                  const Color(0xFF8FD11B)),
              const SizedBox(height: 10),
              _buildResumenRow(
                  'En proceso', _resumen.activos, total,
                  const Color(0xFFF59E0B)),
              const SizedBox(height: 10),
              _buildResumenRow(
                  'Pendientes', _resumen.pendientes, total, Colors.grey),
              const Divider(height: 22),
              Row(
                children: [
                  _buildResumenStat(
                      '$tasaExito%', 'Tasa éxito',
                      const Color(0xFF8FD11B)),
                  _buildResumenStat('$total', 'Total', null),
                  _buildResumenStat(
                      '${_resumen.asistenciasMes}', 'Asistencias',
                      const Color(0xFF3B82F6)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResumenRow(
      String label, int value, int total, Color color) {
    final pct = total > 0 ? value / total : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style:
                  const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  Widget _buildResumenStat(
      String value, String label, Color? color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style:
                const TextStyle(fontSize: 10, color: Colors.grey),
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

  // ── Acciones Rápidas (estilo Figma: 1 verde + 2 blancos) ───────────────────
  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        // ── Primario: Asistencia (verde sólido) ────────────────────────
        Expanded(
          child: _FigmaQuickAction(
            label: 'Asistencia',
            icon: Icons.fingerprint_rounded,
            isPrimary: true,
            onTap: () => Navigator.pushNamed(context, '/asistencia'),
          ),
        ),
        const SizedBox(width: 10),
        // ── Secundario: Calendario ─────────────────────────────────────
        Expanded(
          child: _FigmaQuickAction(
            label: 'Calendario',
            icon: Icons.calendar_month_rounded,
            isPrimary: false,
            onTap: () => Navigator.pushNamed(context, '/calendario'),
          ),
        ),
        const SizedBox(width: 10),
        // ── Secundario: Operaciones ────────────────────────────────────
        Expanded(
          child: _FigmaQuickAction(
            label: 'Operaciones',
            icon: Icons.build_rounded,
            isPrimary: false,
            onTap: () => tabNotifier.value = 1,
          ),
        ),
      ],
    );
  }
}

// ─── Botón de Acción Rápida — estilo Figma ────────────────────────────────────
class _FigmaQuickAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _FigmaQuickAction({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_FigmaQuickAction> createState() => _FigmaQuickActionState();
}

class _FigmaQuickActionState extends State<_FigmaQuickAction>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.0,
      upperBound: 0.06,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.93).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: widget.isPrimary ? green : surface,
            borderRadius: BorderRadius.circular(16),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: isDark
                        ? green.withValues(alpha: 0.25)
                        : Colors.grey.shade200,
                    width: 1.2,
                  ),
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: green.withValues(alpha: 0.42),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDark ? 0.12 : 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 28,
                color: widget.isPrimary
                    ? Colors.white
                    : (isDark ? green : const Color(0xFF4A8E00)),
              ),
              const SizedBox(height: 7),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: widget.isPrimary
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
