import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../services/auth_service.dart';

const _kGreen  = Color(0xFF1E9462);
const _kGreenL = Color(0xFF8FD11B);

// ─── Modelos ──────────────────────────────────────────────────────────────────

class _Usuario {
  final String id, nombre, apellido, username;
  final String? rol;
  final bool activo;
  int permisosDirectos;

  _Usuario({
    required this.id,
    required this.nombre,
    required this.apellido,
    required this.username,
    this.rol,
    required this.activo,
    required this.permisosDirectos,
  });

  String get nombreCompleto => '$nombre $apellido';

  factory _Usuario.fromJson(Map<String, dynamic> j) => _Usuario(
        id: j['id'] as String,
        nombre: j['nombre'] as String,
        apellido: j['apellido'] as String,
        username: j['username'] as String,
        rol: j['rol'] as String?,
        activo: j['activo'] as bool? ?? true,
        permisosDirectos: j['permisos_directos'] as int? ?? 0,
      );
}

class _Permiso {
  final String id, modulo, accion;
  final String? descripcion;
  bool viaRol;
  bool directo;

  _Permiso({
    required this.id,
    required this.modulo,
    required this.accion,
    this.descripcion,
    required this.viaRol,
    required this.directo,
  });

  bool get activo => viaRol || directo;

  factory _Permiso.fromJson(Map<String, dynamic> j) => _Permiso(
        id: j['id'] as String,
        modulo: j['modulo'] as String,
        accion: j['accion'] as String,
        descripcion: j['descripcion'] as String?,
        viaRol: j['via_rol'] as bool? ?? false,
        directo: j['directo'] as bool? ?? false,
      );
}

// ─── Pantalla ─────────────────────────────────────────────────────────────────

class PantallaPrivilegios extends StatefulWidget {
  const PantallaPrivilegios({super.key});

  @override
  State<PantallaPrivilegios> createState() => _PantallaPrivilegiosState();
}

class _PantallaPrivilegiosState extends State<PantallaPrivilegios> {
  ApiClient? _api;
  bool _cargandoUsuarios = true;
  List<_Usuario> _usuarios = [];
  List<_Usuario> _filtrados = [];
  String _busqueda = '';
  _Usuario? _seleccionado;

  bool _cargandoPermisos = false;
  Map<String, List<_Permiso>> _porModulo = {};
  final Set<String> _modulosExpandidos = {};
  final Set<String> _guardando = {};
  bool _bulkLoading = false;

  @override
  void initState() {
    super.initState();
    _initApi();
  }

  Future<void> _initApi() async {
    final prefs = await SharedPreferences.getInstance();
    _api = ApiClient(prefs);
    _cargarUsuarios();
  }

  Future<void> _cargarUsuarios() async {
    if (_api == null) return;
    setState(() => _cargandoUsuarios = true);
    try {
      final r = await _api!.get('/privilegios/usuarios');
      if (!mounted) return;
      if (r.statusCode == 200) {
        final list = (jsonDecode(r.body) as List)
            .map((j) => _Usuario.fromJson(j as Map<String, dynamic>))
            .toList();
        setState(() {
          _usuarios = list;
          _filtrados = list;
          _cargandoUsuarios = false;
        });
      } else {
        setState(() => _cargandoUsuarios = false);
        _snack('Error al cargar usuarios (${r.statusCode})', Colors.red);
      }
    } catch (e) {
      if (mounted) setState(() => _cargandoUsuarios = false);
      _snack('Error de red', Colors.red);
    }
  }

  void _filtrar(String q) {
    setState(() {
      _busqueda = q;
      final lower = q.toLowerCase();
      _filtrados = q.isEmpty
          ? _usuarios
          : _usuarios
              .where((u) =>
                  u.nombreCompleto.toLowerCase().contains(lower) ||
                  u.username.toLowerCase().contains(lower) ||
                  (u.rol ?? '').toLowerCase().contains(lower))
              .toList();
    });
  }

