import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api_client.dart';
import 'core/connectivity_service.dart';
import 'repositories/asistencia_local_repo.dart';
import 'services/asistencia_service.dart';
import 'services/auth_service.dart';
import 'services/proyecto_service.dart';
import 'utils/app_notifiers.dart';
import 'utils/app_session.dart';
import 'widgets/chatbot/chatbot_launcher.dart';
import 'widgets/offline_overlay.dart';
import 'screens/pantalla_splash.dart';
import 'screens/pantalla_principal.dart';
import 'screens/pantalla_operaciones.dart';
import 'screens/pantalla_logistica.dart';
import 'screens/pantalla_perfil.dart';
import 'screens/pantalla_mas.dart';
import 'screens/pantalla_login.dart';
import 'screens/pantalla_recuperacion_password.dart';
import 'screens/pantalla_asistencia.dart';
import 'screens/pantalla_calendario.dart';
import 'screens/pantalla_notificaciones.dart';
import 'services/notification_service.dart';
import 'services/fcm_flutter_service.dart';
import 'screens/pantalla_historial_equipo.dart';
import 'screens/pantalla_auditoria.dart';
import 'portal/pantalla_portal_shell.dart';
import 'theme/ez_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App 100% vertical: se bloquea aquí una sola vez para toda la vida de la
  // app (antes alguna pantalla la desbloqueaba en su dispose() y rompía el
  // layout del resto si el usuario giraba el dispositivo).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Solo lo imprescindible para el primer frame: tema (evita parpadeo) y, en
  // paralelo, formatos de fecha + conectividad. Firebase y notificaciones se
  // difieren tras el primer frame (el splash da >1.4s antes de usarlos) para no
  // bloquear el arranque.
  final prefs = await SharedPreferences.getInstance();
  themeNotifier.value =
      (prefs.getBool('dark_mode') ?? false) ? ThemeMode.dark : ThemeMode.light;

  await Future.wait([
    initializeDateFormatting('es_ES', null),
    ConnectivityService.instance.initialize(),
  ]);

  runApp(const ESystemApp());

  // ── Inicialización diferida (no bloquea el primer frame) ──────────────────
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    // Firebase: solo mobile soporta FCM. En web/Windows se inicializa sin handler.
    try {
      await Firebase.initializeApp();
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Firebase] Init error: ${e.runtimeType}');
    }
    try {
      await NotificationService.initialize();
    } catch (e) {
      if (kDebugMode) debugPrint('[Notifications] Init error: ${e.runtimeType}');
    }
  });
}

// Temas pre-construidos una sola vez al cargar el módulo — Sistema de Diseño
// E-Zyro v1.0 (ver lib/theme/ez_theme.dart). Reemplaza los 9 sistemas previos
// (Verdant, Style E, Paper, Portal claro/oscuro, Ficha Colaborador, Mi
// Espacio, _C Trámites, Finanzas suelto).
final _lightTheme = buildEzTheme(ezLight);
final _darkTheme  = buildEzTheme(ezDark);

class ESystemApp extends StatelessWidget {
  const ESystemApp({super.key});

  /// NavigatorKey global — lo usa FcmFlutterService para navegar al tocar push.
  static final navigatorKey = GlobalKey<NavigatorState>();

