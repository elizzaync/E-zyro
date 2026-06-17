import 'package:flutter/material.dart';

import '../models/usuario_admin_models.dart';
import '../services/usuarios_service.dart';
import '../utils/api_provider.dart';

/// Gestión de usuarios (Admin / permiso `usuarios:gestionar`):
/// listar, cambiar rol, activar/desactivar, resetear contraseña y crear cuentas
/// (con ficha de empleado opcional).
class PantallaGestionUsuarios extends StatefulWidget {
  const PantallaGestionUsuarios({super.key});

  @override
  State<PantallaGestionUsuarios> createState() => _PantallaGestionUsuariosState();
}

class _PantallaGestionUsuariosState extends State<PantallaGestionUsuarios> {
  static const _green = Color(0xFF8FD11B);

  UsuariosService? _svc;
  List<UsuarioAdmin> _usuarios = [];
  List<RolItem> _roles = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getUsuariosService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final us = await _svc!.listar();
    final rs = await _svc!.roles();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (us.ok) {
        _usuarios = us.data ?? [];
      } else {
        _error = us.errorMessage;
      }
      if (rs.ok) _roles = rs.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : _green));
  }

  // ── Acciones ──────────────────────────────────────────────────────────────
  Future<void> _acciones(UsuarioAdmin u) async {
    final accion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(u.nombreCompleto,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined, color: _green),
              title: const Text('Cambiar rol'),
              subtitle: Text(u.rol ?? 'Sin rol'),
              onTap: () => Navigator.pop(ctx, 'rol'),
            ),
            ListTile(
              leading: Icon(u.activo ? Icons.block : Icons.check_circle_outline,
                  color: u.activo ? Colors.red : _green),
              title: Text(u.activo ? 'Desactivar cuenta' : 'Activar cuenta'),
              onTap: () => Navigator.pop(ctx, 'activo'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset, color: Colors.orange),
              title: const Text('Restablecer contraseña'),
              onTap: () => Navigator.pop(ctx, 'password'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (accion == null || !mounted) return;
    switch (accion) {
      case 'rol':
        await _cambiarRol(u);
      case 'activo':
        await _cambiarActivo(u);
      case 'password':
        await _resetPassword(u);
    }
  }

  Future<void> _cambiarRol(UsuarioAdmin u) async {
    String? sel = u.rolId;
    final nuevoRolId = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: const Text('Cambiar rol'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _roles.map((r) {
              final selected = sel == r.id;
              return ListTile(
                title: Text(r.nombre),
                trailing: selected
                    ? const Icon(Icons.check_circle, color: _green)
                    : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                onTap: () => setLocal(() => sel = r.id),
              );
            }).toList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: sel == null ? null : () => Navigator.pop(ctx, sel),
              child: const Text('Guardar'),
            ),
          ],
        );
      }),
    );
    if (nuevoRolId == null || nuevoRolId == u.rolId) return;
    final r = await _svc!.cambiarRol(u.id, nuevoRolId);
    if (!mounted) return;
    if (r.ok) {
      _snack('Rol actualizado');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _cambiarActivo(UsuarioAdmin u) async {
    final r = await _svc!.cambiarActivo(u.id, !u.activo);
    if (!mounted) return;
    if (r.ok) {
      _snack(u.activo ? 'Cuenta desactivada' : 'Cuenta activada');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _resetPassword(UsuarioAdmin u) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer contraseña'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
              labelText: 'Nueva contraseña temporal', helperText: 'Mínimo 6 caracteres'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restablecer')),
        ],
      ),
    );
    if (ok != true) return;
    if (ctrl.text.trim().length < 6) {
      _snack('La contraseña debe tener al menos 6 caracteres', error: true);
      return;
    }
    final r = await _svc!.resetPassword(u.id, ctrl.text.trim());
    if (!mounted) return;
    _snack(r.ok ? 'Contraseña restablecida (el usuario deberá cambiarla)' : r.errorMessage,
        error: !r.ok);
  }

  Future<void> _crearUsuario() async {
    if (_roles.isEmpty) {
      _snack('No hay roles disponibles', error: true);
      return;
    }
    final creado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormCrearUsuario(svc: _svc!, roles: _roles),
    );
    if (creado == true) {
      _snack('Usuario creado');
      _cargar();
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de usuarios', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearUsuario,
        backgroundColor: _green,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Crear usuario'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: _green))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: _green,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: _usuarios.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = _usuarios[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (u.activo ? _green : Colors.grey).withValues(alpha: 0.15),
                          child: Text(
                            (u.nombre.isNotEmpty ? u.nombre[0] : '?').toUpperCase(),
                            style: TextStyle(
                                color: u.activo ? _green : Colors.grey,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(u.nombreCompleto,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: u.activo ? null : Colors.grey)),
                        subtitle: Text('@${u.username} · ${u.rol ?? "Sin rol"}'
                            '${u.tieneFicha ? "" : " · sin ficha"}'),
                        trailing: Wrap(
                          spacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (!u.activo)
                              const Chip(
                                label: Text('Inactivo', style: TextStyle(fontSize: 11)),
                                backgroundColor: Color(0x22FF5252),
                                side: BorderSide.none,
                                visualDensity: VisualDensity.compact,
                              ),
                            const Icon(Icons.more_vert),
                          ],
                        ),
                        onTap: () => _acciones(u),
                      );
                    },
                  ),
                ),
    );
  }
}