  Future<void> _seleccionarUsuario(_Usuario u) async {
    if (_api == null) return;
    setState(() {
      _seleccionado = u;
      _cargandoPermisos = true;
      _porModulo = {};
      _modulosExpandidos.clear();
    });
    try {
      final r = await _api!.get('/privilegios/usuarios/${u.id}/permisos');
      if (!mounted) return;
      if (r.statusCode == 200) {
        final list = (jsonDecode(r.body) as List)
            .map((j) => _Permiso.fromJson(j as Map<String, dynamic>))
            .toList();
        final mapa = <String, List<_Permiso>>{};
        for (final p in list) {
          (mapa[p.modulo] ??= []).add(p);
        }
        setState(() {
          _porModulo = mapa;
          _cargandoPermisos = false;
        });
      } else {
        setState(() => _cargandoPermisos = false);
      }
    } catch (_) {
      if (mounted) setState(() => _cargandoPermisos = false);
    }
  }

  Future<void> _togglePermiso(_Permiso p, bool nuevoValor) async {
    if (p.viaRol || _seleccionado == null || _guardando.contains(p.id)) return;
    setState(() => _guardando.add(p.id));
    final uid = _seleccionado!.id;
    try {
      if (nuevoValor) {
        final r = await _api!.post(
          '/privilegios/usuarios/$uid/permisos',
          {'permiso_id': p.id},
        );
        if (r.statusCode == 200 && mounted) {
          setState(() {
            p.directo = true;
            _seleccionado!.permisosDirectos++;
            final idx = _usuarios.indexWhere((u) => u.id == uid);
            if (idx >= 0) _usuarios[idx].permisosDirectos++;
          });
        }
      } else {
        final r = await _api!.delete('/privilegios/usuarios/$uid/permisos/${p.id}');
        if (r.statusCode == 200 && mounted) {
          setState(() {
            p.directo = false;
            if (_seleccionado!.permisosDirectos > 0) {
              _seleccionado!.permisosDirectos--;
            }
            final idx = _usuarios.indexWhere((u) => u.id == uid);
            if (idx >= 0 && _usuarios[idx].permisosDirectos > 0) {
              _usuarios[idx].permisosDirectos--;
            }
          });
        }
      }
      // Si el usuario afectado es el que está logueado, refresca su propia
      // sesión para que el cambio se vea al instante sin re-login.
      await refrescarPermisosGlobal();
    } catch (_) {
      if (mounted) {
        _snack('Sin conexión. El cambio no se aplicó.', Colors.orange);
      }
    } finally {
      if (mounted) setState(() => _guardando.remove(p.id));
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<bool> _confirmar(String titulo, String mensaje) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensaje, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _activarTodos() async {
    final u = _seleccionado;
    if (u == null || _api == null) return;
    final ok = await _confirmar(
      'Activar todos los privilegios',
      'Se asignarán directamente todos los permisos del catálogo a ${u.nombreCompleto}.\n\n'
      'Nota: los endpoints que exigen exclusivamente rol Administrador '
      'seguirán bloqueados.',
    );
    if (!ok || !mounted) return;
    setState(() => _bulkLoading = true);
    try {
      final r = await _api!.post('/privilegios/usuarios/${u.id}/permisos/todos', {});
      if (!mounted) return;
      if (r.statusCode == 200) {
        await _seleccionarUsuario(u);
        await refrescarPermisosGlobal();
        _snack('Todos los privilegios activados', _kGreen);
      } else {
        _snack('Error al activar privilegios (${r.statusCode})', Colors.red);
      }
    } catch (_) {
      _snack('Sin conexión', Colors.orange);
    } finally {
      if (mounted) setState(() => _bulkLoading = false);
    }
  }

  Future<void> _restablecerAlRol() async {
    final u = _seleccionado;
    if (u == null || _api == null) return;
    final ok = await _confirmar(
      'Restablecer al rol',
      'Se eliminarán todos los privilegios directos de ${u.nombreCompleto}.\n\n'
      'Solo conservará los permisos de su rol actual (${u.rol ?? 'sin rol'}).',
    );
    if (!ok || !mounted) return;
    setState(() => _bulkLoading = true);
    try {
      final r = await _api!.delete('/privilegios/usuarios/${u.id}/permisos');
      if (!mounted) return;
      if (r.statusCode == 200) {
        await _seleccionarUsuario(u);
        await refrescarPermisosGlobal();
        _snack('Privilegios restablecidos al rol', Colors.orange);
      } else {
        _snack('Error al restablecer (${r.statusCode})', Colors.red);
      }
    } catch (_) {
      _snack('Sin conexión', Colors.orange);
    } finally {
      if (mounted) setState(() => _bulkLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privilegios de Usuario'),
        actions: [
          IconButton(
            tooltip: 'Actualizar lista',
            icon: const Icon(Icons.refresh),
            onPressed: _cargarUsuarios,
          ),
        ],
      ),
      body: LayoutBuilder(builder: (_, c) {
        final sideBySide = c.maxWidth > 640;
        final panelUsuarios = _PanelUsuarios(
          cargando: _cargandoUsuarios,
          filtrados: _filtrados,
          seleccionado: _seleccionado,
          busqueda: _busqueda,
          onBuscar: _filtrar,
          onSeleccionar: sideBySide
              ? _seleccionarUsuario
              : (u) async {
                  await _seleccionarUsuario(u);
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PantallaDetalle(
                        usuario: u,
                        cargando: _cargandoPermisos,
                        porModulo: _porModulo,
                        modulosExpandidos: _modulosExpandidos,
                        guardando: _guardando,
                        bulkLoading: _bulkLoading,
                        onExpandir: (m) => setState(() =>
                            _modulosExpandidos.contains(m)
                                ? _modulosExpandidos.remove(m)
                                : _modulosExpandidos.add(m)),
                        onToggle: _togglePermiso,
                        onActivarTodos: _activarTodos,
                        onRestablecerAlRol: _restablecerAlRol,
                        isDark: isDark,
                      ),
                    ),
                  );
                },
          isDark: isDark,
        );

        if (!sideBySide) return panelUsuarios;

        return Row(children: [
          SizedBox(width: 288, child: panelUsuarios),
          VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
          Expanded(
            child: _PanelPermisos(
              usuario: _seleccionado,
              cargando: _cargandoPermisos,
              porModulo: _porModulo,
              modulosExpandidos: _modulosExpandidos,
              guardando: _guardando,
              bulkLoading: _bulkLoading,
              onExpandir: (m) => setState(() => _modulosExpandidos.contains(m)
                  ? _modulosExpandidos.remove(m)
                  : _modulosExpandidos.add(m)),
              onToggle: _togglePermiso,
              onActivarTodos: _seleccionado != null ? _activarTodos : null,
              onRestablecerAlRol: _seleccionado != null ? _restablecerAlRol : null,
              isDark: isDark,
            ),
          ),
        ]);
      }),
    );
  }
}

