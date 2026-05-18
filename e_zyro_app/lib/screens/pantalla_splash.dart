import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/fcm_flutter_service.dart';
import '../widgets/topo_background.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    // Restaurar token desde SecureStorage si SharedPreferences fue borrado
    await AuthService.restoreTokenIfNeeded(prefs);
    final hasToken = prefs.getString('auth_token') != null;
    final bioEnabled = prefs.getBool('biometric_enabled') ?? false;
    if (!mounted) return;

    // Cuando ya hay sesión y no se pasa por login, inicializar FCM aquí.
    if (hasToken && !bioEnabled) {
      FcmFlutterService.initialize(
        client: ApiClient(prefs),
        navKey: ESystemApp.navigatorKey,
      );
    }

    // Si biométrica habilitada → pasar siempre por login para verificación.
    // Si no → acceso directo al home cuando ya hay sesión.
    Navigator.pushReplacementNamed(
      context,
      (!hasToken || bioEnabled) ? '/login' : '/',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TopoBackground(
        count: 18,
        amp: 10,
        stroke: 0.45,
        speed: 0.7,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/logo.png', width: 180, height: 180),
                      const SizedBox(height: 28),
                      RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'e-System ',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            TextSpan(
                              text: 'Tic',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8FD11B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Soluciones innovadoras para tu empresa',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
