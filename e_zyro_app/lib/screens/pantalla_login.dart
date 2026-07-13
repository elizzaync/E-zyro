import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/connectivity_service.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_notifiers.dart';
import '../utils/app_session.dart';
import '../widgets/e_system_painters.dart';
import '../widgets/topo_background.dart';
import '../theme/ez_theme.dart';
import 'pantalla_recuperacion_password.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Paleta — siempre fondo oscuro (no depende de isDark)
// ─────────────────────────────────────────────────────────────────────────────
const _kAccent   = Color(0xFF8FD11B);  // verde lima — números / acentos
const _kGreenBtn = Color(0xFF4E9E00);  // verde CTA / botón principal
const _kBg1      = Color(0xFF1A4400);  // fondo superior (topo c1)
const _kBg2      = Color(0xFF2D7100);  // fondo medio  (topo c2)
const _kBgBase   = Color(0xFF091500);  // base más oscura (topo base)

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// Radial sparks from the bolt logo
const List<Particle> _sparks = [
  Particle(dx:  58,  dy: -42, size: 3.0, phase: 0.00, duration: 2.0),
  Particle(dx: -52,  dy: -46, size: 2.5, phase: 0.15, duration: 2.2),
  Particle(dx:  68,  dy:  14, size: 2.0, phase: 0.30, duration: 1.8),
  Particle(dx: -60,  dy:  20, size: 3.0, phase: 0.45, duration: 2.5),
  Particle(dx:  30,  dy: -60, size: 2.0, phase: 0.60, duration: 2.0),
  Particle(dx: -22,  dy:  54, size: 2.5, phase: 0.75, duration: 1.9),
  Particle(dx:  48,  dy:  40, size: 1.5, phase: 0.10, duration: 2.3),
  Particle(dx: -40,  dy: -54, size: 2.0, phase: 0.55, duration: 1.7),
  Particle(dx:  24,  dy: -24, size: 1.5, phase: 0.20, duration: 1.5),
  Particle(dx: -30,  dy:  16, size: 1.5, phase: 0.70, duration: 1.6),
  Particle(dx:  14,  dy:  30, size: 1.5, phase: 0.40, duration: 1.8),
  Particle(dx: -44,  dy:  34, size: 2.0, phase: 0.85, duration: 2.1),
];

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── Controllers ─────────────────────────────────────────────────────────────
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  late AnimationController _pulseCtrl;
  late AnimationController _particleCtrl;

  // ── Logo position for particle origin ────────────────────────────────────
  final _logoKey = GlobalKey();
  Offset _logoCenter = const Offset(60, 120);

  // ── Servicios ────────────────────────────────────────────────────────────────
  AuthService? _authService;
  BiometricService? _bioService;
  SharedPreferences? _prefs;

  // ── Estado de sesión / bio ────────────────────────────────────────────────
  bool _hasSession = false;
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _showPasswordForm = false;

  // ── Rate limiting ─────────────────────────────────────────────────────────
  int _loginAttempts = 0;
  DateTime? _lockoutUntil;
  static const _maxAttempts = 5;
  static const _lockoutDuration = Duration(seconds: 60);

  bool get _isBioMode =>
      _hasSession && _bioEnabled && _bioAvailable && !_showPasswordForm;

  // ── Ciclo de vida ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    _initServices();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLogo());
    isOnlineNotifier.addListener(_onConnectivityChange);
  }

  void _onConnectivityChange() {
    if (mounted) setState(() {});
  }

  void _measureLogo() {
    final box = _logoKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    // Solo actualiza si la posición cambió, para evitar rebuilds infinitos
    if (center != _logoCenter) setState(() => _logoCenter = center);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _pulseCtrl.dispose();
    _particleCtrl.dispose();
    isOnlineNotifier.removeListener(_onConnectivityChange);
    super.dispose();
  }

  Future<void> _initServices() async {
    final prefs    = await SharedPreferences.getInstance();
    final authSvc  = await getAuthService();
    final bioSvc   = BiometricService(prefs);
    final hasSess  = prefs.getString('auth_token') != null;
    final bioAvail = await bioSvc.isAvailable();
    final bioEnab  = bioSvc.isEnabled;
    if (!mounted) return;
    setState(() {
      _authService  = authSvc;
      _bioService   = bioSvc;
      _prefs        = prefs;
      _hasSession   = hasSess;
      _bioAvailable = bioAvail;
      _bioEnabled   = bioEnab;
    });
    if (hasSess && bioEnab && bioAvail) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _authenticateWithBiometric();
    }
  }

  // ── FCM ───────────────────────────────────────────────────────────────────

  Future<void> _initFcm() async {
    if (_prefs == null) return;
    await FcmFlutterService.initialize(
      client: ApiClient(_prefs!),
      navKey: ESystemApp.navigatorKey,
    );
  }

  // ── Biométrico ────────────────────────────────────────────────────────────

  Future<void> _authenticateWithBiometric() async {
    if (_bioService == null || _authService == null) return;
    final success = await _bioService!.authenticate();
    if (!mounted) return;
    if (!success) return;

    // Verificar validez del token localmente ANTES de tocar la red
    final tokenValido = _authService!.isStoredTokenValid();

    try {
      await _authService!.refreshToken();
      if (!mounted) return;
      _initFcm();
      Navigator.pushReplacementNamed(context, AppSession.i.rutaHome);
    } catch (_) {
      if (!mounted) return;
      if (tokenValido) {
        // Sin red pero JWT aún vigente → entrar directamente
        _initFcm();
        Navigator.pushReplacementNamed(context, AppSession.i.rutaHome);
      } else {
        // Token realmente expirado — necesita conexión para renovarlo
        final warning = context.ez.warning;
        await _authService!.logout();
        if (!mounted) return;
        setState(() { _hasSession = false; _showPasswordForm = true; });
        _showSnack(
          'Sesión expirada. Conéctate a internet para renovarla.',
          warning,
        );
      }
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  bool get _isLockedOut {
    if (_lockoutUntil == null) return false;
    return DateTime.now().isBefore(_lockoutUntil!);
  }

  Future<void> _handleLogin() async {
    if (_authService == null || _isLoading) return;
    if (_isLockedOut) {
      final secs = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      _showSnack('Demasiados intentos. Espera $secs segundos.', context.ez.danger);
      return;
    }
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showSnack('Completa usuario y contraseña', context.ez.warning);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService!.login(username: username, password: password);
      if (!mounted) return;
      _loginAttempts = 0;
      final bioAvailable = await (_bioService?.isAvailable() ?? Future.value(false));
      final bioEnabled   = _bioService?.isEnabled ?? false;
      if (!mounted) return;
      if (bioAvailable && !bioEnabled) {
        _showBiometricSetupSheet();
      } else {
        _initFcm();
        Navigator.pushReplacementNamed(context, AppSession.i.rutaHome);
      }
    } catch (e) {
      if (!mounted) return;
      _loginAttempts++;
      if (_loginAttempts >= _maxAttempts) {
        setState(() {
          _lockoutUntil  = DateTime.now().add(_lockoutDuration);
          _loginAttempts = 0;
        });
        _showSnack('Cuenta bloqueada 60 s por múltiples intentos.', context.ez.danger);
      } else {
        _showSnack(_sanitize(e.toString()), context.ez.danger);
      }
      setState(() => _isLoading = false);
    }
  }

  String _sanitize(String raw) {
    if (raw.contains('incorrectos') || raw.contains('contraseña')) {
      return 'Usuario o contraseña incorrectos';
    }
    if (raw.contains('500') || raw.contains('servidor')) {
      return 'Error del servidor. Intenta nuevamente.';
    }
    if (raw.contains('timeout') || raw.contains('SocketException')) {
      return 'Sin conexión. Verifica tu red.';
    }
    return 'Error al iniciar sesión. Intenta nuevamente.';
  }

  void _showBiometricSetupSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BiometricPolicySheet(
        onAccepted: () async {
          await _bioService?.enable();
          if (mounted) { _initFcm(); Navigator.pushReplacementNamed(context, AppSession.i.rutaHome); }
        },
        onDeclined: () { _initFcm(); Navigator.pushReplacementNamed(context, AppSession.i.rutaHome); },
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Remedir el logo cada vez que el layout cambia
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureLogo());

    final screenH = MediaQuery.of(context).size.height;
    // Card ocupa exactamente 55% — la sección de marca queda en el 45% superior
    final cardH = screenH * 0.55;

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          TopoBackground(
            c1:    _kBg1,
            c2:    _kBg2,
            base:  _kBgBase,
            count: 28,
            amp:   14,
            stroke: 0.45,
            speed:  0.55,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Área de marca — ocupa el espacio restante
                  Flexible(child: _buildBrandSection()),
                  // Card blanca inferior — altura fija al 55% de pantalla
                  SizedBox(
                    height: cardH,
                    child: _isBioMode ? _buildBioCard() : _buildFormCard(),
                  ),
                ],
              ),
            ),
          ),

          // Partículas sobre el fondo, ignorando gestos
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _particleCtrl,
                builder: (context, child) => CustomPaint(
                  painter: ParticlePainter(
                    t: _particleCtrl.value,
                    particles: _sparks,
                    ambient: const [],
                    originX: _logoCenter.dx,
                    originY: _logoCenter.dy,
                    color: const Color(0xFF8FD11B),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Sección de marca (sobre el fondo verde) ───────────────────────────────

  Widget _buildBrandSection() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── Amanecer desde la esquina superior izquierda ────────────────────
        // Capa 1: sol — núcleo brillante en la esquina sup-izq
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1.35, -1.4),
                  radius: 2.2,
                  colors: [
                    const Color(0xFFDDFF00).withValues(alpha: 0.72),
                    const Color(0xFF9AE600).withValues(alpha: 0.45),
                    const Color(0xFF55C000).withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.22, 0.50, 1.0],
                ),
              ),
            ),
          ),
        ),
        // Capa 2: aureola difusa que extiende la luz hacia el centro
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-1.1, -1.0),
                  radius: 1.7,
                  colors: [
                    const Color(0xFFBBFF00).withValues(alpha: 0.30),
                    const Color(0xFF6DC800).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
        ),
        LayoutBuilder(builder: (_, constraints) {
      final compact = constraints.maxHeight < 220;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, compact ? 12 : 20, 24, compact ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ── Fila logo + nombre ────────────────────────────────────────
            Row(
              children: [
                Container(
                  key: _logoKey,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _kAccent.withValues(alpha: 0.40),
                        blurRadius: 16,
                        spreadRadius: 1,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/estelogo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'E-System TIC',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                    Text(
                      '• SISTEMA OPERATIVO',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 9.5,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (!compact) const SizedBox(height: 22),
            if (!compact)
              const Text(
                'Conecta con tu\nequipo de campo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.5,
                ),
              ),
            if (compact)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Conecta con tu equipo de campo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),

            SizedBox(height: compact ? 10 : 18),

            // ── Stats ─────────────────────────────────────────────────────
            Row(
              children: [
                _buildStat('248', 'TÉCNICOS EN LÍNEA'),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: Colors.white.withValues(alpha: 0.2),
                ),
                _buildStat('12.5K', 'SERVICIOS / MES'),
              ],
            ),
          ],
        ),
      );
    }),       // fin LayoutBuilder — hijo del Stack
      ],
    );        // fin Stack
  }

  Widget _buildStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _kAccent,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 10,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Card blanca del formulario ────────────────────────────────────────────

  Widget _buildFormCard() {
    final ez = context.ez;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ez.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 32,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Indicador de arrastre
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Acceso rápido offline ─────────────────────────────────────
              if (!isOnlineNotifier.value &&
                  (_authService?.isStoredTokenValid() ?? false)) ...[
                _buildOfflineQuickAccess(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade200)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'o inicia sesión',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade400),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade200)),
                    ],
                  ),
                ),
              ],

              // Volver a biométrico
              if (_hasSession && _bioEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _showPasswordForm = false);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _isBioMode) _authenticateWithBiometric();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _kAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fingerprint, color: _kGreenBtn, size: 17),
                          SizedBox(width: 7),
                          Text(
                            'Usar huella digital',
                            style: TextStyle(
                              color: _kGreenBtn,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Campo usuario ───────────────────────────────────────────
              _buildInputField(
                controller: _usernameController,
                hint: 'Correo electrónico',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),

              // ── Campo contraseña ────────────────────────────────────────
              _buildInputField(
                controller: _passwordController,
                hint: 'Contraseña',
                icon: Icons.lock_outline_rounded,
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: Colors.grey.shade400,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                onSubmitted: (_) => _handleLogin(),
              ),
              const SizedBox(height: 8),

              // ¿Olvidaste la contraseña?
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PasswordRecoveryScreen()),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '¿Olvidaste tu contraseña?',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Botón Iniciar Sesión ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: _isLoading || _authService == null
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFF68C000), Color(0xFF3E8A00)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    color: _isLoading || _authService == null
                        ? _kGreenBtn.withValues(alpha: 0.45)
                        : null,
                    boxShadow: _isLoading || _authService == null
                        ? null
                        : [
                            BoxShadow(
                              color: _kGreenBtn.withValues(alpha: 0.40),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: ElevatedButton(
                    onPressed:
                        (_isLoading || _authService == null) ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Iniciar Sesión',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 18),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Footer
              Center(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                    children: [
                      const TextSpan(text: '¿No tienes cuenta? '),
                      TextSpan(
                        text: 'Solicitar al equipo',
                        style: const TextStyle(
                          color: _kGreenBtn,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ── Acceso rápido cuando no hay internet pero el token es válido ─────────

  Widget _buildOfflineQuickAccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 14, color: Colors.amber.shade700),
            const SizedBox(width: 6),
            Text(
              'Sin internet · Acceso offline disponible',
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _OfflineShortcutButton(
                icon: Icons.fingerprint,
                label: 'Asistencia',
                onTap: () {
                  _initFcm();
                  Navigator.pushReplacementNamed(context, '/asistencia');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _OfflineShortcutButton(
                icon: Icons.build_outlined,
                label: 'Proyectos',
                onTap: () {
                  _initFcm();
                  tabNotifier.value = 1; // tab Operaciones
                  Navigator.pushReplacementNamed(context, '/');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Card biométrico ───────────────────────────────────────────────────────

  Widget _buildBioCard() {
    final ez = context.ez;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: ez.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 32,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge sesión protegida
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _kAccent.withValues(alpha: 0.28)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: _kGreenBtn, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Sesión protegida',
                      style: TextStyle(
                        color: _kGreenBtn,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Botón huella con pulso animado
              GestureDetector(
                onTap: _authenticateWithBiometric,
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) {
                    final pulse = math.sin(_pulseCtrl.value * math.pi);
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 140 + pulse * 14,
                          height: 140 + pulse * 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kAccent.withValues(
                                alpha: 0.05 + pulse * 0.04),
                          ),
                        ),
                        Container(
                          width: 120 + pulse * 6,
                          height: 120 + pulse * 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _kAccent.withValues(
                                alpha: 0.09 + pulse * 0.05),
                          ),
                        ),
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF68C000),
                                Color(0xFF3E8A00),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _kGreenBtn.withValues(
                                    alpha: 0.40 + pulse * 0.15),
                                blurRadius: 24 + pulse * 12,
                                spreadRadius: 2 + pulse * 3,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.fingerprint,
                              color: Colors.white, size: 52),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),

              const Text(
                'Toca para acceder',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2E06),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Usa tu huella digital o Face ID',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 18),

              TextButton(
                onPressed: () => setState(() => _showPasswordForm = true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade500,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_outlined, size: 15),
                    SizedBox(width: 6),
                    Text('Usar contraseña',
                        style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Campo de texto (solo para card blanca) ────────────────────────────────

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF1A2E06),
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(icon, size: 20, color: Colors.grey.shade400),
          suffixIcon: suffix,
          filled: false,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
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
            borderSide: const BorderSide(color: _kGreenBtn, width: 1.5),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Botón de acceso rápido offline
// ─────────────────────────────────────────────────────────────────────────────

class _OfflineShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OfflineShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _kGreenBtn.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kGreenBtn.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, color: _kGreenBtn, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: _kGreenBtn,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Sheet de política biométrica
// ─────────────────────────────────────────────────────────────────────────────

class _BiometricPolicySheet extends StatefulWidget {
  final VoidCallback onAccepted;
  final VoidCallback onDeclined;

  const _BiometricPolicySheet({
    required this.onAccepted,
    required this.onDeclined,
  });

  @override
  State<_BiometricPolicySheet> createState() => _BiometricPolicySheetState();
}

class _BiometricPolicySheetState extends State<_BiometricPolicySheet> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    final ez = context.ez;
    return Container(
      decoration: BoxDecoration(
        color: ez.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: ez.hairline,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kAccent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.fingerprint, size: 38, color: _kGreenBtn),
          ),
          const SizedBox(height: 10),
          const Text('Acceso con Huella Digital',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('E-System TIC — Política de uso',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.32),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _PolicyItem(
                    icon: Icons.security,
                    title: 'Almacenamiento local',
                    body: 'Los datos biométricos son procesados exclusivamente '
                        'por el sistema operativo. E-System TIC no almacena ni '
                        'accede a tu información biométrica.',
                  ),
                  SizedBox(height: 12),
                  _PolicyItem(
                    icon: Icons.phone_android,
                    title: 'Pérdida o robo',
                    body: 'Notifica INMEDIATAMENTE al equipo técnico si pierdes '
                        'o te roban el dispositivo. Eres responsable de cualquier '
                        'acceso hasta el bloqueo de tu cuenta.',
                  ),
                  SizedBox(height: 12),
                  _PolicyItem(
                    icon: Icons.toggle_off_outlined,
                    title: 'Revocación',
                    body: 'Puedes deshabilitar el acceso biométrico en cualquier '
                        'momento desde tu perfil.',
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: InkWell(
              onTap: () => setState(() => _accepted = !_accepted),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                    activeColor: _kGreenBtn,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  const Expanded(
                    child: Text(
                      'Acepto la política y me comprometo a notificar si pierdo '
                      'mi dispositivo.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _accepted
                        ? () {
                            Navigator.pop(context);
                            widget.onAccepted();
                          }
                        : null,
                    icon: const Icon(Icons.fingerprint, size: 20),
                    label: const Text('Habilitar huella digital',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kGreenBtn,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade200,
                      disabledForegroundColor: Colors.grey,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDeclined();
                  },
                  child: Text('Ahora no',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _PolicyItem(
      {required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _kAccent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: _kGreenBtn),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              Text(body,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
