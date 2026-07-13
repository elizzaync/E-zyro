import 'package:flutter/material.dart';

import '../models/auditoria_models.dart';
import '../services/auditoria_service.dart';
import '../utils/api_provider.dart';

/// Auditoría General — SOLO SuperAdmin.
/// 3 pestañas: Acciones (cross-empresa), Errores (log_sistema) y Estadísticas.
class PantallaAuditoriaGeneral extends StatefulWidget {
  const PantallaAuditoriaGeneral({super.key});

  @override
  State<PantallaAuditoriaGeneral> createState() =>
      _PantallaAuditoriaGeneralState();
}

class _PantallaAuditoriaGeneralState extends State<PantallaAuditoriaGeneral>
    with SingleTickerProviderStateMixin {
  static const _green = Color(0xFF8FD11B);
  static const _greenDark = Color(0xFF1E9462);
  static const _pageSize = 50;

  late final TabController _tabCtrl;
  AuditoriaService? _service;

  // ── Pestaña Acciones ──
  List<AuditoriaGeneralItem> _acciones = [];
  bool _loadingAcciones = true;
  bool _masAcciones = true;
  String? _errorAcciones;
  String _filtroModulo = 'Todos';
  String _busqueda = '';
  final _busquedaCtrl = TextEditingController();

  static const _modulos = [
    'Todos',
    'SEGURIDAD', 'OPERACIONES', 'ASISTENCIA', 'REQUERIMIENTOS',
    'INVENTARIO', 'COMPRAS', 'CLIENTES', 'FINANZAS', 'MANTENIMIENTO',
    'COMUNICADOS', 'USUARIOS', 'EMPLEADOS', 'EMPRESA', 'RRHH',
  ];

  // ── Pestaña Errores ──
  List<LogSistemaItem> _logs = [];
  bool _loadingLogs = true;
  bool _masLogs = true;
  String? _errorLogs;
  String _filtroNivel = 'Todos';

  // ── Pestaña Estadísticas ──
  AuditoriaStats? _stats;
  bool _loadingStats = true;
  String? _errorStats;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getAuditoriaService();
    await Future.wait([
      _cargarAcciones(reset: true),
      _cargarLogs(reset: true),
      _cargarStats(),
    ]);
  }

  // ── Carga de datos ──────────────────────────────────────────────────────────

  Future<void> _cargarAcciones({bool reset = false}) async {
    final s = _service;
    if (s == null) return;
    if (reset) {
      setState(() {
        _loadingAcciones = true;
        _errorAcciones = null;
        if (reset) _acciones = [];
      });
    }
    final r = await s.getAuditoriaGeneral(
      modulo: _filtroModulo == 'Todos' ? null : _filtroModulo,
      q: _busqueda.isEmpty ? null : _busqueda,
      limit: _pageSize,
      offset: reset ? 0 : _acciones.length,
    );
    if (!mounted) return;
    setState(() {
      _loadingAcciones = false;
      if (r.ok) {
        final nuevos = r.data ?? [];
        _acciones = reset ? nuevos : [..._acciones, ...nuevos];
        _masAcciones = nuevos.length >= _pageSize;
      } else {
        _errorAcciones = r.errorMessage;
      }
    });
  }

  Future<void> _cargarLogs({bool reset = false}) async {
    final s = _service;
    if (s == null) return;
    if (reset) {
      setState(() {
        _loadingLogs = true;
        _errorLogs = null;
        _logs = [];
      });
    }
    final r = await s.getLogsSistema(
      nivel: _filtroNivel == 'Todos' ? null : _filtroNivel.toLowerCase(),
      limit: _pageSize,
      offset: reset ? 0 : _logs.length,
    );
    if (!mounted) return;
    setState(() {
      _loadingLogs = false;
      if (r.ok) {
        final nuevos = r.data ?? [];
        _logs = reset ? nuevos : [..._logs, ...nuevos];
        _masLogs = nuevos.length >= _pageSize;
      } else {
        _errorLogs = r.errorMessage;
      }
    });
  }

  Future<void> _cargarStats() async {
    final s = _service;
    if (s == null) return;
    setState(() {
      _loadingStats = true;
      _errorStats = null;
    });
    final r = await s.getStats();
    if (!mounted) return;
    setState(() {
      _loadingStats = false;
      if (r.ok) {
        _stats = r.data;
      } else {
        _errorStats = r.errorMessage;
      }
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría General',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: isDark ? const Color(0xFF1E9462) : _greenDark,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.7),
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_outlined, size: 20), text: 'Acciones'),
            Tab(icon: Icon(Icons.error_outline, size: 20), text: 'Errores'),
            Tab(icon: Icon(Icons.bar_chart_outlined, size: 20), text: 'Estadísticas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildTabAcciones(),
          _buildTabErrores(),
          _buildTabStats(),
        ],
      ),
    );
  }

  // ── Pestaña 1: Acciones ─────────────────────────────────────────────────────

  Widget _buildTabAcciones() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _busquedaCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar en descripción…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _busqueda.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _busquedaCtrl.clear();
                        _busqueda = '';
                        _cargarAcciones(reset: true);
                      },
                    )
                  : null,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) {
              _busqueda = v.trim();
              _cargarAcciones(reset: true);
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: _modulos.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final m = _modulos[i];
              final sel = m == _filtroModulo;
              return ChoiceChip(
                label: Text(m, style: const TextStyle(fontSize: 12)),
                selected: sel,
                selectedColor: _green.withValues(alpha: 0.30),
                onSelected: (_) {
                  setState(() => _filtroModulo = m);
                  _cargarAcciones(reset: true);
                },
              );
            },
          ),
        ),
        Expanded(
          child: _loadingAcciones
              ? const Center(child: CircularProgressIndicator(color: _green))
              : _errorAcciones != null
                  ? _buildError(_errorAcciones!, () => _cargarAcciones(reset: true))
                  : _acciones.isEmpty
                      ? _buildVacio('Sin acciones registradas')
                      : RefreshIndicator(
                          color: _green,
                          onRefresh: () => _cargarAcciones(reset: true),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemCount: _acciones.length + (_masAcciones ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= _acciones.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.expand_more, size: 18),
                                      label: const Text('Cargar más'),
                                      onPressed: () => _cargarAcciones(),
                                    ),
                                  ),
                                );
                              }
                              return _buildAccionCard(_acciones[i]);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildAccionCard(AuditoriaGeneralItem a) {
    final surface = Theme.of(context).colorScheme.surface;
    return Card(
      color: surface,
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: _colorAccion(a.accion).withValues(alpha: 0.15),
          child: Icon(_iconoAccion(a.accion),
              size: 17, color: _colorAccion(a.accion)),
        ),
        title: Text(
          a.descripcion?.isNotEmpty == true
              ? a.descripcion!
              : '${a.accion} · ${a.tablaAfectada}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (a.usuarioNombre?.isNotEmpty == true)
                _miniDato(Icons.person_outline, a.usuarioNombre!),
              if (a.empresaNombre?.isNotEmpty == true)
                _miniDato(Icons.business_outlined, a.empresaNombre!),
              _miniDato(Icons.schedule, a.fecha),
            ],
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chipInfo('Módulo: ${a.modulo ?? "—"}'),
                _chipInfo('Acción: ${a.accion}'),
                _chipInfo('Tabla: ${a.tablaAfectada}'),
                if (a.ip != null) _chipInfo('IP: ${a.ip}'),
              ],
            ),
          ),
          if (a.descripcion?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(a.descripcion!, style: const TextStyle(fontSize: 12.5)),
            ),
          ],
          if (a.datosAnteriores != null && a.datosAnteriores!.isNotEmpty)
            _bloqueDatos('Datos anteriores', a.datosAnteriores!),
          if (a.datosNuevos != null && a.datosNuevos!.isNotEmpty)
            _bloqueDatos('Datos nuevos', a.datosNuevos!),
        ],
      ),
    );
  }

  Widget _bloqueDatos(String titulo, Map<String, dynamic> datos) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ...datos.entries.take(20).map(
                  (e) => Text('${e.key}: ${e.value}',
                      style: const TextStyle(
                          fontSize: 11.5, fontFamily: 'monospace')),
                ),
          ],
        ),
      ),
    );
  }

  Widget _miniDato(IconData icon, String texto) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 2),
        Text(texto,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _chipInfo(String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(texto,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  IconData _iconoAccion(String accion) {
    final a = accion.toUpperCase();
    if (a.contains('INSERT') || a.contains('CREAR')) return Icons.add_circle_outline;
    if (a.contains('UPDATE') || a.contains('EDITAR')) return Icons.edit_outlined;
    if (a.contains('DELETE') || a.contains('ELIMINAR')) return Icons.delete_outline;
    if (a.contains('LOGIN')) return Icons.login;
    if (a.contains('LOGOUT')) return Icons.logout;
    return Icons.bolt_outlined;
  }

  Color _colorAccion(String accion) {
    final a = accion.toUpperCase();
    if (a.contains('DELETE') || a.contains('ELIMINAR')) return Colors.red;
    if (a.contains('UPDATE') || a.contains('EDITAR')) return Colors.orange;
    if (a.contains('INSERT') || a.contains('CREAR')) return _greenDark;
    return Colors.blueGrey;
  }

  // ── Pestaña 2: Errores ──────────────────────────────────────────────────────

  Widget _buildTabErrores() {
    const niveles = ['Todos', 'error', 'warning', 'info'];
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: niveles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final n = niveles[i];
              final sel = n == _filtroNivel;
              return ChoiceChip(
                label: Text(n == 'Todos' ? 'Todos' : n.toUpperCase(),
                    style: const TextStyle(fontSize: 12)),
                selected: sel,
                selectedColor: _colorNivel(n).withValues(alpha: 0.25),
                onSelected: (_) {
                  setState(() => _filtroNivel = n);
                  _cargarLogs(reset: true);
                },
              );
            },
          ),
        ),
        Expanded(
          child: _loadingLogs
              ? const Center(child: CircularProgressIndicator(color: _green))
              : _errorLogs != null
                  ? _buildError(_errorLogs!, () => _cargarLogs(reset: true))
                  : _logs.isEmpty
                      ? _buildVacio('Sin errores registrados')
                      : RefreshIndicator(
                          color: _green,
                          onRefresh: () => _cargarLogs(reset: true),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                            itemCount: _logs.length + (_masLogs ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= _logs.length) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.expand_more, size: 18),
                                      label: const Text('Cargar más'),
                                      onPressed: () => _cargarLogs(),
                                    ),
                                  ),
                                );
                              }
                              return _buildLogCard(_logs[i]);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Color _colorNivel(String nivel) {
    switch (nivel.toLowerCase()) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.amber.shade800;
      case 'info':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildLogCard(LogSistemaItem l) {
    final surface = Theme.of(context).colorScheme.surface;
    final color = _colorNivel(l.nivel);
    return Card(
      color: surface,
      elevation: 0.5,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
            l.nivel == 'warning'
                ? Icons.warning_amber_outlined
                : l.nivel == 'info'
                    ? Icons.info_outline
                    : Icons.error_outline,
            size: 17,
            color: color,
          ),
        ),
        title: Text(
          l.mensaje,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(l.nivel.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
              _miniDato(Icons.schedule, l.fecha),
              if (l.origen != null)
                _miniDato(Icons.route_outlined,
                    '${l.metodo ?? ''} ${l.origen}'.trim()),
            ],
          ),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (l.statusCode != null) _chipInfo('HTTP ${l.statusCode}'),
                if (l.metodo != null) _chipInfo('Método: ${l.metodo}'),
                if (l.origen != null) _chipInfo('Origen: ${l.origen}'),
              ],
            ),
          ),
          if (l.detalle?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l.detalle!,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Pestaña 3: Estadísticas ─────────────────────────────────────────────────

  Widget _buildTabStats() {
    if (_loadingStats) {
      return const Center(child: CircularProgressIndicator(color: _green));
    }
    if (_errorStats != null) {
      return _buildError(_errorStats!, _cargarStats);
    }
    final s = _stats;
    if (s == null) return _buildVacio('Sin estadísticas');

    final maxModulo = s.porModulo.isEmpty
        ? 1
        : s.porModulo.map((e) => e.cantidad).reduce((a, b) => a > b ? a : b);
    final maxDia = s.porDia.isEmpty
        ? 1
        : s.porDia.map((e) => e.cantidad).reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      color: _green,
      onRefresh: _cargarStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _statCard('Acciones (30 días)', '${s.totalAcciones}',
                    Icons.list_alt_outlined, _greenDark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard('Errores (30 días)', '${s.totalErrores}',
                    Icons.error_outline, Colors.red),
              ),
            ],
          ),
          if (s.erroresPorNivel.isNotEmpty) ...[
            const SizedBox(height: 14),
            _tituloSeccion('Errores por nivel'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: s.erroresPorNivel
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _colorNivel(e.nombre).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _colorNivel(e.nombre)
                                  .withValues(alpha: 0.40)),
                        ),
                        child: Text(
                          '${e.nombre.toUpperCase()}: ${e.cantidad}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _colorNivel(e.nombre),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 18),
          _tituloSeccion('Actividad por módulo (top 10)'),
          const SizedBox(height: 8),
          if (s.porModulo.isEmpty)
            const Text('Sin datos', style: TextStyle(color: Colors.grey)),
          ...s.porModulo.map((m) => _barraModulo(m, maxModulo)),
          const SizedBox(height: 18),
          _tituloSeccion('Acciones por tipo'),
          const SizedBox(height: 8),
          if (s.porAccion.isEmpty)
            const Text('Sin datos', style: TextStyle(color: Colors.grey)),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: s.porAccion
                .map((a) => _chipInfo('${a.nombre}: ${a.cantidad}'))
                .toList(),
          ),
          const SizedBox(height: 18),
          _tituloSeccion('Actividad por día'),
          const SizedBox(height: 8),
          if (s.porDia.isEmpty)
            const Text('Sin datos', style: TextStyle(color: Colors.grey)),
          ...s.porDia.map((d) => _barraDia(d, maxDia)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statCard(String titulo, String valor, IconData icon, Color color) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(valor,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(titulo,
              style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _tituloSeccion(String titulo) {
    return Text(
      titulo.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Colors.grey,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _barraModulo(ConteoStat m, int max) {
    final frac = max <= 0 ? 0.0 : (m.cantidad / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(m.nombre,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${m.cantidad}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 7,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation<Color>(_green),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraDia(ConteoStat d, int max) {
    final frac = max <= 0 ? 0.0 : (d.cantidad / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(d.nombre,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: Colors.grey.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(
                    _greenDark.withValues(alpha: 0.85)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text('${d.cantidad}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Comunes ─────────────────────────────────────────────────────────────────

  Widget _buildError(String mensaje, Future<void> Function() reintentar) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 44, color: Colors.grey),
            const SizedBox(height: 10),
            Text(mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
              onPressed: () => reintentar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVacio(String mensaje) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 44, color: Colors.grey),
          const SizedBox(height: 8),
          Text(mensaje,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}