// ─── Panel de usuarios ────────────────────────────────────────────────────────

class _PanelUsuarios extends StatelessWidget {
  const _PanelUsuarios({
    required this.cargando,
    required this.filtrados,
    required this.seleccionado,
    required this.busqueda,
    required this.onBuscar,
    required this.onSeleccionar,
    required this.isDark,
  });

  final bool cargando;
  final List<_Usuario> filtrados;
  final _Usuario? seleccionado;
  final String busqueda;
  final ValueChanged<String> onBuscar;
  final ValueChanged<_Usuario> onSeleccionar;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: TextField(
          onChanged: onBuscar,
          decoration: InputDecoration(
            hintText: 'Buscar usuario…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: isDark ? Colors.white10 : Colors.grey.shade100,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
      ),
      if (cargando)
        const Expanded(
          child: Center(
            child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_kGreen)),
          ),
        )
      else
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: filtrados.length,
            itemBuilder: (_, i) => _UserTile(
              usuario: filtrados[i],
              selected: seleccionado?.id == filtrados[i].id,
              onTap: () => onSeleccionar(filtrados[i]),
              isDark: isDark,
            ),
          ),
        ),
    ]);
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.usuario,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  final _Usuario usuario;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: selected
            ? _kGreen.withValues(alpha: isDark ? 0.18 : 0.09)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          _Avatar(usuario: usuario, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    usuario.nombreCompleto,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!usuario.activo)
                  _MiniChip('inactivo', Colors.grey),
              ]),
              const SizedBox(height: 2),
              Text(
                usuario.rol ?? 'Sin rol',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (usuario.permisosDirectos > 0) ...[
            const SizedBox(width: 6),
            _MiniChip('+${usuario.permisosDirectos}', _kGreen),
          ],
          if (selected) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: _kGreen),
          ],
        ]),
      ),
    );
  }
}

