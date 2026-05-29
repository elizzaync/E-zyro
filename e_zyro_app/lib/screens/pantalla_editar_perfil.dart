import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _rolCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _fotoUrl = '';
  bool _isSaving = false;
  bool _isLoading = true;

  static const _green = Color(0xFF8FD11B);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rolCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameCtrl.text = prefs.getString('user_name') ?? '';
        _rolCtrl.text = prefs.getString('user_rol') ?? '';
        _emailCtrl.text = prefs.getString('user_email') ?? '';
        _phoneCtrl.text = prefs.getString('user_phone') ?? '';
        _fotoUrl = prefs.getString('user_foto_url') ?? '';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('user_name', _nameCtrl.text.trim()),
      // user_rol NO se persiste aquí: es autoritativo del login y determina los
      // permisos (logística, etc.). Sobreescribirlo desde un campo de texto
      // corrompería el RBAC local.
      prefs.setString('user_email', _emailCtrl.text.trim()),
      prefs.setString('user_phone', _phoneCtrl.text.trim()),
    ]);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Perfil actualizado correctamente'),
      backgroundColor: _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    BoxDecoration cardDeco() => BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: isDark ? Border.all(color: _green.withValues(alpha: 0.35)) : null,
          boxShadow: isDark
              ? [BoxShadow(color: _green.withValues(alpha: 0.08), blurRadius: 10)]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar Perfil', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isSaving || _isLoading ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(_green),
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(color: _green, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Avatar ────────────────────────────────────────────────
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: isDark ? _green.withValues(alpha: 0.12) : const Color(0xFFEFFAE0),
                                shape: BoxShape.circle,
                                border: Border.all(color: _green, width: 2.5),
                              ),
                              child: ClipOval(
                                child: _fotoUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: _fotoUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: (context, error, _) =>
                                            const Icon(Icons.person, size: 50, color: _green),
                                      )
                                    : const Icon(Icons.person, size: 50, color: _green),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: const Text('Edición de foto disponible próximamente'),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                )),
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: _green,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Información Personal ──────────────────────────────────
                      const _SectionLabel('INFORMACIÓN PERSONAL'),
                      const SizedBox(height: 10),
                      Container(
                        decoration: cardDeco(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Column(
                          children: [
                            _ProfileField(
                              controller: _nameCtrl,
                              label: 'Nombre completo',
                              icon: Icons.person_outline,
                              validator: (v) =>
                                  (v == null || v.trim().isEmpty) ? 'El nombre es requerido' : null,
                            ),
                            const SizedBox(height: 14),
                            _ProfileField(
                              controller: _rolCtrl,
                              label: 'Cargo / Rol',
                              icon: Icons.work_outline,
                              readOnly: true, // El rol es autoritativo del servidor
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Contacto ──────────────────────────────────────────────
                      const _SectionLabel('CONTACTO'),
                      const SizedBox(height: 10),
                      Container(
                        decoration: cardDeco(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Column(
                          children: [
                            _ProfileField(
                              controller: _emailCtrl,
                              label: 'Correo electrónico',
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 14),
                            _ProfileField(
                              controller: _phoneCtrl,
                              label: 'Teléfono',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Seguridad ─────────────────────────────────────────────
                      const _SectionLabel('SEGURIDAD'),
                      const SizedBox(height: 10),
                      Container(
                        decoration: cardDeco(),
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? _green.withValues(alpha: 0.12) : const Color(0xFFEFFAE0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.lock_outline, color: _green, size: 20),
                          ),
                          title: const Text(
                            'Cambiar Contraseña',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          subtitle: const Text(
                            'Actualizar credenciales de acceso',
                            style: TextStyle(fontSize: 11),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const _ChangePasswordSheet(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ── Botón Guardar ─────────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _green.withValues(alpha: 0.5),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _isSaving
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text('Guardando...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                  ],
                                )
                              : const Text(
                                  'Guardar Cambios',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Etiqueta de sección ───────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
          letterSpacing: 0.8,
        ),
      );
}

// ── Campo de formulario ───────────────────────────────────────────────────────
class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool readOnly;

  const _ProfileField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.validator,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF8FD11B);
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      enableInteractiveSelection: !readOnly,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: green),
        filled: true,
        fillColor: isDark ? green.withValues(alpha: 0.04) : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? green.withValues(alpha: 0.2) : Colors.grey.shade200,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? green.withValues(alpha: 0.2) : Colors.grey.shade200,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: green, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}

// ── Sheet: Cambiar contraseña ─────────────────────────────────────────────────
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? green.withValues(alpha: 0.12) : const Color(0xFFEFFAE0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.lock_outline, color: green, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cambiar Contraseña',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Ingresa tu contraseña actual y la nueva',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _pwField(context, 'Contraseña actual', _currentCtrl, _showCurrent,
                  () => setState(() => _showCurrent = !_showCurrent)),
              const SizedBox(height: 12),
              _pwField(context, 'Nueva contraseña', _newCtrl, _showNew,
                  () => setState(() => _showNew = !_showNew)),
              const SizedBox(height: 12),
              _pwField(context, 'Confirmar contraseña', _confirmCtrl, _showConfirm,
                  () => setState(() => _showConfirm = !_showConfirm)),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Cambio de contraseña disponible próximamente'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Actualizar Contraseña',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pwField(
    BuildContext context,
    String label,
    TextEditingController ctrl,
    bool show,
    VoidCallback toggle,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF8FD11B);
    return TextField(
      controller: ctrl,
      obscureText: !show,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline, size: 20, color: green),
        suffixIcon: IconButton(
          icon: Icon(
            show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
            color: Colors.grey,
          ),
          onPressed: toggle,
        ),
        filled: true,
        fillColor: isDark ? green.withValues(alpha: 0.04) : Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? green.withValues(alpha: 0.2) : Colors.grey.shade200,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? green.withValues(alpha: 0.2) : Colors.grey.shade200,
          ),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: green, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
