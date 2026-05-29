import 'package:flutter/material.dart';
import '../models/auditoria_models.dart';
import '../services/auditoria_service.dart';
import '../utils/api_provider.dart';
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
  String? _filtroFechaDesde;
  String? _filtroFechaHasta;

  final _scrollCtrl = ScrollController();

  static const _modulos = [
    'Todos', 'seguridad', 'comunicados', 'operaciones',
    'requerimientos', 'asistencia', 'proyectos',
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

  void _openFiltros() {
    String? modulo = _filtroModulo;
    String? accion = _filtroAccion;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
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
              const Text('Módulo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: modulo ?? 'Todos',
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: _modulos.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setModal(() => modulo = v),
              ),
              const SizedBox(height: 16),
              const Text('Acción', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: accion ?? 'Todas',
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                items: _acciones.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setModal(() => accion = v),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _filtroModulo = null;
                        _filtroAccion = null;
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
      ),
    );
  }

  bool get _hayFiltros =>
      (_filtroModulo != null && _filtroModulo != 'Todos') ||
      (_filtroAccion != null && _filtroAccion != 'Todas') ||
      _filtroFechaDesde != null ||
      _filtroFechaHasta != null;

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
          title: const Text('Registro de Auditoría',
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                        return _AuditoriaCard(item: _items[i]);
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
              onPressed: () {
                setState(() {
                  _filtroModulo = null;
                  _filtroAccion = null;
                  _filtroFechaDesde = null;
                  _filtroFechaHasta = null;
                });
                _load(reset: true);
              },
              child: const Text('Limpiar filtros', style: TextStyle(color: _green)),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Tarjeta de evento de auditoría ────────────────────────────────────────────

class _AuditoriaCard extends StatelessWidget {
  final AuditoriaItem item;
  const _AuditoriaCard({required this.item});

  static const _green  = Color(0xFF8FD11B);  // crear / éxito
  static const _amber  = Color(0xFFF59E0B);  // modificar / password
  static const _blue   = Color(0xFF3B82F6);  // sesión / acceso
  static const _red    = Color(0xFFEF4444);  // eliminar / fallar / rechazar
  static const _purple = Color(0xFF8B5CF6);  // flujo de negocio (aprobar/firmar/entregar)
  static const _teal   = Color(0xFF14B8A6);  // movimiento / transferencia
  static const _gray   = Color(0xFF6B7280);  // logout / consulta

  // Categoría visual de la acción. Se evalúa por palabras-clave de mayor a
  // menor prioridad: lo peligroso (rojo) gana sobre lo neutro.
  static _AccionCat _categoria(String accionRaw) {
    final a = accionRaw.toUpperCase();

    // Errores / accesos bloqueados / rechazos → rojo
    if (a.contains('FAILED') || a.contains('BLOCK') || a.contains('DENIED') ||
        a.contains('RECHAZ') || a.contains('CANCEL')) {
      return _AccionCat.peligro;
    }
    // Eliminación → rojo
    if (a == 'DELETE' || a.contains('ELIMINAR') || a.contains('REMOVER') ||
        a.contains('BAJA')) {
      return _AccionCat.eliminar;
    }
    // Sesión
    if (a.contains('LOGIN') || a.contains('ACCESO')) return _AccionCat.login;
    if (a.contains('LOGOUT'))                         return _AccionCat.logout;
    // Password / recuperación
    if (a.contains('PASSWORD') || a.contains('RECUPERAC')) {
      return _AccionCat.password;
    }
    // Flujo de negocio (logística / operaciones)
    if (a.contains('APROBAR') || a.contains('APROBADO') ||
        a.contains('FIRMAR')  || a.contains('FIRMA')   ||
        a.contains('ENTREGAR')|| a.contains('ENTREGADO')||
        a.contains('FINALIZAR') || a.contains('GENERAR') ||
        a.contains('PUBLICAR')) {
      return _AccionCat.flujo;
    }
    // Movimientos de inventario / transferencias
    if (a.contains('MOVIMIENTO') || a.contains('TRANSFER') ||
        a.contains('AJUSTE')     || a.contains('STOCK')) {
      return _AccionCat.movimiento;
    }
    // Modificación
    if (a == 'UPDATE' || a.contains('ACTUALIZAR') || a.contains('EDITAR') ||
        a.contains('MODIFICAR') || a.contains('CAMBIO')) {
      return _AccionCat.modificar;
    }
    // Creación / inserción
    if (a == 'INSERT' || a.contains('CREAR') || a.contains('AGREGAR') ||
        a.contains('REGISTRAR') || a.contains('NUEVO')) {
      return _AccionCat.crear;
    }
    return _AccionCat.otro;
  }

  Color get _accionColor => switch (_categoria(item.accion)) {
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

  IconData get _accionIcon => switch (_categoria(item.accion)) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final color = _accionColor;

    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.15 : 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(_accionIcon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      item.accion,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  Text(item.fecha,
                      style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ]),
                if (item.usuarioNombre != null) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.person_outline, size: 11, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(item.usuarioNombre!,
                        style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ]),
                ],
                if (item.descripcion != null && item.descripcion!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.descripcion!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(children: [
                  if (item.modulo != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(item.modulo!,
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (item.tablaAfectada.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(item.tablaAfectada,
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    ),
                  if (item.ip != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.router_outlined, size: 10, color: Colors.grey.shade400),
                    const SizedBox(width: 2),
                    Text(item.ip!,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  ],
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AccionCat {
  crear,       // INSERT, CREAR, AGREGAR, REGISTRAR, NUEVO
  modificar,   // UPDATE, ACTUALIZAR, EDITAR, MODIFICAR, CAMBIO
  eliminar,    // DELETE, ELIMINAR, REMOVER, BAJA
  login,       // LOGIN, ACCESO
  logout,      // LOGOUT
  password,    // PASSWORD, RECUPERACIÓN
  flujo,       // APROBAR, FIRMAR, ENTREGAR, FINALIZAR, GENERAR, PUBLICAR
  movimiento,  // MOVIMIENTO, TRANSFERENCIA, AJUSTE, STOCK
  peligro,     // FAILED, BLOCK, DENIED, RECHAZAR, CANCEL
  otro,
}
