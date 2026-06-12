import 'dart:convert';

import 'package:flutter/material.dart';
import '../models/auditoria_models.dart';
import '../services/auditoria_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../widgets/topo_background.dart';

class PantallaAuditoria extends StatefulWidget {
  const PantallaAuditoria({super.key});

  @override
  State<PantallaAuditoria> createState() => _PantallaAuditoriaState();
}

class _PantallaAuditoriaState extends State<PantallaAuditoria> {
  static const _green = Color(0xFF8FD11B);

  AuditoriaService? _service;
  List<AuditoriaItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sessionExpired = false;
  String? _errorMsg;
  int _page = 1;
  static const _pageSize = 50;

  // Filtros
  String? _filtroModulo;
  String? _filtroAccion;
  String? _filtroTablaAfectada;
  String? _filtroQ;
  String? _filtroBuscarUsuario;
  String? _filtroFechaDesde; // YYYY-MM-DD
  String? _filtroFechaHasta; // YYYY-MM-DD

  final _scrollCtrl = ScrollController();

  static const _modulos = [
    'Todos',
    'SEGURIDAD', 'OPERACIONES', 'ASISTENCIA', 'REQUERIMIENTOS',
    'INVENTARIO', 'COMPRAS', 'CLIENTES', 'FINANZAS', 'MANTENIMIENTO',
    'COMUNICADOS', 'USUARIOS', 'EMPLEADOS', 'EMPRESA', 'RRHH',
  ];
  static const _acciones = [
    'Todas',
    'INSERT', 'UPDATE', 'DELETE',
    'LOGIN', 'LOGOUT',
    'CREAR_COMUNICADO',
    'PASSWORD_CHANGED_SUCCESS', 'PASSWORD_RECOVERY_REQUEST',
    'PASSWORD_RECOVERY_FAILED', 'PASSWORD_RECOVERY_BLOCKED',
  ];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getAuditoriaService();
    await _load(reset: true);
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore || _loading) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_service == null) return;
    if (reset) {
      setState(() { _loading = true; _page = 1; _hasMore = true; _errorMsg = null; _sessionExpired = false; });
    }
    try {
      final data = await _service!.getAuditoria(
        modulo: (_filtroModulo == 'Todos' || _filtroModulo == null) ? null : _filtroModulo,
        accion: (_filtroAccion == 'Todas' || _filtroAccion == null) ? null : _filtroAccion,
        tablaAfectada: _filtroTablaAfectada,
        q: _filtroQ,
        buscarUsuario: _filtroBuscarUsuario,
        fechaDesde: _filtroFechaDesde,
        fechaHasta: _filtroFechaHasta,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = data;
        _hasMore = data.length >= _pageSize;
        _page = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _loading = false;
        if (msg.contains('expirada') || msg.contains('Sesión')) {
          _sessionExpired = true;
        } else {
          _errorMsg = msg;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_service == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    final data = await _service!.getAuditoria(
      modulo: (_filtroModulo == 'Todos' || _filtroModulo == null) ? null : _filtroModulo,
      accion: (_filtroAccion == 'Todas' || _filtroAccion == null) ? null : _filtroAccion,
      tablaAfectada: _filtroTablaAfectada,
      q: _filtroQ,
      buscarUsuario: _filtroBuscarUsuario,
      fechaDesde: _filtroFechaDesde,
      fechaHasta: _filtroFechaHasta,
      page: nextPage,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _items.addAll(data);
      _page = nextPage;
      _hasMore = data.length >= _pageSize;
      _loadingMore = false;
    });
  }

  static String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  void _openFiltros() {
    String? modulo = _filtroModulo;
    String? accion = _filtroAccion;
    String? fechaDesde = _filtroFechaDesde;
    String? fechaHasta = _filtroFechaHasta;
    final tablaCtrl = TextEditingController(text: _filtroTablaAfectada ?? '');
    final qCtrl = TextEditingController(text: _filtroQ ?? '');
    final usuarioCtrl = TextEditingController(text: _filtroBuscarUsuario ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final rangoLabel = (fechaDesde != null || fechaHasta != null)
              ? '${fechaDesde ?? '…'}  →  ${fechaHasta ?? '…'}'
              : 'Cualquier fecha';
          return SingleChildScrollView(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 24, right: 24, top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Filtrar Auditoría',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // ── Rango de fecha ──
                  const Text('Rango de fecha', style: _labelStyle),
                  const SizedBox(height: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final now = DateTime.now();
                      final initial = (fechaDesde != null && fechaHasta != null)
                          ? DateTimeRange(
                              start: _parseDate(fechaDesde)!,
                              end: _parseDate(fechaHasta)!,
                            )
                          : null;
                      final picked = await showDateRangePicker(
                        context: ctx,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 1, 12, 31),
                        initialDateRange: initial,
                        builder: (c, child) => Theme(
                          data: Theme.of(c).copyWith(
                            colorScheme: Theme.of(c).colorScheme.copyWith(primary: _green),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setModal(() {
                          fechaDesde = _fmtDate(picked.start);
                          fechaHasta = _fmtDate(picked.end);
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.date_range_rounded, size: 18, color: Colors.grey),
                          const SizedBox(width: 10),
                          Expanded(child: Text(rangoLabel, style: const TextStyle(fontSize: 13))),
                          if (fechaDesde != null || fechaHasta != null)
                            GestureDetector(
                              onTap: () => setModal(() { fechaDesde = null; fechaHasta = null; }),
                              child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── Buscar usuario ──
                  const Text('Usuario (nombre o apellido)', style: _labelStyle),
                  const SizedBox(height: 8),
                  TextField(
                    controller: usuarioCtrl,
                    decoration: _fieldDeco(context,
                        hint: 'ej: Juan, Pérez…', icon: Icons.person_search_rounded),
                  ),
                  const SizedBox(height: 16),

                  // ── Tipo de acción ──
                  const Text('Tipo de acción', style: _labelStyle),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: accion ?? 'Todas',
                    decoration: _fieldDeco(context),
                    items: _acciones.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setModal(() => accion = v),
                  ),
                  const SizedBox(height: 16),

                  // ── Módulo ──
                  const Text('Módulo', style: _labelStyle),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: modulo ?? 'Todos',
                    decoration: _fieldDeco(context),
                    items: _modulos.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setModal(() => modulo = v),
                  ),
                  const SizedBox(height: 16),

                  // ── Búsqueda en descripción ──
                  const Text('Buscar en descripción', style: _labelStyle),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qCtrl,
                    decoration: _fieldDeco(context,
                        hint: 'Texto libre…', icon: Icons.search),
                  ),
                  const SizedBox(height: 16),

                  // ── Tabla afectada ──
                  const Text('Tabla afectada', style: _labelStyle),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tablaCtrl,
                    decoration: _fieldDeco(context,
                        hint: 'ej: proyecto_servicio, requerimiento…'),
                  ),
                  const SizedBox(height: 24),

                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _filtroModulo = null;
                            _filtroAccion = null;
                            _filtroTablaAfectada = null;
                            _filtroQ = null;
                            _filtroBuscarUsuario = null;
                            _filtroFechaDesde = null;
                            _filtroFechaHasta = null;
                          });
                          Navigator.pop(context);
                          _load(reset: true);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Limpiar', style: TextStyle(color: Colors.grey)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _filtroModulo = modulo;
                            _filtroAccion = accion;
                            final t = tablaCtrl.text.trim();
                            _filtroTablaAfectada = t.isEmpty ? null : t;
                            final qq = qCtrl.text.trim();
                            _filtroQ = qq.isEmpty ? null : qq;
                            final u = usuarioCtrl.text.trim();
                            _filtroBuscarUsuario = u.isEmpty ? null : u;
                            _filtroFechaDesde = fechaDesde;
                            _filtroFechaHasta = fechaHasta;
                          });
                          Navigator.pop(context);
                          _load(reset: true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static const _labelStyle =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey);

  InputDecoration _fieldDeco(BuildContext context, {String? hint, IconData? icon}) =>
      InputDecoration(
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 18) : null,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );

  bool get _hayFiltros =>
      (_filtroModulo != null && _filtroModulo != 'Todos') ||
      (_filtroAccion != null && _filtroAccion != 'Todas') ||
      (_filtroTablaAfectada != null && _filtroTablaAfectada!.isNotEmpty) ||
      (_filtroQ != null && _filtroQ!.isNotEmpty) ||
      (_filtroBuscarUsuario != null && _filtroBuscarUsuario!.isNotEmpty) ||
      _filtroFechaDesde != null ||
      _filtroFechaHasta != null;

  void _limpiarFiltros() {
    setState(() {
      _filtroModulo = null;
      _filtroAccion = null;
      _filtroTablaAfectada = null;
      _filtroQ = null;
      _filtroBuscarUsuario = null;
      _filtroFechaDesde = null;
      _filtroFechaHasta = null;
    });
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TopoBackground(
      c1: isDark ? const Color(0xFF3D6E00) : const Color(0xFF5A9A00),
      c2: isDark ? const Color(0xFF5A9A00) : const Color(0xFF8FD11B),
      base: isDark ? const Color(0xFF0F1A08) : const Color(0xFFF5FAF0),
      count: 14, amp: 8, stroke: 0.35, speed: 0.4,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Registros de Auditoría',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.filter_list_rounded,
                    color: _hayFiltros ? _green : null,
                  ),
                  onPressed: _openFiltros,
                  tooltip: 'Filtros',
                ),
                if (_hayFiltros)
                  Positioned(
                    top: 8, right: 8,
                    child: Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(_green)))
            : _sessionExpired
                ? _buildSessionExpired()
                : _errorMsg != null
                    ? _buildErrorMsg(_errorMsg!)
                    : _items.isEmpty
                ? _buildEmpty()
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    color: _green,
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      padding: bottomSafePadding(context, top: 8, extra: 24),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i == _items.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          );
                        }
                        // key estable por id → preserva estado de expansión al paginar
                        return _AuditoriaCard(key: ValueKey(_items[i].id), item: _items[i]);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildSessionExpired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock_outlined, size: 56, color: Colors.orange),
            const SizedBox(height: 16),
            const Text('Sesión expirada',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Tu sesión ha vencido. Cierra sesión e inicia nuevamente para continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Ir al Login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMsg(String msg) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 12),
          Text(msg.replaceAll('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: () => _load(reset: true),
              child: const Text('Reintentar', style: TextStyle(color: _green))),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.manage_search_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            _hayFiltros ? 'Sin registros con los filtros actuales' : 'Sin registros de auditoría',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
          if (_hayFiltros) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _limpiarFiltros,
              child: const Text('Limpiar filtros', style: TextStyle(color: _green)),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Tarjeta de evento de auditoría — compacta + accordion inline
// ══════════════════════════════════════════════════════════════════════════════

class _AuditoriaCard extends StatefulWidget {
  final AuditoriaItem item;
  const _AuditoriaCard({super.key, required this.item});

  @override
  State<_AuditoriaCard> createState() => _AuditoriaCardState();
}

class _AuditoriaCardState extends State<_AuditoriaCard> {
  bool _expanded = false;
  bool _ctxExpanded = false;

  static const _green  = Color(0xFF8FD11B);  // crear / éxito
  static const _amber  = Color(0xFFF59E0B);  // modificar / password
  static const _blue   = Color(0xFF3B82F6);  // sesión / acceso
  static const _red    = Color(0xFFEF4444);  // eliminar / fallar / rechazar
  static const _purple = Color(0xFF8B5CF6);  // flujo de negocio
  static const _teal   = Color(0xFF14B8A6);  // movimiento / transferencia
  static const _gray   = Color(0xFF6B7280);  // logout / consulta

  AuditoriaItem get item => widget.item;

  // Categoría visual de la acción (rojo gana sobre lo neutro).
  static _AccionCat _categoria(String accionRaw) {
    final a = accionRaw.toUpperCase();
    if (a.contains('FAILED') || a.contains('BLOCK') || a.contains('DENIED') ||
        a.contains('RECHAZ') || a.contains('CANCEL')) {
      return _AccionCat.peligro;
    }
    if (a == 'DELETE' || a.contains('ELIMINAR') || a.contains('REMOVER') ||
        a.contains('BAJA')) {
      return _AccionCat.eliminar;
    }
    if (a.contains('LOGIN') || a.contains('ACCESO')) return _AccionCat.login;
    if (a.contains('LOGOUT'))                         return _AccionCat.logout;
    if (a.contains('PASSWORD') || a.contains('RECUPERAC')) {
      return _AccionCat.password;
    }
    if (a.contains('APROBAR') || a.contains('APROBADO') ||
        a.contains('FIRMAR')  || a.contains('FIRMA')   ||
        a.contains('ENTREGAR')|| a.contains('ENTREGADO')||
        a.contains('FINALIZAR') || a.contains('GENERAR') ||
        a.contains('PUBLICAR')) {
      return _AccionCat.flujo;
    }
    if (a.contains('MOVIMIENTO') || a.contains('TRANSFER') ||
        a.contains('AJUSTE')     || a.contains('STOCK')) {
      return _AccionCat.movimiento;
    }
    if (a == 'UPDATE' || a.contains('ACTUALIZAR') || a.contains('EDITAR') ||
        a.contains('MODIFICAR') || a.contains('CAMBIO')) {
      return _AccionCat.modificar;
    }
    if (a == 'INSERT' || a.contains('CREAR') || a.contains('AGREGAR') ||
        a.contains('REGISTRAR') || a.contains('NUEVO')) {
      return _AccionCat.crear;
    }
    return _AccionCat.otro;
  }

  _AccionCat get _cat => _categoria(item.accion);

  Color get _accionColor => switch (_cat) {
        _AccionCat.peligro    => _red,
        _AccionCat.eliminar   => _red,
        _AccionCat.login      => _blue,
        _AccionCat.logout     => _gray,
        _AccionCat.password   => _amber,
        _AccionCat.flujo      => _purple,
        _AccionCat.movimiento => _teal,
        _AccionCat.modificar  => _amber,
        _AccionCat.crear      => _green,
        _AccionCat.otro       => _gray,
      };

  IconData get _accionIcon => switch (_cat) {
        _AccionCat.peligro    => Icons.warning_amber_rounded,
        _AccionCat.eliminar   => Icons.delete_outline_rounded,
        _AccionCat.login      => Icons.login_rounded,
        _AccionCat.logout     => Icons.logout_rounded,
        _AccionCat.password   => Icons.lock_outline_rounded,
        _AccionCat.flujo      => Icons.workspace_premium_outlined,
        _AccionCat.movimiento => Icons.swap_horiz_rounded,
        _AccionCat.modificar  => Icons.edit_outlined,
        _AccionCat.crear      => Icons.add_circle_outline_rounded,
        _AccionCat.otro       => Icons.history_rounded,
      };

  /// Verbo en lenguaje natural según la acción.
  String get _verbo {
    final a = item.accion.toUpperCase();
    return switch (_cat) {
      _AccionCat.crear      => 'creó un registro en',
      _AccionCat.modificar  => 'actualizó',
      _AccionCat.eliminar   => 'eliminó un registro de',
      _AccionCat.login      => 'inició sesión',
      _AccionCat.logout     => 'cerró sesión',
      _AccionCat.password   => 'modificó credenciales',
      _AccionCat.movimiento => 'registró un movimiento en',
      _AccionCat.flujo      => 'ejecutó una acción en',
      _AccionCat.peligro    => 'intento bloqueado en',
      _AccionCat.otro       => '${a.toLowerCase().replaceAll('_', ' ')} en',
    };
  }

  /// Acciones de sesión no tienen una entidad significativa.
  bool get _muestraEntidad =>
      _cat != _AccionCat.login && _cat != _AccionCat.logout;

  /// Iniciales para el avatar (2 letras). 'SY' = Sistema.
  String get _iniciales {
    final n = item.usuarioNombre?.trim();
    if (n == null || n.isEmpty) return 'SY';
    final partes = n.split(RegExp(r'\s+'));
    if (partes.length == 1) {
      return partes.first.substring(0, partes.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (partes[0][0] + partes[1][0]).toUpperCase();
  }

  String get _actor => item.usuarioNombre?.trim().isNotEmpty == true
      ? item.usuarioNombre!.trim()
      : 'Sistema';

  String get _entidad {
    final t = item.tablaAfectada;
    if (item.registroId != null && item.registroId!.isNotEmpty) {
      final corto = item.registroId!.length > 8
          ? item.registroId!.substring(0, 8)
          : item.registroId!;
      return '$t · #$corto';
    }
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final color = _accionColor;
    final diff = _computeDiff(item.datosAnteriores, item.datosNuevos);
    final tieneDetalle = diff.isNotEmpty ||
        (item.userAgent != null && item.userAgent!.isNotEmpty) ||
        (item.ip != null && item.ip!.isNotEmpty);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? color.withValues(alpha: 0.25) : Colors.grey.shade200,
        ),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        children: [
          // ── Encabezado (tap para expandir) ──
          InkWell(
            onTap: tieneDetalle ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar con iniciales (icono de acción superpuesto en miniatura)
                  _Avatar(iniciales: _iniciales, color: color, icon: _accionIcon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Frase en lenguaje natural
                        Text.rich(
                          TextSpan(
                            style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: isDark ? Colors.grey.shade200 : Colors.grey.shade800),
                            children: [
                              TextSpan(
                                text: _actor,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              TextSpan(text: ' $_verbo'),
                              if (_muestraEntidad)
                                TextSpan(
                                  text: " '$_entidad'",
                                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Metadatos: timestamp + IP
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 11, color: Colors.grey),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(item.fecha,
                                  style: const TextStyle(color: Colors.grey, fontSize: 10.5),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            if (item.ip != null && item.ip!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.router_outlined, size: 11, color: Colors.grey.shade400),
                              const SizedBox(width: 3),
                              Text('IP: ${item.ip}',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 10.5)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Chips: acción · módulo
                        Row(children: [
                          _chip(item.accion, color, isDark, filled: true),
                          if (item.modulo != null) ...[
                            const SizedBox(width: 6),
                            _chip(item.modulo!, Colors.grey, isDark),
                          ],
                          const Spacer(),
                          if (tieneDetalle)
                            AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(Icons.expand_more_rounded,
                                  size: 20, color: Colors.grey.shade400),
                            ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Accordion: contenido expandible ──
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: tieneDetalle
                ? _buildDetalle(context, isDark, color, diff)
                : const SizedBox(width: double.infinity),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _chip(String txt, Color color, bool isDark, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: filled
            ? color.withValues(alpha: isDark ? 0.18 : 0.12)
            : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 10,
              fontWeight: filled ? FontWeight.w700 : FontWeight.w500,
              color: filled ? color : Colors.grey.shade600,
              letterSpacing: 0.2)),
    );
  }

  Widget _buildDetalle(
      BuildContext context, bool isDark, Color color, List<_DiffRow> diff) {
    final descr = item.descripcion;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 12),

          if (descr != null && descr.isNotEmpty) ...[
            Text(descr,
                style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4)),
            const SizedBox(height: 12),
          ],

          // ── Visual Diff ──
          if (diff.isNotEmpty) ...[
            Row(children: [
              Icon(Icons.compare_arrows_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text('Cambios de datos',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 6),
              Text('(${diff.length})',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            const SizedBox(height: 8),
            _DiffTable(rows: diff, isDark: isDark),
            const SizedBox(height: 12),
          ],

          // ── Detalles contextuales (sub-accordion) ──
          if ((item.userAgent != null && item.userAgent!.isNotEmpty) ||
              (item.ip != null && item.ip!.isNotEmpty))
            _ContextoSection(
              item: item,
              expanded: _ctxExpanded,
              onToggle: () => setState(() => _ctxExpanded = !_ctxExpanded),
              isDark: isDark,
            ),
        ],
      ),
    );
  }
}

// ── Avatar circular con iniciales + mini-badge de acción ──────────────────────

class _Avatar extends StatelessWidget {
  final String iniciales;
  final Color color;
  final IconData icon;
  const _Avatar({required this.iniciales, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 40, height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(iniciales,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          ),
          Positioned(
            bottom: -2, right: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).colorScheme.surface, width: 1.5),
              ),
              child: Icon(icon, size: 9, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tabla comparativa: Campo | Antes | Después ────────────────────────────────

class _DiffTable extends StatelessWidget {
  final List<_DiffRow> rows;
  final bool isDark;
  const _DiffTable({required this.rows, required this.isDark});

  static const _red   = Color(0xFFEF4444);
  static const _green = Color(0xFF8FD11B);

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.grey.withValues(alpha: 0.2);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Cabecera
          Container(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: const [
                Expanded(flex: 4, child: Text('Campo', style: _hStyle)),
                Expanded(flex: 5, child: Text('Antes', style: _hStyle)),
                Expanded(flex: 5, child: Text('Después', style: _hStyle)),
              ],
            ),
          ),
          ...rows.asMap().entries.map((e) {
            final r = e.value;
            final isLast = e.key == rows.length - 1;
            return Container(
              decoration: BoxDecoration(
                border: isLast
                    ? null
                    : Border(bottom: BorderSide(color: borderColor)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(r.campo,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700)),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      r.antes.isEmpty ? '—' : r.antes,
                      style: TextStyle(
                          fontSize: 11,
                          color: r.antes.isEmpty ? Colors.grey.shade400 : _red,
                          decoration: r.kind == _DiffKind.modificado
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: _red.withValues(alpha: 0.5)),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Text(
                      r.despues.isEmpty ? '—' : r.despues,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: r.despues.isEmpty ? Colors.grey.shade400 : _green),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static const _hStyle = TextStyle(
      fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey);
}

// ── Sub-sección colapsable: dispositivo / SO / cliente / IP ───────────────────

class _ContextoSection extends StatelessWidget {
  final AuditoriaItem item;
  final bool expanded;
  final VoidCallback onToggle;
  final bool isDark;
  const _ContextoSection({
    required this.item,
    required this.expanded,
    required this.onToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ua = _parseUserAgent(item.userAgent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Icon(Icons.devices_other_rounded, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text('Detalles contextuales',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500)),
              const Spacer(),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more_rounded, size: 18, color: Colors.grey.shade400),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800.withValues(alpha: 0.4) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _row(Icons.smartphone_rounded, 'Dispositivo', ua.dispositivo),
                _row(Icons.memory_rounded, 'Sistema operativo', ua.so),
                _row(Icons.public_rounded, 'Cliente', ua.cliente),
                if (item.ip != null && item.ip!.isNotEmpty)
                  _row(Icons.router_outlined, 'Dirección IP', item.ip!),
                if (item.userAgent != null && item.userAgent!.isNotEmpty)
                  _row(Icons.code_rounded, 'User-Agent', item.userAgent!, mono: true),
              ],
            ),
          ),
          crossFadeState:
              expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }

  Widget _row(IconData icon, String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontFamily: mono ? 'monospace' : null)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Lógica de soporte (sin estado): diff de JSONB + parser de user-agent
// ══════════════════════════════════════════════════════════════════════════════

enum _AccionCat {
  crear, modificar, eliminar, login, logout, password, flujo, movimiento, peligro, otro,
}

enum _DiffKind { agregado, modificado, eliminado }

class _DiffRow {
  final String campo;
  final String antes;
  final String despues;
  final _DiffKind kind;
  const _DiffRow(this.campo, this.antes, this.despues, this.kind);
}

String _fmtVal(dynamic v) {
  if (v == null) return '';
  if (v is Map || v is List) {
    try { return jsonEncode(v); } catch (_) { return v.toString(); }
  }
  if (v is bool) return v ? 'Sí' : 'No';
  return v.toString();
}

/// Transforma old_state / new_state (JSONB) en filas comparativas.
/// - INSERT (sin anterior): todos los campos como "agregado".
/// - DELETE (sin nuevo): todos los campos como "eliminado".
/// - UPDATE: solo los campos cuyo valor cambió.
List<_DiffRow> _computeDiff(
    Map<String, dynamic>? old, Map<String, dynamic>? nuevo) {
  if (old == null && nuevo == null) return const [];

  final keys = <String>{...?old?.keys, ...?nuevo?.keys}.toList()..sort();
  final rows = <_DiffRow>[];

  for (final k in keys) {
    final hasOld = old != null && old.containsKey(k);
    final hasNew = nuevo != null && nuevo.containsKey(k);
    final ov = _fmtVal(hasOld ? old[k] : null);
    final nv = _fmtVal(hasNew ? nuevo[k] : null);

    if (old == null) {
      rows.add(_DiffRow(k, '', nv, _DiffKind.agregado));
    } else if (nuevo == null) {
      rows.add(_DiffRow(k, ov, '', _DiffKind.eliminado));
    } else if (ov != nv) {
      final kind = !hasOld
          ? _DiffKind.agregado
          : !hasNew
              ? _DiffKind.eliminado
              : _DiffKind.modificado;
      rows.add(_DiffRow(k, ov, nv, kind));
    }
  }
  return rows;
}

class _UAInfo {
  final String dispositivo;
  final String so;
  final String cliente;
  const _UAInfo(this.dispositivo, this.so, this.cliente);
}

/// Extrae dispositivo, sistema operativo y cliente legibles de un user-agent.
_UAInfo _parseUserAgent(String? ua) {
  if (ua == null || ua.trim().isEmpty) {
    return const _UAInfo('Desconocido', 'Desconocido', 'Desconocido');
  }
  final low = ua.toLowerCase();

  // Sistema operativo
  String so = 'Desconocido';
  if (low.contains('android')) {
    final m = RegExp(r'android[ /]([\d.]+)').firstMatch(low);
    so = m != null ? 'Android ${m.group(1)}' : 'Android';
  } else if (low.contains('iphone') || low.contains('ipad') || low.contains('ios')) {
    final m = RegExp(r'os ([\d_]+)').firstMatch(low);
    so = m != null ? 'iOS ${m.group(1)!.replaceAll('_', '.')}' : 'iOS';
  } else if (low.contains('windows')) {
    so = 'Windows';
  } else if (low.contains('mac os') || low.contains('macintosh')) {
    so = 'macOS';
  } else if (low.contains('linux')) {
    so = 'Linux';
  }

  // Cliente / navegador
  String cliente = 'Desconocido';
  if (low.contains('dart')) {
    cliente = 'App E-Zyro (Flutter)';
  } else if (low.contains('okhttp')) {
    cliente = 'App E-Zyro (Android)';
  } else if (low.contains('edg/')) {
    cliente = 'Edge';
  } else if (low.contains('chrome')) {
    cliente = 'Chrome';
  } else if (low.contains('firefox')) {
    cliente = 'Firefox';
  } else if (low.contains('safari')) {
    cliente = 'Safari';
  } else if (low.contains('postman')) {
    cliente = 'Postman';
  }

  // Dispositivo
  String disp = 'Desconocido';
  if (low.contains('dart') || low.contains('okhttp') ||
      low.contains('mobile') || low.contains('android') ||
      low.contains('iphone')) {
    disp = 'Móvil';
  } else if (low.contains('ipad')) {
    disp = 'Tablet';
  } else if (low.contains('windows') || low.contains('macintosh') ||
      low.contains('linux')) {
    disp = 'Escritorio';
  }

  return _UAInfo(disp, so, cliente);
}
