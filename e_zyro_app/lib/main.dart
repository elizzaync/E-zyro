import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'widgets/offline_overlay.dart';
import 'widgets/chatbot/chatbot_launcher.dart';
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
import 'screens/pantalla_mantenimientos.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase: solo mobile soporta FCM. En web/Windows se inicializa sin handler.
  try {
    await Firebase.initializeApp();
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[Firebase] Init error: ${e.runtimeType}');
  }

  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('dark_mode') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  await initializeDateFormatting('es_ES', null);
  await NotificationService.initialize();
  await ConnectivityService.instance.initialize();
  runApp(const ESystemApp());
}

// ── Paleta de marca "E-System" ────────────────────────────────────────────
const Color _kLime = Color(0xFF8FD11B); // verde lima (acento neón)
const Color _kForest = Color(0xFF5A9A00); // verde bosque (acento profundo)

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  var scheme = ColorScheme.fromSeed(seedColor: _kLime, brightness: brightness);

  // ── Estilo artístico de modo oscuro (estilo logística, app-wide) ─────────
  // Recolorea las superficies M3 hacia un verde-bosque profundo en vez del
  // gris-violáceo por defecto. Se propaga a TODA la app porque las pantallas
  // ya leen scheme.surface / scaffoldBackgroundColor.
  if (isDark) {
    scheme = scheme.copyWith(
      primary: _kLime,
      onPrimary: const Color(0xFF0C1506),
      onSurface: const Color(0xFFE7F2D8),
      onSurfaceVariant: const Color(0xFF9FB58B),
      outline: _kLime.withValues(alpha: 0.28),
      outlineVariant: _kLime.withValues(alpha: 0.14),
      surface: const Color(0xFF16240C),
      surfaceContainerLowest: const Color(0xFF0B1305),
      surfaceContainerLow: const Color(0xFF0F1A08),
      surfaceContainer: const Color(0xFF16240C),
      surfaceContainerHigh: const Color(0xFF1D2F11),
      surfaceContainerHighest: const Color(0xFF243A15),
    );
  }

  final accentSel = isDark ? _kLime : _kForest;

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surfaceContainerLow,
    cardColor: scheme.surface,
    dividerColor: isDark
        ? _kLime.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08),
    // ── Transiciones de página suaves (Material 3 Zoom) ──────────────────
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      },
    ),
    // ── AppBar ────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    // ── Tarjetas: bordes neón en oscuro (estilo "cuadro" de logística) ────
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDark
            ? BorderSide(color: _kLime.withValues(alpha: 0.22), width: 1)
            : BorderSide.none,
      ),
    ),
    // ── Botones ───────────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _kLime,
        foregroundColor: isDark ? const Color(0xFF0C1506) : Colors.white,
        elevation: isDark ? 0 : 1,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _kLime,
        foregroundColor: isDark ? const Color(0xFF0C1506) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: accentSel,
        side: BorderSide(color: _kLime.withValues(alpha: isDark ? 0.55 : 0.8)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accentSel),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _kLime,
      foregroundColor: isDark ? const Color(0xFF0C1506) : Colors.white,
    ),
    // ── Diálogos / hojas / snackbars ──────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: _kLime.withValues(alpha: isDark ? 0.30 : 0.20)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    // ── NavigationBar (Material 3) ───────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: _kLime.withValues(alpha: isDark ? 0.22 : 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? accentSel : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? accentSel : scheme.onSurfaceVariant,
          size: 24,
        );
      }),
      elevation: 0,
      height: 68,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: isDark
            ? BorderSide(color: _kLime.withValues(alpha: 0.18))
            : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _kLime, width: 1.5),
      ),
    ),
  );
}

class ESystemApp extends StatelessWidget {
  const ESystemApp({super.key});

  /// NavigatorKey global — lo usa FcmFlutterService para navegar al tocar push.
  static final navigatorKey = GlobalKey<NavigatorState>();