// ─── Panel de permisos ────────────────────────────────────────────────────────

class _PanelPermisos extends StatelessWidget {
  const _PanelPermisos({
    required this.usuario,
    required this.cargando,
    required this.porModulo,
    required this.modulosExpandidos,
    required this.guardando,
    required this.bulkLoading,
    required this.onExpandir,
    required this.onToggle,
    this.onActivarTodos,
    this.onRestablecerAlRol,
    required this.isDark,
  });

  final _Usuario? usuario;
  final bool cargando;
  final Map<String, List<_Permiso>> porModulo;
  final Set<String> modulosExpandidos;
  final Set<String> guardando;
  final bool bulkLoading;
  final ValueChanged<String> onExpandir;
  final Future<void> Function(_Permiso, bool) onToggle;
  final VoidCallback? onActivarTodos;
  final VoidCallback? onRestablecerAlRol;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (usuario == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.manage_accounts_outlined,
              size: 60,
              color: Colors.grey.withValues(alpha: 0.35)),
          const SizedBox(height: 14),
          const Text(
            'Selecciona un usuario\npara gestionar sus privilegios',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.55),
          ),
        ]),
      );
    }
    if (cargando) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen)),
      );
    }
    final modulos = porModulo.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UsuarioHeader(
          usuario: usuario!,
          bulkLoading: bulkLoading,
          onActivarTodos: onActivarTodos,
          onRestablecerAlRol: onRestablecerAlRol,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            itemCount: modulos.length,
            itemBuilder: (_, i) {
              final mod = modulos[i];
              final permisos = porModulo[mod]!;
              return _ModuloCard(
                modulo: mod,
                permisos: permisos,
                expandido: modulosExpandidos.contains(mod),
                guardando: guardando,
                onExpandir: () => onExpandir(mod),
                onToggle: onToggle,
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _UsuarioHeader extends StatelessWidget {
  const _UsuarioHeader({
    required this.usuario,
    this.bulkLoading = false,
    this.onActivarTodos,
    this.onRestablecerAlRol,
  });

  final _Usuario usuario;
  final bool bulkLoading;
  final VoidCallback? onActivarTodos;
  final VoidCallback? onRestablecerAlRol;

  @override
  Widget build(BuildContext context) {
    final d = usuario.permisosDirectos;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _Avatar(usuario: usuario, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(usuario.nombreCompleto,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('@${usuario.username} · ${usuario.rol ?? 'Sin rol'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
            if (d > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _kGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kGreen.withValues(alpha: 0.35)),
                ),
                child: Text(
                  '$d privilegio${d == 1 ? '' : 's'} extra',
                  style: const TextStyle(
                      fontSize: 11, color: _kGreen, fontWeight: FontWeight.w700),
                ),
              ),
          ]),
          if (onActivarTodos != null || onRestablecerAlRol != null) ...[
            const SizedBox(height: 10),
            Row(children: [
              if (onActivarTodos != null)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: bulkLoading ? null : onActivarTodos,
                    icon: bulkLoading
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.select_all, size: 16),
                    label: const Text('Activar todos', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: _kGreen,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (onActivarTodos != null && onRestablecerAlRol != null)
                const SizedBox(width: 8),
              if (onRestablecerAlRol != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: bulkLoading ? null : onRestablecerAlRol,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: const Text('Solo por rol', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _ModuloCard extends StatelessWidget {
  const _ModuloCard({
    required this.modulo,
    required this.permisos,
    required this.expandido,
    required this.guardando,
    required this.onExpandir,
    required this.onToggle,
    required this.isDark,
  });

  final String modulo;
  final List<_Permiso> permisos;
  final bool expandido;
  final Set<String> guardando;
  final VoidCallback onExpandir;
  final Future<void> Function(_Permiso, bool) onToggle;
  final bool isDark;

  static const _iconos = <String, IconData>{
    'asistencia': Icons.fingerprint_outlined,
    'auditoria': Icons.manage_search_rounded,
    'calibracion': Icons.straighten_outlined,
    'catalogos': Icons.category_outlined,
    'caja_chica': Icons.money_outlined,
    'clientes': Icons.people_outline,
    'comunicados': Icons.campaign_outlined,
    'conciliacion_bancaria': Icons.account_balance_outlined,
    'contabilidad': Icons.receipt_long_outlined,
    'controlling': Icons.tune_outlined,
    'correctivo': Icons.build_outlined,
    'cxc': Icons.arrow_circle_up_outlined,
    'cxp': Icons.arrow_circle_down_outlined,
    'dashboard': Icons.insights_outlined,
    'documentos_sst': Icons.verified_outlined,
    'empleados': Icons.badge_outlined,
    'epp': Icons.shield_outlined,
    'equipo': Icons.precision_manufacturing_outlined,
    'equipo_intervenido': Icons.build_circle_outlined,
    'evaluacion': Icons.star_outline,
    'galeria': Icons.photo_library_outlined,
    'informe_servicio': Icons.description_outlined,
    'inventario': Icons.inventory_2_outlined,
    'inventario_valorizado': Icons.price_check_outlined,
    'itse': Icons.fact_check_outlined,
    'observacion': Icons.visibility_outlined,
    'planilla': Icons.payments_outlined,
    'planos': Icons.architecture_outlined,
    'prestamo': Icons.handshake_outlined,
    'privilegios': Icons.admin_panel_settings_outlined,
    'proyectos': Icons.folder_special_outlined,
    'requerimientos': Icons.shopping_cart_outlined,
    'reportes': Icons.bar_chart_outlined,
    'soporte': Icons.support_agent_outlined,
    'tributario': Icons.account_balance_wallet_outlined,
    'usuarios': Icons.manage_accounts_outlined,
    'vacaciones': Icons.beach_access_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final icono = _iconos[modulo] ?? Icons.extension_outlined;
    final directos = permisos.where((p) => p.directo).length;
    final viaRol = permisos.where((p) => p.viaRol && !p.directo).length;
    final tieneAlgo = directos > 0 || viaRol > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: directos > 0
              ? _kGreen.withValues(alpha: 0.35)
              : Colors.grey.withValues(alpha: isDark ? 0.12 : 0.14),
        ),
      ),
      child: Column(children: [
        // Cabecera del módulo
        InkWell(
          borderRadius: expandido
              ? const BorderRadius.vertical(top: Radius.circular(12))
              : BorderRadius.circular(12),
          onTap: onExpandir,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: tieneAlgo
                      ? _kGreen.withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono,
                    size: 17,
                    color: tieneAlgo ? _kGreen : Colors.grey),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                    modulo,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: tieneAlgo
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  if (viaRol > 0 || directos > 0)
                    Row(children: [
                      if (viaRol > 0)
                        _MiniChip('$viaRol por rol', Colors.blue),
                      if (viaRol > 0 && directos > 0)
                        const SizedBox(width: 4),
                      if (directos > 0)
                        _MiniChip('+$directos extra', _kGreen),
                    ]),
                ]),
              ),
              AnimatedRotation(
                turns: expandido ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.expand_more,
                    size: 20, color: Colors.grey),
              ),
            ]),
          ),
        ),
        // Permisos expandidos
        if (expandido)
          Column(children: [
            const Divider(height: 1, indent: 12, endIndent: 12),
            ...permisos.map((p) => _PermisoRow(
                  permiso: p,
                  guardando: guardando.contains(p.id),
                  onToggle: (v) => onToggle(p, v),
                  isDark: isDark,
                )),
            const SizedBox(height: 4),
          ]),
      ]),
    );
  }
}

