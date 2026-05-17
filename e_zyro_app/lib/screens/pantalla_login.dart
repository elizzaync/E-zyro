import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
import 'pantalla_recuperacion_password.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  AuthService? _authService;
  BiometricService? _bioService;
  SharedPreferences? _prefs;

  bool _hasSession = false;
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _showPasswordForm = false; // fallback desde modo bio

  // Modo bio: sesión activa + bio habilitada + dispositivo capaz
  bool get _isBioMode =>
      _hasSession && _bioEnabled && _bioAvailable && !_showPasswordForm;

  // ── Ciclo de vida ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initServices() async {
    final prefs = await SharedPreferences.getInstance();
    final authSvc = await getAuthService();
    final bioSvc = BiometricService(prefs);

    final hasSession = prefs.getString('auth_token') != null;
    final bioAvailable = await bioSvc.isAvailable();
    final bioEnabled = bioSvc.isEnabled;

    if (!mounted) return;
    setState(() {
      _authService = authSvc;
      _bioService = bioSvc;
      _prefs = prefs;
      _hasSession = hasSession;
      _bioAvailable = bioAvailable;
      _bioEnabled = bioEnabled;
    });

    // Si hay sesión y bio activa, lanzar el prompt automáticamente.
    if (hasSession && bioEnabled && bioAvailable) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _authenticateWithBiometric();
    }
  }

  // ── FCM: inicializar tras login exitoso ───────────────────────────────────

  Future<void> _initFcm() async {
    if (_prefs == null) return;
    await FcmFlutterService.initialize(
      client: ApiClient(_prefs!),
      navKey: ESystemApp.navigatorKey,
    );
  }

  // ── Autenticación biométrica ───────────────────────────────────────────────

  Future<void> _authenticateWithBiometric() async {
    if (_bioService == null || _authService == null) return;
    final success = await _bioService!.authenticate();
    if (!mounted) return;
    if (!success) return;

    // Renovar el token antes de ir al home — puede estar vencido tras dormir.
    try {
      await _authService!.refreshToken();
      if (!mounted) return;
      _initFcm(); // fire-and-forget: no bloqueamos la navegación
      Navigator.pushReplacementNamed(context, '/');
    } catch (_) {
      // Token demasiado antiguo (>30 días): forzar re-login con contraseña.
      if (!mounted) return;
      await _authService!.logout();
      setState(() {
        _hasSession = false;
        _showPasswordForm = true;
      });
      _showSnack(
        'Tu sesión expiró. Ingresa tu contraseña para continuar.',
        Colors.orange,
      );
    }
  }

  // ── Login con contraseña ───────────────────────────────────────────────────

  Future<void> _handleLogin() async {
    if (_authService == null || _isLoading) return;

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      _showSnack('Por favor completa todos los campos', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService!.login(username: username, password: password);
      if (!mounted) return;

      // Recargar estado de bio (puede haber cambiado)
      final bioAvailable = await (_bioService?.isAvailable() ?? Future.value(false));
      final bioEnabled = _bioService?.isEnabled ?? false;

      if (!mounted) return;

      if (bioAvailable && !bioEnabled) {
        // Ofrecer habilitar biométrica por primera vez
        _showBiometricSetupSheet();
      } else {
        _initFcm(); // fire-and-forget
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), Colors.red);
      setState(() => _isLoading = false);
    }
  }

  // ── Hoja de política biométrica ────────────────────────────────────────────

  void _showBiometricSetupSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BiometricPolicySheet(
        onAccepted: () async {
          await _bioService?.enable();
          if (mounted) {
            _initFcm();
            Navigator.pushReplacementNamed(context, '/');
          }
        },
        onDeclined: () {
          Navigator.pushReplacementNamed(context, '/');
        },
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: _isBioMode ? _buildBioLayout() : _buildPasswordLayout(),
      ),
    );
  }

  // ── Layout: modo biométrico (centrado vertical en pantalla completa) ────────

  Widget _buildBioLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildLogo(),
            const SizedBox(height: 52),
            _buildBioMode(),
          ],
        ),
      ),
    );
  }

  // ── Layout: formulario de contraseña (scrollable) ──────────────────────────

  Widget _buildPasswordLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 72),
          _buildLogo(),
          const SizedBox(height: 44),
          _buildPasswordForm(),
        ],
      ),
    );
  }

  // ── Logo ───────────────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF8FD11B),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8FD11B).withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.bolt, color: Colors.white, size: 42),
        ),
        const SizedBox(height: 22),
        const Text(
          'E-System TIC',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Plataforma de Servicios de Campo',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ],
    );
  }

  // ── Modo biométrico ────────────────────────────────────────────────────────

  Widget _buildBioMode() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Badge "Sesión protegida"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF8FD11B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, color: Color(0xFF8FD11B), size: 16),
              SizedBox(width: 6),
              Text(
                'Sesión protegida',
                style: TextStyle(
                  color: Color(0xFF8FD11B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 44),

        // Botón huella — tamaño aumentado y centrado
        GestureDetector(
          onTap: _authenticateWithBiometric,
          child: Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              color: const Color(0xFF8FD11B),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8FD11B).withValues(alpha: 0.40),
                  blurRadius: 36,
                  spreadRadius: 4,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(Icons.fingerprint, color: Colors.white, size: 88),
          ),
        ),
        const SizedBox(height: 28),

        const Text(
          'Toca para acceder',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Usa tu huella digital para ingresar',
          style: TextStyle(fontSize: 13, color: Colors.black38),
        ),
        const SizedBox(height: 36),

        // Fallback a contraseña
        TextButton(
          onPressed: () => setState(() => _showPasswordForm = true),
          style: TextButton.styleFrom(
            foregroundColor: Colors.grey.shade500,
          ),
          child: const Text(
            'Usar contraseña en su lugar',
            style: TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  // ── Formulario de contraseña ───────────────────────────────────────────────

  Widget _buildPasswordForm() {
    return Column(
      children: [
        // Banner "volver a bio" si el usuario eligió ver el form
        if (_hasSession && _bioEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TextButton.icon(
              onPressed: () {
                setState(() => _showPasswordForm = false);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _isBioMode) _authenticateWithBiometric();
                });
              },
              icon: const Icon(Icons.fingerprint, size: 18, color: Colors.grey),
              label: const Text(
                'Usar huella digital',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          ),

        _buildField(
          controller: _usernameController,
          hint: 'Correo electrónico',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _passwordController,
          hint: 'Contraseña',
          obscure: _obscurePassword,
          suffix: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: Colors.grey.shade400,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: (_isLoading || _authService == null) ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8FD11B),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFF8FD11B).withValues(alpha: 0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Iniciar Sesión',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 20),

        TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PasswordRecoveryScreen(),
            ),
          ),
          child: const Text(
            'Portal de Acceso para Técnicos',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14, color: Colors.black87),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
        suffixIcon: suffix,
      ),
    );
  }
}

