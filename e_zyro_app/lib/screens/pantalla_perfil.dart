import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_notifiers.dart';
import '../models/asistencia_models.dart';
import '../utils/api_provider.dart';
import '../widgets/topo_background.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key});

  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  int _selectedTab = 0;
  final List<String> _tabs = ['Perfil', 'Asistencia', 'Documentos'];

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
                  _AsistenciaHistorialTab(),
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
          _rol = prefs.getString('user_rol') ?? 'Colaborador';
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
          _rol = prefs.getString('user_rol') ?? 'Colaborador';
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
                      colors: [Color(0xFF8FD11B), Color(0xFF3E7E00)],
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

// ─── Tab: Historial de Asistencia ──────────────────────────────────────────────
class _AsistenciaHistorialTab extends StatefulWidget {
  const _AsistenciaHistorialTab();

  @override
  State<_AsistenciaHistorialTab> createState() =>
      _AsistenciaHistorialTabState();
}

class _AsistenciaHistorialTabState extends State<_AsistenciaHistorialTab> {
  List<RegistroAsistencia> _historial = [];
  RegistroAsistencia? _entradaHoy;
  RegistroAsistencia? _salidaHoy;
  bool _isLoading = true;

  static const _green = Color(0xFF8FD11B);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = await getAsistenciaService();
    final historial = await svc.getHistorial();
    final ahora = DateTime.now();
    bool esHoy(DateTime dt) =>
        dt.year == ahora.year && dt.month == ahora.month && dt.day == ahora.day;
    final hoyList = historial.where((r) => esHoy(r.timestamp));
    final entradas = hoyList.where(
      (r) => r.tipo == 'ENTRADA' && r.status == 'APROBADO',
    );
    final salidas = hoyList.where(
      (r) => r.tipo == 'SALIDA' && r.status == 'APROBADO',
    );
    if (mounted) {
      setState(() {
        _historial = historial;
        _entradaHoy = entradas.isEmpty ? null : entradas.first;
        _salidaHoy = salidas.isEmpty ? null : salidas.first;
        _isLoading = false;
      });
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  BoxDecoration _cardDeco(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(14),
      border: isDark
          ? Border.all(color: _green.withValues(alpha: 0.45), width: 1.0)
          : null,
      boxShadow: isDark
          ? [
              BoxShadow(
                color: _green.withValues(alpha: 0.10),
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
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_green),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: _green,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Estado del día ────────────────────────────────────────
            Container(
              decoration: _cardDeco(context),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hoy',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatusItem(
                          context,
                          'Entrada',
                          _entradaHoy,
                          true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatusItem(
                          context,
                          'Salida',
                          _salidaHoy,
                          false,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Historial ─────────────────────────────────────────────
            const Text(
              'Historial',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (_historial.isEmpty)
              Container(
                padding: const EdgeInsets.all(28),
                decoration: _cardDeco(context),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.history, size: 48, color: Colors.grey),
                      SizedBox(height: 10),
                      Text(
                        'Sin registros previos',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Usa "Asistencia" desde Inicio para registrar',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._buildHistorialAgrupado(context),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(
    BuildContext context,
    String label,
    RegistroAsistencia? r,
    bool isEntrada,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const green = Color(0xFF8FD11B);
    final registered = r != null;
    final col = isEntrada ? green : Colors.blue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: registered
            ? (isDark
                  ? col.withValues(alpha: 0.12)
                  : col.withValues(alpha: 0.08))
            : (isDark
                  ? Colors.grey.withValues(alpha: 0.08)
                  : Colors.grey.shade50),
        borderRadius: BorderRadius.circular(12),
        border: registered
            ? Border.all(color: col.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEntrada ? Icons.login : Icons.logout,
                size: 13,
                color: registered ? col : Colors.grey,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: registered ? col : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            registered
                ? '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}'
                : '--:--',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: registered ? col : Colors.grey.shade400,
            ),
          ),
          if (registered)
            Text(
              '${r.score.toStringAsFixed(1)}% · ${r.latitud != null ? "GPS ✓" : "Sin GPS"}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            )
          else
            const Text(
              'Pendiente',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildHistorialAgrupado(BuildContext context) {
    final Map<String, List<RegistroAsistencia>> grupos = {};
    for (final r in _historial) {
      grupos.putIfAbsent(_dayKey(r.timestamp), () => []).add(r);
    }
    return grupos.entries
        .map(
          (entry) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _labelForKey(entry.key),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              ...entry.value.map((r) => _buildRegistroItem(context, r)),
              const SizedBox(height: 12),
            ],
          ),
        )
        .toList();
  }

  String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _labelForKey(String key) {
    final now = DateTime.now();
    if (key == _dayKey(now)) return 'HOY';
    if (key == _dayKey(now.subtract(const Duration(days: 1)))) return 'AYER';
    final p = key.split('-');
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  Widget _buildRegistroItem(BuildContext context, RegistroAsistencia r) {
    final aprobado = r.status == 'APROBADO';
    final isEntrada = r.tipo == 'ENTRADA';
    const green = Color(0xFF8FD11B);
    final tipoColor = isEntrada ? green : Colors.blue;
    final statusColor = aprobado ? green : Colors.red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(context),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: tipoColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isEntrada ? Icons.login : Icons.logout,
              color: tipoColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.tipo,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_pad(r.timestamp.hour)}:${_pad(r.timestamp.minute)}  ·  ${r.latitud != null ? "GPS ✓" : "Sin GPS"}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  r.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${r.score.toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Documentos ──────────────────────────────────────────────────────────
class _DocumentsTab extends StatelessWidget {
  const _DocumentsTab();

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

    final docTypes = [
      (Icons.badge_outlined, 'Contrato de Trabajo'),
      (Icons.health_and_safety_outlined, 'Certificado Médico'),
      (Icons.school_outlined, 'Certificaciones'),
      (Icons.receipt_long_outlined, 'Boletas de Pago'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner próximamente
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  isDark ? const Color(0xFF1A2A0A) : const Color(0xFFF0FAE0),
                  isDark ? const Color(0xFF0D1A06) : const Color(0xFFE8F7D0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: green.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.folder_outlined,
                    size: 38,
                    color: Color(0xFF8FD11B),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Documentos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Aquí podrás acceder a tus documentos laborales, contratos y certificaciones.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Próximamente',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'CATEGORÍAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade500,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...docTypes.map(
            (doc) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: cardDeco(),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? green.withValues(alpha: 0.12)
                        : const Color(0xFFEFFAE0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(doc.$1, color: green, size: 20),
                ),
                title: Text(
                  doc.$2,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: const Text(
                  'No disponible aún',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Pronto',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ),
              ),  // Material
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