class _PermisoRow extends StatelessWidget {
  const _PermisoRow({
    required this.permiso,
    required this.guardando,
    required this.onToggle,
    required this.isDark,
  });

  final _Permiso permiso;
  final bool guardando;
  final ValueChanged<bool> onToggle;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final activo = permiso.activo;
    final bloqueado = permiso.viaRol;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(children: [
        // dot de estado
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: activo
                ? (permiso.directo ? _kGreenL : Colors.blue.shade300)
                : Colors.grey.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(
              permiso.accion,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    activo ? FontWeight.w600 : FontWeight.normal,
                color: activo ? null : Colors.grey,
              ),
            ),
            if (permiso.descripcion != null &&
                permiso.descripcion!.isNotEmpty)
              Text(
                permiso.descripcion!,
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ]),
        ),
        if (permiso.viaRol) ...[
          _MiniChip('rol', Colors.blue),
          const SizedBox(width: 6),
        ],
        guardando
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(_kGreen)),
              )
            : Switch(
                value: activo,
                onChanged: bloqueado ? null : onToggle,
                activeColor: _kGreenL,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
      ]),
    );
  }
}

// ─── Pantalla de detalle para móvil ──────────────────────────────────────────

class _PantallaDetalle extends StatefulWidget {
  const _PantallaDetalle({
    required this.usuario,
    required this.cargando,
    required this.porModulo,
    required this.modulosExpandidos,
    required this.guardando,
    required this.bulkLoading,
    required this.onExpandir,
    required this.onToggle,
    required this.onActivarTodos,
    required this.onRestablecerAlRol,
    required this.isDark,
  });

