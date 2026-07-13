import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';
import '../theme/ez_theme.dart';

// ── Paleta de marca "E-System" (consistente con el login) ───────────────────
const _kAccent = Color(0xFF8FD11B); // verde lima — acentos
const _kBg1 = Color(0xFF1A4400); // fondo superior (topo c1)
const _kBg2 = Color(0xFF2D7100); // fondo medio  (topo c2)
const _kBgBase = Color(0xFF091500); // base más oscura (topo base)
const _kCardBg = Color(0xFF0E1611); // superficie de tarjeta oscura
const _kFieldBg = Color(0xFF16240C); // relleno de campos
const _kOnDark = Color(0xFFE7F2D8); // texto sobre oscuro
const _kMuted = Color(0xFF9FB58B); // texto secundario

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  int _step = 0; // 0: email | 1: código | 2: nueva contraseña
  String _verifiedEmail = '';
  AuthService? _authService;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final svc = await getAuthService();
    if (mounted) setState(() => _authService = svc);
  }

  // ── PASO 1: Solicitar código ────────────────────────────────────────────────
  Future<void> _requestCode() async {
    if (_authService == null || _isLoading) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnack('Ingresa tu correo electrónico', context.ez.warning);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService!.requestPasswordReset(email: email);
      if (!mounted) return;
      _verifiedEmail = email;
      setState(() => _step = 1);
      _showSnack('Código enviado a $email', context.ez.success);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), context.ez.danger);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PASO 2: Verificar código ────────────────────────────────────────────────
  Future<void> _verifyCode() async {
    if (_authService == null || _isLoading) return;
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _showSnack('El código debe tener 6 dígitos', context.ez.warning);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService!.verifyPasswordCode(
        email: _verifiedEmail,
        code: code,
      );
      if (!mounted) return;
      setState(() => _step = 2);
      _showSnack('Código verificado', context.ez.success);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), context.ez.danger);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PASO 3: Cambiar contraseña ──────────────────────────────────────────────
  Future<void> _resetPassword() async {
    if (_authService == null || _isLoading) return;
    final newPass = _newPassController.text;
    final confirmPass = _confirmPassController.text;
    if (newPass.length < 6) {
      _showSnack('La contraseña debe tener al menos 6 caracteres', context.ez.warning);
      return;
    }
    if (newPass != confirmPass) {
      _showSnack('Las contraseñas no coinciden', context.ez.warning);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _authService!.resetPassword(
        email: _verifiedEmail,
        code: _codeController.text.trim(),
        newPassword: newPass,
      );
      if (!mounted) return;
      _showSnack('Contraseña actualizada exitosamente', context.ez.success);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), context.ez.danger);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goBack() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TopoBackground(
        c1: _kBg1,
        c2: _kBg2,
        base: _kBgBase,
        count: 28,
        amp: 14,
        stroke: 0.45,
        speed: 0.55,
        child: SafeArea(
          child: Column(
            children: [
              // Barra superior con botón de retroceso
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      size: 20, color: _kOnDark),
                  onPressed: _goBack,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStepIndicator(),
                      const SizedBox(height: 32),
                      // Tarjeta oscura tipo "glass" con el contenido del paso
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: _kCardBg.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _kAccent.withValues(alpha: 0.22),
                          ),
                        ),
                        child: _buildStepContent(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Indicador de pasos ─────────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    const labels = ['Correo', 'Código', 'Contraseña'];
    return Row(
      children: List.generate(3, (i) {
        final done = _step > i;
        final active = _step == i;
        final on = done || active;
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: on ? _kAccent : _kFieldBg,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: on
                            ? _kAccent
                            : _kAccent.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Center(
                      child: done
                          ? const Icon(Icons.check,
                              color: Color(0xFF0C1506), size: 18)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: active
                                    ? const Color(0xFF0C1506)
                                    : _kMuted,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      color: on ? _kOnDark : _kMuted,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
              if (i < 2)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: _step > i
                        ? _kAccent
                        : _kAccent.withValues(alpha: 0.14),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // ── Contenido según paso ───────────────────────────────────────────────────
  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildEmailStep();
      case 1:
        return _buildCodeStep();
      case 2:
        return _buildPasswordStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Paso 1: Email ──────────────────────────────────────────────────────────
  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Recuperar Contraseña'),
        const SizedBox(height: 8),
        _subtitle('Ingresa tu correo y te enviaremos un código de 6 dígitos.'),
        const SizedBox(height: 28),
        _buildField(
          controller: _emailController,
          hint: 'correo@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),
        _buildButton('Enviar Código', _requestCode),
      ],
    );
  }

  // ── Paso 2: Código ─────────────────────────────────────────────────────────
  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Verificar Código'),
        const SizedBox(height: 8),
        _subtitle('Ingresa el código de 6 dígitos enviado a $_verifiedEmail'),
        const SizedBox(height: 28),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 10,
            color: _kOnDark,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: TextStyle(
              color: _kMuted.withValues(alpha: 0.5),
              fontSize: 28,
              letterSpacing: 10,
            ),
            filled: true,
            fillColor: _kFieldBg,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            border: _fieldBorder(),
            enabledBorder: _fieldBorder(),
            focusedBorder: _fieldBorder(focused: true),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    _emailController.clear();
                    _codeController.clear();
                    setState(() => _step = 0);
                  },
            child: const Text(
              'Usar otro correo',
              style: TextStyle(color: _kMuted, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildButton('Verificar Código', _verifyCode),
      ],
    );
  }

  // ── Paso 3: Nueva contraseña ───────────────────────────────────────────────
  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title('Nueva Contraseña'),
        const SizedBox(height: 8),
        _subtitle('Crea una contraseña segura de al menos 6 caracteres.'),
        const SizedBox(height: 28),
        _buildField(
          controller: _newPassController,
          hint: 'Nueva contraseña',
          obscure: _obscureNew,
          suffix: IconButton(
            icon: Icon(
              _obscureNew
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _kMuted,
              size: 20,
            ),
            onPressed: () => setState(() => _obscureNew = !_obscureNew),
          ),
        ),
        const SizedBox(height: 14),
        _buildField(
          controller: _confirmPassController,
          hint: 'Confirmar contraseña',
          obscure: _obscureConfirm,
          suffix: IconButton(
            icon: Icon(
              _obscureConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: _kMuted,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        const SizedBox(height: 28),
        _buildButton('Cambiar Contraseña', _resetPassword),
      ],
    );
  }

  // ── Helpers de UI ──────────────────────────────────────────────────────────
  Widget _title(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: _kOnDark,
        ),
      );

  Widget _subtitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, color: _kMuted),
      );

  OutlineInputBorder _fieldBorder({bool focused = false}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: focused
            ? const BorderSide(color: _kAccent, width: 1.5)
            : BorderSide(color: _kAccent.withValues(alpha: 0.18)),
      );

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
      style: const TextStyle(fontSize: 14, color: _kOnDark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kMuted, fontSize: 14),
        filled: true,
        fillColor: _kFieldBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: _fieldBorder(),
        enabledBorder: _fieldBorder(),
        focusedBorder: _fieldBorder(focused: true),
        suffixIcon: suffix,
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback action) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: (_isLoading || _authService == null) ? null : action,
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF0C1506)),
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