  Map<String, WidgetBuilder> _routes() => {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/recovery': (context) => const PasswordRecoveryScreen(),
        '/': (context) => const MainShell(),
        // Portal (cliente externo): única desviación permitida del sistema —
        // brand -> brandExternal (#16A34A) — el resto (accent, estados,
        // superficie, tipografía) es idéntico al tema interno.
        '/portal': (context) => Theme(
              data: buildEzTheme(
                (Theme.of(context).brightness == Brightness.dark ? ezDark : ezLight)
                    .external,
              ),
              child: const PortalShell(),
            ),
        '/home': (context) => const MainShell(initialIndex: 0),
        '/operations': (context) => const MainShell(initialIndex: 1),
        '/logistics': (context) => const MainShell(initialIndex: 2),
        '/personal': (context) => const MainShell(initialIndex: 3),
        '/more': (context) => const MainShell(initialIndex: 4),
        '/calendario': (context) => const CalendarioScreen(),
        '/notificaciones': (context) => const NotificacionesScreen(),
        '/asistencia': (context) => Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: const Text('Asistencia',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                elevation: 0,
                backgroundColor: Colors.transparent,
              ),
              body: const AsistenciaScreen(),
            ),
        '/auditoria': (_) => const PantallaAuditoria(),
        '/historial-equipo': (context) {
          final args = ModalRoute.of(context)?.settings.arguments
              as Map<String, String>?;
          return PantallaHistorialEquipo(
            equipoId: args?['equipoId'] ?? '',
            equipoNombre: args?['equipoNombre'] ?? 'Equipo',
          );
        },
      };

  MaterialApp _materialApp({
    required ThemeData theme,
    ThemeData? darkTheme,
    required ThemeMode themeMode,
    TransitionBuilder? builder,
  }) {
    return MaterialApp(
      title: 'E-System TIC',
      debugShowCheckedModeBanner: false,
      navigatorKey: ESystemApp.navigatorKey,
      themeMode: themeMode,
      theme: theme,
      darkTheme: darkTheme,
      themeAnimationDuration: Duration.zero,
      builder: builder,
      initialRoute: '/splash',
      routes: _routes(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, _) => _materialApp(
        theme: _lightTheme,
        darkTheme: _darkTheme,
        themeMode: mode,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late int _currentIndex;
  // Lazy-load de pestañas: una tab se construye solo la primera vez que se
  // visita y luego queda viva (mantiene estado). Evita que el IndexedStack monte
  // las 5 pantallas (y dispare sus cargas de red) en el arranque en frío.
  late final List<bool> _activated;
  Timer? _syncTimer;
  bool _puedeLogistica = false;
  bool _puedePersonal = false;

  // Transición al cambiar de pestaña: el IndexedStack conmuta instantáneo
  // (por diseño, para preservar estado y no repintar tabs ocultas), así que
  // el fundido+deslizamiento se anima aquí por fuera, en el contenedor.
  late final AnimationController _tabTransCtrl;

  // Índice fijo de la pantalla de logística en _screens. Se mantiene en la
  // lista aunque el usuario no tenga permiso para no descuadrar otros
  // tabNotifier.value que se pasan entre módulos.
  static const _logisticaScreenIdx = 2;
  static const _personalScreenIdx = 3;

  // Nombre de cada tab para el contexto `pantalla` del asistente E-Zybot.
  static const _nombresTab = [
    'inicio', 'operaciones', 'logistica', 'personal', 'mas',
  ];

  // Inicio (0) y Operaciones (1) funcionan offline con datos cacheados.
  // El resto aún requiere red → OfflineOverlay los bloquea automáticamente.
  static const List<Widget> _screens = [
    HomeScreen(),
    OperationsScreen(),
    OfflineOverlay(child: LogisticsScreen()),
    OfflineOverlay(child: PersonalScreen()),
    OfflineOverlay(child: MoreScreen()),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _activated = List<bool>.filled(_screens.length, false);
    _activated[_currentIndex] = true;
    _tabTransCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..value = 1;
    WidgetsBinding.instance.addObserver(this);
    tabNotifier.addListener(_onTabChanged);
    isOnlineNotifier.addListener(_onConnectivityChanged);
    sessionExpiredSyncNotifier.addListener(_onSessionExpiredDuringSync);
    permissionsRefreshNotifier.addListener(_cargarPermisos);

    _cargarPermisos();

    // ── Sync al arrancar: si hay pendientes acumulados, enviarlos de inmediato
    WidgetsBinding.instance.addPostFrameCallback((_) => _triggerSync());

    // ── Sync periódico cada 5 min mientras la app esté abierta
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (isOnlineNotifier.value) _triggerSync();
    });
  }

  /// Carga los permisos relevantes para el bottom nav. Si el usuario inició en
  /// una pestaña a la que ya no tiene acceso (p. ej. Logística), regresa al
  /// Inicio para no dejarlo viendo una pantalla vacía.
  Future<void> _cargarPermisos() async {
    await AppSession.load();
    if (!mounted) return;
    // Cuentas del Portal Cliente nunca ven el shell interno: cualquier vía de
    // entrada a '/' (atajos offline, deep links, push) se redirige al portal.
    if (AppSession.i.esClienteExterno) {
      Navigator.pushNamedAndRemoveUntil(context, '/portal', (r) => false);
      return;
    }
    final canLog = AppSession.i.canGestInventario;
    final canPer = AppSession.i.canVerPersonal;
    setState(() {
      _puedeLogistica = canLog;
      _puedePersonal = canPer;
    });
    if (!canLog && _currentIndex == _logisticaScreenIdx) {
      tabNotifier.value = 0;
    }
    if (!canPer && _currentIndex == _personalScreenIdx) {
      tabNotifier.value = 0;
    }
  }

  /// Al volver del segundo plano, recarga rol+permisos desde el servidor: cubre
  /// los cambios de privilegios hechos mientras la app estaba minimizada (red de
  /// seguridad además del push 'perfil_actualizado').
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isOnlineNotifier.value) {
      _refrescarSesionYNav();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tabNotifier.removeListener(_onTabChanged);
    isOnlineNotifier.removeListener(_onConnectivityChanged);
    sessionExpiredSyncNotifier.removeListener(_onSessionExpiredDuringSync);
    permissionsRefreshNotifier.removeListener(_cargarPermisos);
    _syncTimer?.cancel();
    _tabTransCtrl.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    final target = tabNotifier.value;
    if (_currentIndex != target) {
      setState(() {
        _currentIndex = target;
        _activated[target] = true; // monta la tab la primera vez que se abre
      });
      _tabTransCtrl
        ..reset()
        ..forward();
    }
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    if (isOnlineNotifier.value) {
      _triggerSync();
      _refreshTokenSilencioso();
      _refrescarSesionYNav();
    }
  }

  /// Al recuperar conexión, recarga rol+permisos desde el servidor y refresca el
  /// bottom nav (p. ej. aparece/desaparece Logística si cambió el rol en BD).
  Future<void> _refrescarSesionYNav() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final auth  = AuthService(ApiClient(prefs), prefs);
      final ok = await auth.refrescarSesion();
      if (ok && mounted) await _cargarPermisos();
    } catch (_) {}
  }

  // Throttle del refresh para no renovar en cada parpadeo de conexión.
  static DateTime? _ultimoRefresh;

  /// Renueva el token al recuperar conexión (extiende la ventana de 7 días)
  /// si el JWT sigue vigente. Silencioso: si falla, el manejo de 401 ya cubre
  /// la expiración real.
  Future<void> _refreshTokenSilencioso() async {
    final ahora = DateTime.now();
    if (_ultimoRefresh != null &&
        ahora.difference(_ultimoRefresh!) < const Duration(minutes: 30)) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final auth  = AuthService(ApiClient(prefs), prefs);
      if (!auth.isStoredTokenValid()) return; // expirado → no hay qué renovar
      await auth.refreshToken();
      _ultimoRefresh = ahora;
    } catch (_) {
      // Sin red o sesión revocada: se ignora; el flujo de 401 lo gestiona.
    }
  }

  /// Se dispara cuando el sync detectó un 401 — la sesión del usuario venció
  /// mientras había registros locales pendientes de enviar.
  Future<void> _onSessionExpiredDuringSync() async {
    if (!mounted) return;

    // Contar cuántos registros quedaron pendientes para mostrarlo al usuario
    int pendientes = 0;
    try {
      pendientes = await AsistenciaLocalRepo().contarPendientes();
    } catch (_) {}

    // Notificación local (visible aunque la app esté en segundo plano)
    try {
      await NotificationService.show(
        id:    99,
        title: 'Sesión expirada',
        body:  pendientes > 0
            ? 'Tienes $pendientes ${pendientes == 1 ? "asistencia pendiente" : "asistencias pendientes"} de enviar. Inicia sesión para sincronizar.'
            : 'Tu sesión venció. Vuelve a iniciar sesión.',
      );
    } catch (_) {}

    // SnackBar en pantalla con botón de acción directo
    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pendientes > 0
                      ? 'Sesión expirada · $pendientes ${pendientes == 1 ? "registro pendiente" : "registros pendientes"}'
                      : 'Sesión expirada. Inicia sesión nuevamente.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label:     'Iniciar sesión',
            textColor: const Color(0xFF8FD11B),
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
          ),
          backgroundColor: Colors.purple.shade800,
          behavior:        SnackBarBehavior.floating,
          duration:        const Duration(seconds: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _triggerSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final asis  = AsistenciaService(ApiClient(prefs));
      final proy  = ProyectoService(ApiClient(prefs));
      // Solo sincronizar si hay pendientes (asistencia o evidencias) Y el
      // servidor Railway es alcanzable. Un solo probe canReachServer() para
      // ambas colas (HTTP crudo sin token → no falla con 401).
      final pendAsis = await asis.contarPendientes();
      final pendEvid = await proy.contarEvidenciasPendientes();
      final pendAcc  = await proy.contarAccionesPendientes();
      if ((pendAsis > 0 || pendEvid > 0 || pendAcc > 0) && await asis.canReachServer()) {
        bool enviado = false;
        if (pendAsis > 0) { await asis.sincronizarPendientes(); enviado = true; }
        if (pendEvid > 0) { await proy.sincronizarEvidencias();  enviado = true; }
        if (pendAcc  > 0) { await proy.sincronizarAcciones();    enviado = true; }
        // Notificar a las pantallas que escuchan para que se refresquen
        if (enviado) syncCompletedNotifier.value++;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MainShell] _triggerSync error: $e');
    }
  }

  /// Recibe el índice VISUAL del bottom nav (puede tener 4 ó 5 destinos según
  /// permisos) y lo traduce al índice del array fijo `_screens`.
  void _onTabTappedWithOfflineCheck(int visualIdx) {
    final screenIdx = _navDestinations[visualIdx].screenIdx;
    // Inicio (0) y Operaciones (1) funcionan offline; el resto requiere red.
    if (!isOnlineNotifier.value && screenIdx != 0 && screenIdx != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sin conexión. Solo Inicio, Operaciones y Asistencia están disponibles.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFD98A16),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    tabNotifier.value = screenIdx;
  }

  /// Destinos del bottom nav. La pestaña Logística solo aparece para roles
  /// con permiso de inventario (logística / admin / superadmin).
  List<_NavDest> get _navDestinations => [
        const _NavDest(
          screenIdx: 0, label: 'Inicio',
          icon: Icons.home_outlined, selectedIcon: Icons.home_rounded,
        ),
        const _NavDest(
          screenIdx: 1, label: 'Operaciones',
          icon: Icons.build_outlined, selectedIcon: Icons.build_rounded,
        ),
        if (_puedeLogistica)
          const _NavDest(
            screenIdx: _logisticaScreenIdx, label: 'Logística',
            icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded,
          ),
        if (_puedePersonal)
          const _NavDest(
            screenIdx: 3, label: 'Personal',
            icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded,
          ),
        const _NavDest(
          screenIdx: 4, label: 'Más',
          icon: Icons.more_horiz_rounded, selectedIcon: Icons.more_horiz_rounded,
        ),
      ];

  /// Traducción screen idx → posición en el nav visible. Si la pestaña actual
  /// no está en el nav (no debería pasar tras `_cargarPermisos`), devuelve 0.
  int get _visualSelectedIndex {
    final dests = _navDestinations;
    for (int i = 0; i < dests.length; i++) {
      if (dests[i].screenIdx == _currentIndex) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            // TickerMode mutea las animaciones (incluido el fondo TopoBackground)
            // de las pestañas ocultas del IndexedStack → no repintan a 60fps en
            // segundo plano. Se reanudan al volver a la pestaña.
            child: FadeTransition(
              opacity: _tabTransCtrl,
              child: SlideTransition(
                position: _tabTransCtrl.drive(
                  Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeOutCubic)),
                ),
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    for (int i = 0; i < _screens.length; i++)
                      // Solo se monta la pantalla si ya fue visitada (_activated);
                      // las no visitadas son un placeholder vacío → cero coste.
                      _activated[i]
                          ? TickerMode(
                              enabled: _currentIndex == i, child: _screens[i])
                          : const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // E-Zybot: burbuja flotante global (recuperada de la rama chatbot-app).
      // Mismo gate que la pestaña Logística: solo quien gestiona inventario.
      floatingActionButton: _puedeLogistica
          ? ChatbotLauncher(pantalla: _nombresTab[_currentIndex])
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _visualSelectedIndex,
        onDestinationSelected: _onTabTappedWithOfflineCheck,
        animationDuration: const Duration(milliseconds: 320),
        destinations: [
          for (final d in _navDestinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

/// Metadatos de un destino del bottom nav. `screenIdx` es la posición fija en
/// `_MainShellState._screens` (no cambia entre roles).
class _NavDest {
  final int screenIdx;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavDest({
    required this.screenIdx,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
