import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // ── Animaciones ───────────────────────────────────────────────────────────
  late AnimationController _ctrl;
  late Animation<double>  _logoScale;
  late Animation<double>  _logoOpacity;
  late Animation<double>  _textOpacity;
  late Animation<Offset>  _textSlide;
  late Animation<double>  _subtitleOpacity;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // Logo: scale 0.72 → 1.0 con elasticidad + fade in
    _logoScale = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOut),
      ),
    );

    // Título: sube + fade in ligeramente después del logo
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.30, 0.65, curve: Curves.easeOut),
      ),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.28, 0.62, curve: Curves.easeOutCubic),
      ),
    );

    // Subtítulo: aparece al final
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.90, curve: Curves.easeOut),
      ),
    );

    _ctrl.forward();
    _navigate();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await AuthService.restoreTokenIfNeeded(prefs);
    await AppSession.load();
    final bioEnabled  = prefs.getBool('biometric_enabled') ?? false;
    final auth        = AuthService(ApiClient(prefs), prefs);
    // Validar el JWT localmente (sin red): expirado → login para renovar.
    final tokenValido = auth.isStoredTokenValid();
    // Autosanar rol+permisos desde el servidor (best-effort, no bloquea si offline).
    if (tokenValido) {
      await auth.refrescarSesion();
    }
    // Con biométrico vamos a /login para desbloquear con huella (que ya maneja
    // el caso offline). Sin biométrico, entramos directo si el token sigue
    // vigente, incluso sin internet.
    final irHome = !bioEnabled && tokenValido;
    if (!mounted) return;

    if (irHome) {
      FcmFlutterService.initialize(
        client: ApiClient(prefs),
        navKey: ESystemApp.navigatorKey,
      );
    }

    Navigator.pushReplacementNamed(
        context, irHome ? AppSession.i.rutaHome : '/login');
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
              // ── Contenido central ────────────────────────────────────
              Expanded(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context2, child2) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo animado
                        FadeTransition(
                          opacity: _logoOpacity,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF8FD11B).withValues(alpha: 0.30),
                                    blurRadius: 32,
                                    spreadRadius: 4,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: Image.asset(
                                  'assets/logo.png',
                                  width: 120,
                                  height: 120,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Nombre de la app
                        FadeTransition(
                          opacity: _textOpacity,
                          child: SlideTransition(
                            position: _textSlide,
                            child: RichText(
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
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Subtítulo
                        FadeTransition(
                          opacity: _subtitleOpacity,
                          child: const Text(
                            'Soluciones innovadoras para tu empresa',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Dots animados en el footer ───────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: _AnimatedDots(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tres puntos que pulsan secuencialmente ────────────────────────────────────
class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context2, child2) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Cada punto tiene su propio desfase
            final phase = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
            final scale = 1.0 + 0.5 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            final opacity = 0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8FD11B),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
