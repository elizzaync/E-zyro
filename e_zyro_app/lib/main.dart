import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/app_notifiers.dart';
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

  final List<Widget> _screens = const [
    HomeScreen(),
    OperationsScreen(),
    LogisticsScreen(),
    PersonalScreen(),
    MoreScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    tabNotifier.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    tabNotifier.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (mounted && _currentIndex != tabNotifier.value) {
      setState(() => _currentIndex = tabNotifier.value);
    }
  }

  void _onTabTapped(int index) {
    tabNotifier.value = index;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF8FD11B),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build_outlined),
            activeIcon: Icon(Icons.build),
            label: 'Operaciones',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            activeIcon: Icon(Icons.inventory_2),
            label: 'Logística',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Personal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.more_horiz),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
