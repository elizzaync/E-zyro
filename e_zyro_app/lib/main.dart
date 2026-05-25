import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api_client.dart';
import 'core/connectivity_service.dart';
import 'services/asistencia_service.dart';
import 'utils/app_notifiers.dart';
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

ThemeData _buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8FD11B),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surfaceContainerLow,
    cardColor: scheme.surface,
    // ── Transiciones de página suaves (Material 3 Zoom) ──────────────────
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS:     ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(),
      },
    ),
    // ── NavigationBar (Material 3) ───────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: const Color(0xFF8FD11B).withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? const Color(0xFF5A9A00) : scheme.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? const Color(0xFF5A9A00) : scheme.onSurfaceVariant,
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
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF8FD11B), width: 1.5),
      ),
    ),
  );
}

class ESystemApp extends StatelessWidget {
  const ESystemApp({super.key});

  /// NavigatorKey global — lo usa FcmFlutterService para navegar al tocar push.
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, _) => MaterialApp(
        title: 'E-System TIC',
        debugShowCheckedModeBanner: false,
        navigatorKey: ESystemApp.navigatorKey,
        themeMode: mode,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        initialRoute: '/splash',
        routes: {
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
              title: const Text('Asistencia',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              elevation: 0,
              backgroundColor: Colors.transparent,
            ),
            body: const AsistenciaScreen(),
          ),
          '/auditoria': (_) => const PantallaAuditoria(),
          '/mantenimientos': (_) => const PantallaMantenimientos(),
          '/historial-equipo': (context) {
            final args = ModalRoute.of(context)?.settings.arguments
                as Map<String, String>?;
            return PantallaHistorialEquipo(
              equipoId: args?['equipoId'] ?? '',
              equipoNombre: args?['equipoNombre'] ?? 'Equipo',
            );
          },
        },
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

  // Operaciones (índice 1) funciona offline con datos en memoria.
  // El resto requiere red → OfflineOverlay los bloquea automáticamente.
  static const List<Widget> _screens = [
    OfflineOverlay(child: HomeScreen()),
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
    // Disparar sync de asistencias al volver a tener red
    isOnlineNotifier.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    tabNotifier.removeListener(_onTabChanged);
    isOnlineNotifier.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted && _currentIndex != tabNotifier.value) {
      setState(() => _currentIndex = tabNotifier.value);
    }
  }

  void _onConnectivityChanged() {
    if (!mounted) return;
    if (isOnlineNotifier.value) {
      // Volvió la red → disparar sync de asistencias en background
      _triggerAsistenciaSync();
    }
  }

  Future<void> _triggerAsistenciaSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final svc = AsistenciaService(ApiClient(prefs));
      await svc.sincronizarPendientes();
    } catch (_) {}
  }

  void _onTabTappedWithOfflineCheck(int index) {
    // Informar al usuario si intenta acceder a una tab bloqueada sin red
    if (!isOnlineNotifier.value && index != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sin conexión. Solo Operaciones disponible offline.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    tabNotifier.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: IndexedStack(index: _currentIndex, children: _screens),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onTabTappedWithOfflineCheck,
        animationDuration: const Duration(milliseconds: 320),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.build_outlined),
            selectedIcon: Icon(Icons.build_rounded),
            label: 'Operaciones',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Logística',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Personal',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_horiz_rounded),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