// ─── Hoja de política biométrica ─────────────────────────────────────────────

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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icono y título
          const Icon(Icons.fingerprint, size: 48, color: Color(0xFF8FD11B)),
          const SizedBox(height: 12),
          const Text(
            'Acceso con Huella Digital',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'E-System TIC — Política de uso',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),

          // Política (scrollable)
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.35,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _PolicyItem(
                    icon: Icons.security,
                    title: 'Almacenamiento local',
                    body:
                        'Los datos biométricos son procesados exclusivamente '
                        'por el sistema operativo de tu dispositivo. '
                        'E-System TIC no almacena, transfiere ni accede a tu '
                        'información biométrica.',
                  ),
                  SizedBox(height: 16),
                  _PolicyItem(
                    icon: Icons.phone_android,
                    title: 'Pérdida o robo del dispositivo',
                    body:
                        'Si pierdes o te roban el dispositivo, debes notificar '
                        'INMEDIATAMENTE al equipo técnico de E-System TIC. '
                        'Eres personalmente responsable de cualquier acceso no '
                        'autorizado hasta que se realice dicha notificación y '
                        'se bloquee tu cuenta.',
                  ),
                  SizedBox(height: 16),
                  _PolicyItem(
                    icon: Icons.toggle_off_outlined,
                    title: 'Revocación',
                    body:
                        'Puedes deshabilitar el acceso biométrico en cualquier '
                        'momento desde tu perfil de usuario.',
                  ),
                  SizedBox(height: 16),
                  _PolicyItem(
                    icon: Icons.gavel_outlined,
                    title: 'Responsabilidad',
                    body:
                        'Al aceptar, asumes plena responsabilidad por el acceso '
                        'habilitado en este dispositivo y te comprometes a '
                        'actuar con diligencia en caso de pérdida.',
                  ),
                ],
              ),
            ),
          ),

          // Checkbox de aceptación
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: InkWell(
              onTap: () => setState(() => _accepted = !_accepted),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Checkbox(
                    value: _accepted,
                    onChanged: (v) => setState(() => _accepted = v ?? false),
                    activeColor: const Color(0xFF8FD11B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'He leído y acepto la política. Me comprometo a notificar '
                      'al equipo de E-System TIC si pierdo mi dispositivo.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Botones
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
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
                    label: const Text(
                      'Habilitar huella digital',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8FD11B),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade200,
                      disabledForegroundColor: Colors.grey,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onDeclined();
                  },
                  child: const Text(
                    'Ahora no',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
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

  const _PolicyItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF8FD11B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: const Color(0xFF8FD11B)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