// ─── Formulario de creación ──────────────────────────────────────────────────
class _FormCrearUsuario extends StatefulWidget {
  final UsuariosService svc;
  final List<RolItem> roles;
  const _FormCrearUsuario({required this.svc, required this.roles});

  @override
  State<_FormCrearUsuario> createState() => _FormCrearUsuarioState();
}

class _FormCrearUsuarioState extends State<_FormCrearUsuario> {
  static const _green = Color(0xFF8FD11B);
  final _formKey = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _cargo = TextEditingController();
  final _area = TextEditingController();
  String? _rolId;
  bool _crearFicha = false;
  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _apellido.dispose();
    _email.dispose();
    _username.dispose();
    _password.dispose();
    _cargo.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_rolId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Selecciona un rol')));
      return;
    }
    setState(() => _guardando = true);
    final r = await widget.svc.crear(
      nombre: _nombre.text.trim(),
      apellido: _apellido.text.trim(),
      email: _email.text.trim(),
      username: _username.text.trim(),
      password: _password.text,
      rolId: _rolId!,
      crearFicha: _crearFicha,
      cargo: _crearFicha ? _cargo.text.trim() : null,
      area: _crearFicha && _area.text.trim().isNotEmpty ? _area.text.trim() : null,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.errorMessage), backgroundColor: Colors.red.shade700));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Crear usuario',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _field(_nombre, 'Nombre', required: true)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(_apellido, 'Apellido', required: true)),
                ]),
                const SizedBox(height: 12),
                _field(_email, 'Correo', keyboard: TextInputType.emailAddress, required: true),
                const SizedBox(height: 12),
                _field(_username, 'Usuario (para login)', required: true),
                const SizedBox(height: 12),
                _field(_password, 'Contraseña temporal', required: true,
                    helper: 'Mínimo 6 caracteres. El usuario deberá cambiarla.'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _rolId,
                  decoration: const InputDecoration(
                      labelText: 'Rol', border: OutlineInputBorder()),
                  items: widget.roles
                      .map((r) => DropdownMenuItem(value: r.id, child: Text(r.nombre)))
                      .toList(),
                  onChanged: (v) => setState(() => _rolId = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _crearFicha,
                  activeThumbColor: _green,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Crear ficha de empleado'),
                  subtitle: const Text('Necesaria para asistencia, vacaciones, etc.'),
                  onChanged: (v) => setState(() => _crearFicha = v),
                ),
                if (_crearFicha) ...[
                  _field(_cargo, 'Cargo', required: true),
                  const SizedBox(height: 12),
                  _field(_area, 'Área (opcional)'),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : const Text('Crear usuario'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false, TextInputType? keyboard, String? helper}) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(
          labelText: label, helperText: helper, border: const OutlineInputBorder()),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null
          : null,
    );
  }
}