  Map<String, WidgetBuilder> _routes() => {
    '/splash': (context) => const SplashScreen(),
    '/login': (context) => const LoginScreen(),
    '/recovery': (context) => const PasswordRecoveryScreen(),
    '/': (context) => const MainShell(),
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
        title: const Text(
          'Asistencia',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: const AsistenciaScreen(),
    ),
    '/auditoria': (_) => const PantallaAuditoria(),
    '/mantenimientos': (_) => const PantallaMantenimientos(),
    '/historial-equipo': (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, String>?;
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
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
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

class _MainShellState extends State<MainShell> {
  late int _currentIndex;
  Timer? _syncTimer;
  bool _puedeLogistica = false;
  bool _puedePersonal = false;

  // Índice fijo de la pantalla de logística en _screens. Se mantiene en la
  // lista aunque el usuario no tenga permiso para no descuadrar otros
  // tabNotifier.value que se pasan entre módulos.
  static const _logisticaScreenIdx = 2;
  static const _personalScreenIdx = 3;

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

  @override
  void dispose() {
    tabNotifier.removeListener(_onTabChanged);
    isOnlineNotifier.removeListener(_onConnectivityChanged);
    sessionExpiredSyncNotifier.removeListener(_onSessionExpiredDuringSync);
    permissionsRefreshNotifier.removeListener(_cargarPermisos);
    _syncTimer?.cancel();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted) return;
    var target = tabNotifier.value;
    // Bloqueo: si alguien intenta ir a logística/personal sin permiso → Inicio.
    if (!_puedeLogistica && target == _logisticaScreenIdx) {
      tabNotifier.value = 0;
      return;
    }
    if (!_puedePersonal && target == _personalScreenIdx) {
      tabNotifier.value = 0;
      return;
    }
    if (_currentIndex != target) {
      setState(() => _currentIndex = target);
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
      final auth = AuthService(ApiClient(prefs), prefs);
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
      final auth = AuthService(ApiClient(prefs), prefs);
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
        id: 99,
        title: 'Sesión expirada',
        body: pendientes > 0
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
              const Icon(
                Icons.lock_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
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
            label: 'Iniciar sesión',
            textColor: const Color(0xFF8FD11B),
            onPressed: () {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/login', (route) => false);
            },
          ),
          backgroundColor: Colors.purple.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _triggerSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final asis = AsistenciaService(ApiClient(prefs));
      final proy = ProyectoService(ApiClient(prefs));
      // Solo sincronizar si hay pendientes (asistencia o evidencias) Y el
      // servidor Railway es alcanzable. Un solo probe canReachServer() para
      // ambas colas (HTTP crudo sin token → no falla con 401).
      final pendAsis = await asis.contarPendientes();
      final pendEvid = await proy.contarEvidenciasPendientes();
      final pendAcc = await proy.contarAccionesPendientes();
      if ((pendAsis > 0 || pendEvid > 0 || pendAcc > 0) &&
          await asis.canReachServer()) {
        bool enviado = false;
        if (pendAsis > 0) {
          await asis.sincronizarPendientes();
          enviado = true;
        }
        if (pendEvid > 0) {
          await proy.sincronizarEvidencias();
          enviado = true;
        }
        if (pendAcc > 0) {
          await proy.sincronizarAcciones();
          enviado = true;
        }
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
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
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
      screenIdx: 0,
      label: 'Inicio',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    const _NavDest(
      screenIdx: 1,
      label: 'Operaciones',
      icon: Icons.build_outlined,
      selectedIcon: Icons.build_rounded,
    ),
    if (_puedeLogistica)
      const _NavDest(
        screenIdx: _logisticaScreenIdx,
        label: 'Logística',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
      ),
    if (_puedePersonal)
      const _NavDest(
        screenIdx: 3,
        label: 'Personal',
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
      ),
    const _NavDest(
      screenIdx: 4,
      label: 'Más',
      icon: Icons.more_horiz_rounded,
      selectedIcon: Icons.more_horiz_rounded,
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
      body: Stack(
        children: [
          Column(
            children: [
              const OfflineBanner(),
              Expanded(
                // TickerMode mutea las animaciones (incluido el fondo TopoBackground)
                // de las pestañas ocultas del IndexedStack → no repintan a 60fps en
                // segundo plano. Se reanudan al volver a la pestaña.
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    for (int i = 0; i < _screens.length; i++)
                      TickerMode(
                        enabled: _currentIndex == i,
                        child: _screens[i],
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Burbuja flotante del asistente E-Zybot, visible en las 5 pestañas
          // principales. Al entrar a subpantallas (rutas pushed) queda cubierta.
          const Positioned(right: 16, bottom: 16, child: ChatbotLauncher()),
        ],
      ),
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