  final _Usuario usuario;
  final bool cargando;
  final Map<String, List<_Permiso>> porModulo;
  final Set<String> modulosExpandidos;
  final Set<String> guardando;
  final bool bulkLoading;
  final ValueChanged<String> onExpandir;
  final Future<void> Function(_Permiso, bool) onToggle;
  final VoidCallback onActivarTodos;
  final VoidCallback onRestablecerAlRol;
  final bool isDark;

  @override
  State<_PantallaDetalle> createState() => _PantallaDetalleState();
}

class _PantallaDetalleState extends State<_PantallaDetalle> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.usuario.nombreCompleto)),
      body: _PanelPermisos(
        usuario: widget.usuario,
        cargando: widget.cargando,
        porModulo: widget.porModulo,
        modulosExpandidos: widget.modulosExpandidos,
        guardando: widget.guardando,
        bulkLoading: widget.bulkLoading,
        onExpandir: (m) {
          widget.onExpandir(m);
          setState(() {});
        },
        onToggle: (p, v) async {
          await widget.onToggle(p, v);
          if (mounted) setState(() {});
        },
        onActivarTodos: widget.onActivarTodos,
        onRestablecerAlRol: widget.onRestablecerAlRol,
        isDark: widget.isDark,
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({required this.usuario, required this.size});
  final _Usuario usuario;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initials =
        '${usuario.nombre.isNotEmpty ? usuario.nombre[0] : ''}${usuario.apellido.isNotEmpty ? usuario.apellido[0] : ''}'
            .toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _kGreen.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: _kGreen,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600)),
      );
}
