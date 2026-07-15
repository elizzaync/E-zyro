import 'package:e_zyro_app/screens/pantalla_tramites.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_session.dart';
import '../utils/app_notifiers.dart';
import '../widgets/topo_background.dart';
import 'pantalla_accesos_portal.dart';
import 'pantalla_gestion_usuarios.dart';
import 'pantalla_drive.dart';
import 'pantalla_auditoria.dart';
import 'pantalla_auditoria_general.dart';
import 'pantalla_comunicados.dart';
import 'pantalla_privacidad_seguridad.dart';
import 'pantalla_configuracion.dart';
import 'pantalla_centro_ayuda.dart';
import 'pantalla_personal_hub.dart';
import 'pantalla_mi_espacio.dart';
import 'pantalla_editar_perfil.dart';
import 'pantalla_galeria.dart';
import 'pantalla_calibraciones.dart';
import 'pantalla_garantias_correctivos.dart';
import 'pantalla_itse.dart';
import 'pantalla_catalogos.dart';
import 'pantalla_plantillas_procedimiento.dart';
import 'pantalla_equipos_intervenidos.dart';
import 'pantalla_dashboards.dart';
import 'pantalla_planos.dart';
import 'finanzas/pantalla_finanzas.dart';
import 'pantalla_documentos_sst.dart';
import 'pantalla_privilegios.dart';
import 'pantalla_pendientes.dart';
import 'pantalla_cotizaciones.dart';
import 'logistica/almacen/pantalla_requerimientos_logistica.dart';
import 'pantalla_cuadrilla_campo.dart';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _userName = '';
  String _userRol = '';
  String _fotoUrl = '';
  bool _puedeVerAuditoria = false;
  bool _esAdmin = false;
  bool _esSuperAdmin = false;
  bool _puedeVerPersonal = false;
  bool _puedeVerDashboards = false;
  bool _puedeVerControlAsistencias = false;
  bool _puedeGestionarUsuarios = false;
  bool _puedeGestionarPrivilegios = false;
  // Visibilidad de módulos por permiso (admin ve todos).
  bool _canCalibracion = false;
  bool _canCorrectivo = false;
  bool _canItse = false;
  bool _canCatalogos = false;
  bool _canGaleria = false;
  bool _canEquipoIntervenido = false;
  bool _canFinanzas = false;
  bool _canDocumentosSst = false;
  bool _canCotizaciones = false;
  // Vista acotada de Requerimientos para Técnico/Jefe de Operaciones (sin el
  // panel completo de Logística, que sigue exclusivo de Logística/Admin).
  bool _canVerRequerimientos = false;
  // HU-54: asignar cuadrilla de campo — cualquiera menos Técnico (mismo
  // criterio que el backend: exigir_no_tecnico).
  bool _puedeAsignarCuadrilla = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    // Recarga los módulos visibles cuando se refrescan permisos (otorgar/revocar
    // privilegios, resume de la app o push 'perfil_actualizado') — sin re-login.
    permissionsRefreshNotifier.addListener(_loadUserData);
  }

  @override
  void dispose() {
    permissionsRefreshNotifier.removeListener(_loadUserData);
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await AppSession.load();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Usuario';
        // Cargo (puesto laboral) para mostrar, no el rol RBAC (ese gobierna
        // permisos y se gestiona en Gestión de Usuarios).
        final cargo = prefs.getString('user_cargo') ?? '';
        _userRol  = cargo.isNotEmpty ? cargo : (prefs.getString('user_rol') ?? '');
        _fotoUrl  = prefs.getString('user_foto_url') ?? '';
        _puedeVerAuditoria   = AppSession.i.canVerAuditoria;
        _esAdmin             = AppSession.i.isAdmin;
        _esSuperAdmin        = AppSession.i.esSuperAdmin;
        _puedeVerPersonal    = AppSession.i.canVerPersonal;
        _puedeVerDashboards  = AppSession.i.canVerDashboards;
        _puedeVerControlAsistencias = AppSession.i.canVerControlAsistencias;
        _puedeGestionarUsuarios     = AppSession.i.canGestionarUsuarios;
        _puedeGestionarPrivilegios  = AppSession.i.canGestionarPrivilegios;
        _puedeAsignarCuadrilla      = !AppSession.i.isTecnico;
        _canCalibracion  = AppSession.i.canVerCalibracion;
        _canCorrectivo   = AppSession.i.canVerCorrectivo;
        _canItse         = AppSession.i.canVerItse;
        _canCatalogos    = AppSession.i.canVerCatalogos;
        _canGaleria      = AppSession.i.canVerGaleria;
        _canEquipoIntervenido = AppSession.i.canVerEquipoIntervenido;
        _canFinanzas = AppSession.i.canVerFinanzas;
        _canDocumentosSst = AppSession.i.canVerDocumentosSst;
        _canCotizaciones = AppSession.i.isAdmin ||
            AppSession.i.hasPerm('cotizaciones:ver') ||
            AppSession.i.hasPerm('cotizaciones:gestionar');
        _canVerRequerimientos = AppSession.i.canVerRequerimientosAcotado;
      });
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar Sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_name');
    await prefs.remove('user_rol');
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TopoBackground(
      c1: isDark ? const Color(0xFF1E9462) : const Color(0xFF1E9462),
      c2: isDark ? const Color(0xFF1E9462) : const Color(0xFF8FD11B),
      base: isDark ? const Color(0xFF0E1611) : const Color(0xFFF5FAF0),
      count: 18,
      amp: 10,
      stroke: 0.40,
      speed: 0.5,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header card ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black
                        .withValues(alpha: isDark ? 0.20 : 0.07),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Más',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildUserBanner(),
                ],
              ),
            ),
            // ── Contenido ────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),

            // ── 1. Mi cuenta (siempre) ─────────────────────────────────
            _buildSectionTitle('Mi cuenta'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              surface: surface,
              items: [
                _MenuItem(
                  icon: Icons.person_outline,
                  label: 'Mi perfil',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaMiEspacio()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── 2. Trabajo (siempre) ───────────────────────────────────
            _buildSectionTitle('Trabajo'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              surface: surface,
              items: [
                _MenuItem(
                  icon: Icons.pending_actions_outlined,
                  label: 'Mis pendientes',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaPendientes()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.campaign_outlined,
                  label: 'Comunicados',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ComunicadosScreen()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.article_outlined,
                  label: 'Trámites y Permisos',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaTramites()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.cloud_outlined,
                  label: 'Drive de empresa',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaDrive()),
                  ),
                ),
              ],
            ),

            // ── 3. Administración (según permisos) ──────────────────────
            if (_puedeVerControlAsistencias || _puedeVerPersonal || _puedeVerDashboards || _esAdmin || _puedeVerAuditoria || _esSuperAdmin || _puedeGestionarUsuarios || _puedeGestionarPrivilegios || _puedeAsignarCuadrilla) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('Administración'),
              const SizedBox(height: 10),
              _buildMenuGroup(
                surface: surface,
                items: [
                  if (_puedeGestionarPrivilegios)
                    _MenuItem(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Privilegios',
                      iconColor: const Color(0xFFD98A16),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PantallaPrivilegios()),
                      ),
                    ),
                  if (_puedeGestionarUsuarios)
                    _MenuItem(
                      icon: Icons.manage_accounts_outlined,
                      label: 'Gestión de usuarios',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PantallaGestionUsuarios()),
                      ),
                    ),
                  // RR.HH. unifica Asistencias, Solicitudes, Personal,
                  // Evaluaciones, Vacaciones, Indicadores y Sesiones en un hub.
                  if (_puedeVerControlAsistencias || _puedeVerPersonal)
                    _MenuItem(
                      icon: Icons.diversity_3_outlined,
                      label: 'Recursos Humanos',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PantallaPersonalHub()),
                      ),
                    ),
                  if (_puedeVerDashboards)
                    _MenuItem(
                      icon: Icons.insights_outlined,
                      label: 'Dashboards',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PantallaDashboards()),
                      ),
                    ),
                  if (_puedeAsignarCuadrilla)
                    _MenuItem(
                      icon: Icons.groups_outlined,
                      label: 'Cuadrilla de Campo',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PantallaCuadrillaCampo()),
                      ),
                    ),
                  if (_esAdmin)
                    _MenuItem(
                      icon: Icons.business_center_outlined,
                      label: 'Accesos Portal Cliente',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PantallaAccesosPortal()),
                      ),
                    ),
                  if (_puedeVerAuditoria)
                    _MenuItem(
                      icon: Icons.manage_search_rounded,
                      label: 'Registro de Auditoría',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PantallaAuditoria()),
                      ),
                    ),
                  if (_esSuperAdmin)
                    _MenuItem(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Auditoría General',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PantallaAuditoriaGeneral()),
                      ),
                    ),
                ],
              ),
            ],

            // ── 4. Módulos operativos (plan migración ERP) ─────────────
            // Cada módulo se muestra solo si el rol tiene su permiso :ver (admin: todos).
            if (_canFinanzas || _canEquipoIntervenido || _canCalibracion || _canCorrectivo || _canItse || _canCatalogos || _canDocumentosSst || _canVerRequerimientos || _canCotizaciones) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('Módulos operativos'),
              const SizedBox(height: 10),
              _buildMenuGroup(
                surface: surface,
                items: [
                  if (_canVerRequerimientos)
                    _MenuItem(
                      icon: Icons.inventory_2_outlined,
                      label: 'Requerimientos',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(
                            builder: (_) => const PantallaRequerimientosLogistica())),
                    ),
                  if (_canCotizaciones)
                    _MenuItem(
                      icon: Icons.request_quote_outlined,
                      label: 'Cotizaciones',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(
                            builder: (_) => const PantallaCotizaciones())),
                    ),
                  if (_canFinanzas)
                    _MenuItem(
                      icon: Icons.account_balance_outlined,
                      label: 'Finanzas',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(
                            builder: (_) => const PantallaFinanzas())),
                    ),
                  if (_canEquipoIntervenido)
                    _MenuItem(
                      icon: Icons.build_circle_outlined,
                      label: 'Mantenimientos',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(
                            builder: (_) => const PantallaEquiposIntervenidos())),
                    ),
                  if (_canCalibracion)
                    _MenuItem(
                      icon: Icons.straighten_outlined,
                      label: 'Calibraciones',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const PantallaCalibraciones())),
                    ),
                  if (_canCorrectivo)
                    _MenuItem(
                      icon: Icons.workspace_premium_outlined,
                      label: 'Garantías / Correctivos',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(
                            builder: (_) => const PantallaGarantiasCorrectivos())),
                    ),
                  if (_canItse)
                    _MenuItem(
                      icon: Icons.fact_check_outlined,
                      label: 'Inspección ITSE',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const PantallaItse())),
                    ),
                  if (_canCatalogos)
                    _MenuItem(
                      icon: Icons.category_outlined,
                      label: 'Catálogos',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const PantallaCatalogos())),
                    ),
                  if (_canCatalogos)
                    _MenuItem(
                      icon: Icons.menu_book_outlined,
                      label: 'Procedimientos estándar',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(
                            builder: (_) => const PantallaPlantillasProcedimiento())),
                    ),
                  if (_canDocumentosSst)
                    _MenuItem(
                      icon: Icons.verified_outlined,
                      label: 'Documentos SST',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(
                            builder: (_) => const PantallaDocumentosSst())),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),

            // ── 5. Recursos (siempre) ──────────────────────────────────
            _buildSectionTitle('Recursos'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              surface: surface,
              items: [
                if (_canGaleria)
                  _MenuItem(
                    icon: Icons.photo_library_outlined,
                    label: 'Galería',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PantallaGaleria()),
                    ),
                  ),
                _MenuItem(
                  icon: Icons.architecture_outlined,
                  label: 'Planos',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaPlanos()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── 6. Ayuda y soporte (siempre) ──────────────────────────
            _buildSectionTitle('Ayuda y soporte'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              surface: surface,
              items: [
                _MenuItem(
                  icon: Icons.help_outline,
                  label: 'Centro de Ayuda',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PantallaCentroAyuda()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.security_outlined,
                  label: 'Privacidad y Seguridad',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PantallaPrivacidadSeguridad()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Configuración',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PantallaConfiguracion()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Cerrar sesión ───────────────────────────────────────────
            _buildCard(
              surface: surface,
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Cerrar Sesión',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.red),
                onTap: _handleLogout,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Footer ─────────────────────────────────────────────────
            const Center(
              child: Column(
                children: [
                  Text(
                    'E-System TIC',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Plataforma de Servicios de Campo',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'v1.0.0',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
                ],          // inner Column.children
              ),             // inner Column
            ),               // SingleChildScrollView
          ),                 // Expanded
        ],                   // outer Column.children
      ),                     // outer Column (SafeArea child)
    ),                       // SafeArea
  );
  }

  // ── Widgets privados ────────────────────────────────────────────────────────

  Widget _buildUserBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EditProfileScreen()),
      ).then((_) => _loadUserData()),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF2D5A00), const Color(0xFF4E8A00)]
                : [const Color(0xFF1E9462), const Color(0xFF8FD11B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8FD11B).withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Avatar ─────────────────────────────────────────────────
            Stack(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5), width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _fotoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _fotoUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 200,
                            errorWidget: (context2, err, stack) => _avatarFallback(),
                          )
                        : _avatarFallback(),
                  ),
                ),
                // Indicador "activo"
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.shade400,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),

            // ── Nombre + rol ────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _userName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_userRol.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _userRol,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Botón editar ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit_outlined,
                  color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    final initials = _userName.trim().split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Container(
      color: Colors.white.withValues(alpha: 0.25),
      child: Center(
        child: Text(
          initials.isEmpty ? '?' : initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
        letterSpacing: 0.8,
      ),
    );
  }

  Widget _buildCard({required Color surface, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }

  Widget _buildMenuGroup({
    required Color surface,
    required List<_MenuItem> items,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: List.generate(items.length, (i) {
            return Column(
              children: [
                items[i],
                if (i < items.length - 1) const Divider(height: 1, indent: 52),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ── Item de menú ──────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
        size: 22,
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
