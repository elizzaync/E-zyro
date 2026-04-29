import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

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
  ApiService? _apiService;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  Future<void> _initService() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _apiService = ApiService(prefs));
  }

  // ── PASO 1: Solicitar código ────────────────────────────────────────────────
  Future<void> _requestCode() async {
    if (_apiService == null || _isLoading) return;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showSnack('Ingresa tu correo electrónico', Colors.orange);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _apiService!.requestPasswordReset(email: email);
      if (!mounted) return;
      _verifiedEmail = email;
      setState(() => _step = 1);
      _showSnack('Código enviado a $email', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PASO 2: Verificar código ────────────────────────────────────────────────
  Future<void> _verifyCode() async {
    if (_apiService == null || _isLoading) return;
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _showSnack('El código debe tener 6 dígitos', Colors.orange);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _apiService!.verifyPasswordCode(
        email: _verifiedEmail,
        code: code,
      );
      if (!mounted) return;
      setState(() => _step = 2);
      _showSnack('Código verificado', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PASO 3: Cambiar contraseña ──────────────────────────────────────────────
  Future<void> _resetPassword() async {
    if (_apiService == null || _isLoading) return;
    final newPass = _newPassController.text;
    final confirmPass = _confirmPassController.text;
    if (newPass.length < 6) {
      _showSnack('La contraseña debe tener al menos 6 caracteres', Colors.orange);
      return;
    }
    if (newPass != confirmPass) {
      _showSnack('Las contraseñas no coinciden', Colors.orange);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await _apiService!.resetPassword(
        email: _verifiedEmail,
        code: _codeController.text.trim(),
        newPassword: newPass,
      );
      if (!mounted) return;
      _showSnack('Contraseña actualizada exitosamente', Colors.green);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceAll('Exception: ', ''), Colors.red);
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
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F2F2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              _buildStepIndicator(),
              const SizedBox(height: 36),
              _buildStepContent(),
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
        return Expanded(
          child: Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (done || active)
                          ? const Color(0xFF8FD11B)
                          : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: done
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: active ? Colors.white : Colors.grey,
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
                      color: (done || active) ? Colors.black87 : Colors.grey,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.normal,
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
                        ? const Color(0xFF8FD11B)
                        : Colors.grey.shade200,
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
        const Text(
          'Recuperar Contraseña',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ingresa tu correo y te enviaremos un código de 6 dígitos.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 32),
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
        const Text(
          'Verificar Código',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ingresa el código de 6 dígitos enviado a $_verifiedEmail',
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: 10,
            color: Colors.black87,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: TextStyle(
              color: Colors.grey.shade300,
              fontSize: 28,
              letterSpacing: 10,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
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
              borderSide:
                  const BorderSide(color: Color(0xFF8FD11B), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildButton('Verificar Código', _verifyCode),
      ],
    );
  }

  // ── Paso 3: Nueva contraseña ───────────────────────────────────────────────
  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nueva Contraseña',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Crea una contraseña segura de al menos 6 caracteres.',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 32),
        _buildField(
          controller: _newPassController,
          hint: 'Nueva contraseña',
          obscure: _obscureNew,
          suffix: IconButton(
            icon: Icon(
              _obscureNew
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: Colors.grey.shade400,
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
              color: Colors.grey.shade400,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
        ),
        const SizedBox(height: 32),
        _buildButton('Cambiar Contraseña', _resetPassword),
      ],
    );
  }

  // ── Helpers de UI ──────────────────────────────────────────────────────────
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
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

  Widget _buildButton(String label, VoidCallback action) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: (_isLoading || _apiService == null) ? null : action,
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
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
