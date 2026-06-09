import 'package:e_zyro_app/screens/pantalla_tramites.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_notifiers.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';
import 'pantalla_auditoria.dart';
import 'pantalla_mantenimientos.dart';
import 'pantalla_comunicados.dart';
import 'pantalla_soporte.dart';
import 'pantalla_editar_perfil.dart';
import 'pantalla_mis_sesiones.dart';
import 'pantalla_personal.dart';
import 'pantalla_personal_hub.dart';
import 'pantalla_mi_espacio.dart';
import 'pantalla_galeria.dart';
import 'pantalla_calibraciones.dart';
import 'pantalla_correctivos.dart';
import 'pantalla_itse.dart';
import 'pantalla_catalogos.dart';
import 'pantalla_plantillas_procedimiento.dart';
import 'pantalla_equipos_intervenidos.dart';
import 'pantalla_dashboards.dart';
import 'pantalla_planos.dart';
import 'finanzas/pantalla_finanzas.dart';
import 'finanzas/pantalla_manual_finanzas.dart';

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
  bool _puedeVerMantenimiento = false;
  bool _puedeVerPersonal = false;
  bool _puedeVerDashboards = false;
  // Visibilidad de módulos por permiso (admin ve todos).
  bool _canCalibracion = false;
  bool _canCorrectivo = false;
  bool _canItse = false;
  bool _canCatalogos = false;
  bool _canGaleria = false;
  bool _canEquipoIntervenido = false;
  bool _canFinanzas = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await AppSession.load();
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Usuario';
        _userRol  = prefs.getString('user_rol') ?? '';
        _fotoUrl  = prefs.getString('user_foto_url') ?? '';
        _puedeVerAuditoria   = AppSession.i.canVerAuditoria;
        _puedeVerMantenimiento = AppSession.i.canVerMantenimientoGeneral;
        _puedeVerPersonal    = AppSession.i.canVerPersonal;
        _puedeVerDashboards  = AppSession.i.canVerDashboards;
        _canCalibracion  = AppSession.i.canVerCalibracion;
        _canCorrectivo   = AppSession.i.canVerCorrectivo;
        _canItse         = AppSession.i.canVerItse;
        _canCatalogos    = AppSession.i.canVerCatalogos;
        _canGaleria      = AppSession.i.canVerGaleria;
        _canEquipoIntervenido = AppSession.i.canVerEquipoIntervenido;
        _canFinanzas = AppSession.i.canVerFinanzas;
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

  void _abrirDocumentacion() {
    if (!_canFinanzas) {
      _showInfoDialog(
        'Documentación',
        'Por ahora no hay manuales disponibles para los módulos a los que tienes acceso. '
            'Para soporte y guías generales, contáctanos en soporte@esystemtic.com.',
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Manuales disponibles',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined,
                    color: Color(0xFF5A9A00)),
                title: const Text('Manual de Usuario · Finanzas'),
                subtitle: const Text(
                    'Qué hacer en cada pantalla y cómo se forma el asiento contable PCGE'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaManualFinanzas()),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfoDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TopoBackground(
      c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
      c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
      base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
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

            // ── Apariencia ─────────────────────────────────────────────
            _buildSectionTitle('Apariencia'),
            const SizedBox(height: 10),
            _buildCard(
              surface: surface,
              child: ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (_, mode, _) => SwitchListTile(
                  secondary: Icon(
                    mode == ThemeMode.dark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                    size: 22,
                  ),
                  title: const Text(
                    'Modo Oscuro',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  value: mode == ThemeMode.dark,
                  activeThumbColor: const Color(0xFF8FD11B),
                  onChanged: (val) async {
                    themeNotifier.value = val
                        ? ThemeMode.dark
                        : ThemeMode.light;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('dark_mode', val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Cuenta ─────────────────────────────────────────────────
            _buildSectionTitle('Cuenta'),
            const SizedBox(height: 10),
            _buildMenuGroup(
              surface: surface,
              items: [
                _MenuItem(
                  icon: Icons.account_circle_outlined,
                  label: 'Mi espacio',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaMiEspacio()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.person_outline,
                  label: 'Mi Perfil',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ),
                  ),
                ),
                _MenuItem(
                  icon: Icons.campaign_outlined,
                  label: 'Comunicados',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ComunicadosScreen(),
                    ),
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
                  icon: Icons.support_agent_outlined,
                  label: 'Soporte TI',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaSoporte()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.devices_other_outlined,
                  label: 'Mis conexiones',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PantallaMisSesiones()),
                  ),
                ),
                _MenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Configuración',
                  onTap: () => _showInfoDialog(
                    'Configuración',
                    'Las opciones de configuración avanzada estarán disponibles próximamente.',
                  ),
                ),
              ],
            ),
            if (_puedeVerAuditoria || _puedeVerMantenimiento || _puedeVerPersonal || _puedeVerDashboards) ...[
              const SizedBox(height: 20),
              _buildSectionTitle('Administración'),
              const SizedBox(height: 10),
              _buildMenuGroup(
                surface: surface,
                items: [
                  if (_puedeVerDashboards)
                    _MenuItem(
                      icon: Icons.insights_outlined,
                      label: 'Dashboards',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PantallaDashboards()),
                      ),
                    ),
                  if (_puedeVerMantenimiento)
                    _MenuItem(
                      icon: Icons.build_circle_outlined,
                      label: 'Mantenimientos',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PantallaMantenimientos()),
                      ),
                    ),
                  if (_puedeVerPersonal)
                    _MenuItem(
                      icon: Icons.badge_outlined,
                      label: 'Personal / RR.HH.',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PantallaPersonalHub()),
                      ),
                    ),
                  if (_puedeVerPersonal)
                    _MenuItem(
                      icon: Icons.devices_other_outlined,
                      label: 'Sesiones de personal',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PantallaPersonal()),
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
                ],
              ),
            ],
            const SizedBox(height: 20),

            // ── Módulos operativos (plan migración ERP) ────────────────
            // Cada módulo se muestra solo si el rol tiene su permiso :ver (admin: todos).
            if (_canCalibracion || _canCorrectivo || _canItse || _canCatalogos || _canEquipoIntervenido || _canFinanzas) ...[
              _buildSectionTitle('Módulos'),
              const SizedBox(height: 10),
              _buildMenuGroup(
                surface: surface,
                items: [
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
                      icon: Icons.electrical_services_outlined,
                      label: 'Equipos Intervenidos',
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
                      icon: Icons.build_outlined,
                      label: 'Garantías / Correctivos',
                      onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const PantallaCorrectivos())),
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
                ],
              ),
              const SizedBox(height: 20),
            ],

            // ── Recursos ───────────────────────────────────────────────
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
                _MenuItem(
                  icon: Icons.description_outlined,
                  label: 'Documentación',
                  onTap: _abrirDocumentacion,
                ),
                _MenuItem(
                  icon: Icons.help_outline,
                  label: 'Centro de Ayuda',
                  onTap: () => _showInfoDialog(
                    'Centro de Ayuda',
                    'Para soporte técnico contáctanos:\nsoporte@esystemtic.com',
                  ),
                ),
                _MenuItem(
                  icon: Icons.security_outlined,
                  label: 'Privacidad y Seguridad',
                  onTap: () => _showInfoDialog(
                    'Privacidad y Seguridad',
                    'Tu información está protegida. Los datos son cifrados y almacenados de forma segura conforme a nuestra política de privacidad.',
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
                : [const Color(0xFF5A9A00), const Color(0xFF8FD11B)],
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

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
