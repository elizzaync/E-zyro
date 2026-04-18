import 'package:flutter/material.dart';
import 'screens/pantalla_principal.dart';
import 'screens/pantalla_operaciones.dart';
import 'screens/pantalla_logistica.dart';
import 'screens/pantalla_perfil.dart';
import 'screens/pantalla_mas.dart';

void main() {
  runApp(const ESystemApp());
}

class ESystemApp extends StatelessWidget {
  const ESystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-System TIC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8FD11B)),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      // ─── Ruta inicial ───────────────────────────────────────────────
      initialRoute: '/',
      // ─── Tabla de rutas nombradas ────────────────────────────────────
      routes: {
        '/': (context) => const MainShell(),
        '/home': (context) => const MainShell(initialIndex: 0),
        '/operations': (context) => const MainShell(initialIndex: 1),
        '/logistics': (context) => const MainShell(initialIndex: 2),
        '/personal': (context) => const MainShell(initialIndex: 3),
        '/more': (context) => const MainShell(initialIndex: 4),
      },
    );
  }
}

// ─── Shell principal con BottomNavigationBar ────────────────────────────────
class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _currentIndex;

  // Lista de pantallas en el mismo orden que los ítems del nav
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
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── Contenido de la pantalla activa ──
      body: IndexedStack(index: _currentIndex, children: _screens),
      // ── Barra de navegación inferior ──
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
          BottomNavigationBarItem(icon: Icon(Icons.more_horiz), label: 'Más'),
        ],
      ),
    );
  }
}
