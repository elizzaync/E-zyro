import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/legajo_models.dart';
import '../utils/abrir_enlace.dart';
import '../utils/app_notifiers.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';
import 'pantalla_historial_proyectos.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key});

  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  int _selectedTab = 0;
  final List<String> _tabs = ['Perfil', 'Documentos'];

  @override
  void initState() {
    super.initState();
    _selectedTab = personalSubTabNotifier.value;
    personalSubTabNotifier.addListener(_onSubTabChanged);
  }

  @override
  void dispose() {
    personalSubTabNotifier.removeListener(_onSubTabChanged);
    super.dispose();
  }

  void _onSubTabChanged() {
    if (mounted && _selectedTab != personalSubTabNotifier.value) {
      setState(() => _selectedTab = personalSubTabNotifier.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
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
            // ── Header card flotante ──────────────────────────────────
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
                    'Personal',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(
                      _tabs.length,
                      (i) => _TabButton(
                        label: _tabs[i],
                        isSelected: _selectedTab == i,
                        onTap: () {
                          setState(() => _selectedTab = i);
                          personalSubTabNotifier.value = i;
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Contenido ─────────────────────────────────────────────
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: const [
                  _ProfileTab(),
                  _DocumentsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Botón de tab ─────────────────────────────────────────────────────────────
class _TabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? green : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? green
                : (isDark
                      ? green.withValues(alpha: 0.35)
                      : Colors.grey.shade300),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ─── Tab: Perfil ──────────────────────────────────────────────────────────────
class _ProfileTab extends StatefulWidget {
  const _ProfileTab();

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  String _name = 'Usuario';
  String _rol = '';
  String _email = '';
  String _phone = '';
  String _fotoUrl = '';
  int _serviciosCompletados = 0;
  int _asistenciasMes = 0;
  int _solicitudesPendientes = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    fotoPerfilNotifier.addListener(_onFotoChanged);
  }

  @override
  void dispose() {
    fotoPerfilNotifier.removeListener(_onFotoChanged);
    super.dispose();
  }

  void _onFotoChanged() {
    if (mounted) setState(() => _fotoUrl = fotoPerfilNotifier.value);
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dashboardService = await getDashboardService();

      final resumen = await dashboardService.getResumen();

      if (mounted) {
        setState(() {
          _name = '${resumen.usuario.nombre} ${resumen.usuario.apellido}'
              .trim();
          // Cargo (puesto laboral), no el rol RBAC: mismo dato que muestra la
          // web en Personal. El rol RBAC sigue siendo la fuente de permisos
          // y se gestiona aparte en Gestión de Usuarios.
          final cargo = prefs.getString('user_cargo') ?? '';
          _rol = cargo.isNotEmpty
              ? cargo
              : (prefs.getString('user_rol') ?? 'Colaborador');
          _email = resumen.usuario.email;
          _phone = resumen.usuario.telefono;
          _fotoUrl = resumen.usuario.fotoUrl;
          _serviciosCompletados = resumen.completados;
          _asistenciasMes = resumen.asistenciasMes;
          _solicitudesPendientes = resumen.solicitudesPendientes;
          _loaded = true;
        });
      }
    } catch (e) {
      // En caso de error, cargar desde SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _name = prefs.getString('user_name') ?? 'Usuario';
          final cargo = prefs.getString('user_cargo') ?? '';
          _rol = cargo.isNotEmpty
              ? cargo
              : (prefs.getString('user_rol') ?? 'Colaborador');
          _email = prefs.getString('user_email') ?? '';
          _phone = prefs.getString('user_phone') ?? '';
          _fotoUrl = prefs.getString('user_foto_url') ?? '';
          _loaded = true;
        });
      }
    }
  }

  String get _initials {
    final parts = _name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  /// ID de empleado derivado del nombre (estable y visual).
  String get _employeeId {
    if (_name.isEmpty) return 'EMP-0001';
    final code = (_name.hashCode.abs() % 9000 + 1000);
    return 'EMP-$code';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    BoxDecoration cardDeco({double radius = 14}) => BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: isDark
          ? Border.all(color: green.withValues(alpha: 0.45), width: 1.0)
          : null,
      boxShadow: isDark
          ? [
              BoxShadow(
                color: green.withValues(alpha: 0.10),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );

    if (!_loaded) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: [
          // ── Avatar + nombre ───────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: cardDeco(radius: 16),
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8FD11B), Color(0xFF1E9462)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: green.withValues(alpha: 0.45),
                        blurRadius: 22,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: _fotoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _fotoUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 300,
                            errorWidget: (context, error, _) => Center(
                              child: Text(
                                _initials,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              _initials,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 30,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_rol.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _rol,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                // ── Badges: Cuenta Activa + ID de empleado ────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? green.withValues(alpha: 0.12)
                            : const Color(0xFFEFFAE0),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_user_outlined,
                              size: 12, color: Color(0xFF8FD11B)),
                          const SizedBox(width: 4),
                          const Text(
                            'Cuenta Activa',
                            style: TextStyle(
                              color: Color(0xFF8FD11B),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.badge_outlined,
                              size: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            _employeeId,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Info de contacto ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Información de Contacto',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 14),
                if (_email.isNotEmpty)
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Correo',
                    value: _email,
                  )
                else
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Correo',
                    value: 'No configurado',
                    muted: true,
                  ),
                if (_phone.isNotEmpty)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Teléfono',
                    value: _phone,
                  )
                else
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Teléfono',
                    value: 'No configurado',
                    muted: true,
                  ),
                _InfoRow(
                  icon: Icons.business_outlined,
                  label: 'Empresa',
                  value: 'E-System TIC',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Certificaciones ───────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Certificaciones',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark
                            ? green.withValues(alpha: 0.14)
                            : const Color(0xFFEFFAE0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Próximamente',
                        style: TextStyle(
                          color: Color(0xFF8FD11B),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.workspace_premium_outlined,
                          size: 44,
                          color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      const Text(
                        'Sin certificaciones registradas',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tus certificaciones y habilidades\nse mostrarán aquí',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Estadísticas rápidas ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: cardDeco(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Estadísticas',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _StatMini(
                      label: 'Servicios',
                      value: _serviciosCompletados.toString(),
                      icon: Icons.build_outlined,
                    ),
                    const SizedBox(width: 10),
                    _StatMini(
                      label: 'Asistencias',
                      value: _asistenciasMes.toString(),
                      icon: Icons.calendar_month_outlined,
                    ),
                    const SizedBox(width: 10),
                    _StatMini(
                      label: 'Solicitudes',
                      value: _solicitudesPendientes.toString(),
                      icon: Icons.timer_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Historial de Proyectos (HU-45) ────────────────────────────
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PantallaHistorialProyectos(),
                ),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: cardDeco(),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8FD11B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.history_rounded,
                          color: Color(0xFF8FD11B), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Historial de Proyectos',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF8FD11B).withValues(alpha: 0.15)
                  : const Color(0xFFEFFAE0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF8FD11B)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: muted ? Colors.grey : null,
                  fontStyle: muted ? FontStyle.italic : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatMini({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? surface : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF8FD11B)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab: Documentos ──────────────────────────────────────────────────────────
class _DocumentsTab extends StatefulWidget {
  const _DocumentsTab();

  @override
  State<_DocumentsTab> createState() => _DocumentsTabState();
}

class _DocumentsTabState extends State<_DocumentsTab> {
  bool _cargando = true;
  List<DocumentoLegajo> _docs = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final svc = await getDashboardService();
      final docs = await svc.getMisDocumentos();
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargando = false);
    }
  }

  IconData _iconoTipo(String tipo) {
    final t = tipo.trim().toLowerCase();
    if (t.contains('boleta')) return Icons.receipt_long_outlined;
    if (t.contains('contrato')) return Icons.badge_outlined;
    if (t.contains('certificado') || t.contains('constancia')) return Icons.school_outlined;
    return Icons.description_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    const green = Color(0xFF8FD11B);

    BoxDecoration cardDeco() => BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      border: isDark ? Border.all(color: green.withValues(alpha: 0.35)) : null,
      boxShadow: isDark
          ? [BoxShadow(color: green.withValues(alpha: 0.08), blurRadius: 10)]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );

    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: green));
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      color: green,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: _docs.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Column(
                  children: [
                    Icon(Icons.folder_open_outlined, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('Sin documentos',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MIS DOCUMENTOS',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500, letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final d in _docs)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: cardDeco(),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        child: ListTile(
                          onTap: () => abrirEnlace(d.urlArchivo),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? green.withValues(alpha: 0.12) : const Color(0xFFEFFAE0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(_iconoTipo(d.tipo), color: green, size: 20),
                          ),
                          title: Text(d.nombre, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: Text('${d.tipo} · ${d.fechaTexto}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
