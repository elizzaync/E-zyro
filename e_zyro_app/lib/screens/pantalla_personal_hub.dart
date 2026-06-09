import 'package:flutter/material.dart';

import '../models/personal_models.dart';
import '../models/evaluacion_models.dart';
import '../models/vacaciones_models.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';
import '../services/personal_service.dart';
import '../services/vacaciones_service.dart';
import '../utils/abrir_enlace.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import 'pantalla_evaluaciones.dart' show PantallaEvaluaciones, CrearEvaluacionScreen, DetalleEvaluacionScreen;
import 'pantalla_vacaciones.dart';
import 'pantalla_indicadores.dart';

/// Hub de Personal / RR.HH. (Punto 3): lista de empleados + accesos a los
/// dashboards de empresa (Indicadores, Vacaciones, Evaluaciones). Al tocar un
/// empleado se abre su detalle con pestañas Historial · Evaluaciones · Vacaciones.
class PantallaPersonalHub extends StatefulWidget {
  const PantallaPersonalHub({super.key});

  @override
  State<PantallaPersonalHub> createState() => _PantallaPersonalHubState();
}

class _PantallaPersonalHubState extends State<PantallaPersonalHub> {
  PersonalService? _svc;
  final _busca = TextEditingController();
  List<Empleado> _empleados = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getPersonalService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final r = await _svc!.listar(q: _busca.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _empleados = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal / RR.HH.', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          _accesosEmpresa(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, cargo o código',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _cargar),
              ),
              onSubmitted: (_) => _cargar(),
            ),
          ),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _empleados.isEmpty
                        ? const Center(child: Text('Sin empleados.'))
                        : RefreshIndicator(onRefresh: _cargar, child: _lista()),
          ),
        ],
      ),
    );
  }

  Widget _accesosEmpresa() {
    final chips = <Widget>[];
    if (AppSession.i.canVerIndicadores) {
      chips.add(_chip('Indicadores', Icons.insights_outlined, Colors.indigo,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaIndicadores()))));
    }
    if (AppSession.i.canVerVacaciones) {
      chips.add(_chip('Vacaciones', Icons.beach_access_outlined, Colors.teal,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaVacaciones()))));
    }
    if (AppSession.i.canVerEvaluacion) {
      chips.add(_chip('Evaluaciones', Icons.assessment_outlined, Colors.deepPurple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaEvaluaciones()))));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        onPressed: onTap,
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      );

  Widget _lista() {
    return ListView.separated(
      itemCount: _empleados.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _empleados[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage: (e.fotoUrl != null && e.fotoUrl!.isNotEmpty) ? NetworkImage(e.fotoUrl!) : null,
            child: (e.fotoUrl == null || e.fotoUrl!.isEmpty) ? const Icon(Icons.person_outline) : null,
          ),
          title: Text(e.nombre ?? e.codigo ?? e.id),
          subtitle: Text([e.cargo, e.area].where((s) => s != null && s.isNotEmpty).join(' · ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PantallaEmpleadoDetalle(empleado: e)),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Detalle de empleado con pestañas
// ═══════════════════════════════════════════════════════════════════════════
class PantallaEmpleadoDetalle extends StatelessWidget {
  final Empleado empleado;
  const PantallaEmpleadoDetalle({super.key, required this.empleado});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(empleado.nombre ?? 'Empleado',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [
            Tab(text: 'Historial'),
            Tab(text: 'Evaluaciones'),
            Tab(text: 'Vacaciones'),
          ]),
        ),
        body: TabBarView(children: [
          _HistorialTab(empleado: empleado),
          _EvaluacionesTab(empleado: empleado),
          _VacacionesTab(empleado: empleado),
        ]),
      ),
    );
  }
}

// ─── Tab Historial ────────────────────────────────────────────────────────────
class _HistorialTab extends StatefulWidget {
  final Empleado empleado;
  const _HistorialTab({required this.empleado});

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab> with AutomaticKeepAliveClientMixin {
  HistorialPersonal? _h;
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final svc = await getPersonalService();
    final r = await svc.historial(widget.empleado.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _h = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  Future<void> _exportarPdf() async {
    final h = _h;
    if (h == null) return;
    final bytes = await PdfService.historialPersonal(h);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'historial_personal_${widget.empleado.id}.pdf',
      titulo: 'Historial de personal',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    final h = _h;
    if (h == null) return const Center(child: Text('Sin datos.'));
    final e = h.empleado;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _exportarPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exportar PDF'),
            ),
          ),
          _seccion('Datos del colaborador'),
          _kv('Código', e.codigo),
          _kv('Cargo', e.cargo),
          _kv('Área', e.area),
          _kv('Ingreso', e.fechaIngreso),
          _kv('Fin contrato', e.fechaFinContrato),
          _kv('Estado', e.activo ? 'Activo' : 'Inactivo'),
          _seccion('Resumen de asistencia'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip('Total', h.asistencia.total, Colors.blueGrey),
            _chip('Validados', h.asistencia.validados, Colors.green),
            _chip('Pendientes', h.asistencia.pendientes, Colors.orange),
            _chip('Rechazados', h.asistencia.rechazados, Colors.red),
          ]),
          _seccion('Evaluaciones'),
          _kv('Total', '${h.evaluaciones.total}'),
          _kv('Promedio', h.evaluaciones.promedioGeneral?.toStringAsFixed(2)),
          _kv('Último periodo', h.evaluaciones.ultimoPeriodo),
          _seccion('Contratos (${h.contratos.length})'),
          if (h.contratos.isEmpty) _vacio('Sin contratos.')
          else ...h.contratos.map((c) => ListTile(
                dense: true,
                leading: const Icon(Icons.description_outlined),
                title: Text(c.tipo),
                subtitle: Text('${c.fechaInicio ?? '-'} → ${c.fechaFin ?? '-'} · ${c.estado ?? '-'}'),
              )),
          _seccion('Solicitudes (${h.solicitudes.length})'),
          if (h.solicitudes.isEmpty) _vacio('Sin solicitudes.')
          else ...h.solicitudes.map((s) => ListTile(
                dense: true,
                leading: const Icon(Icons.event_note_outlined),
                title: Text(s.tipo),
                subtitle: Text('${s.fechaInicio ?? '-'} → ${s.fechaFin ?? '-'} · ${s.estado ?? '-'}'),
                trailing: s.urlPdf != null
                    ? IconButton(icon: const Icon(Icons.open_in_new, size: 18), onPressed: () => abrirEnlace(s.urlPdf))
                    : null,
              )),
          _seccion('EPP entregado (${h.epp.length})'),
          if (h.epp.isEmpty) _vacio('Sin entregas.')
          else ...h.epp.map((x) => ListTile(
                dense: true,
                leading: const Icon(Icons.health_and_safety_outlined),
                title: Text('${x.fecha ?? '-'} · ${x.items} ítem(s)'),
                subtitle: Text(x.estado ?? '-'),
              )),
          _seccion('Últimas marcaciones (${h.marcaciones.length})'),
          if (h.marcaciones.isEmpty) _vacio('Sin marcaciones.')
          else ...h.marcaciones.map((m) => ListTile(
                dense: true,
                leading: const Icon(Icons.access_time),
                title: Text(m.tipo),
                subtitle: Text('${m.fechaHora ?? '-'} · ${m.estado ?? '-'}'),
              )),
        ],
      ),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(t.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      );

  Widget _kv(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Colors.black54))),
          Expanded(child: Text((v == null || v.isEmpty) ? '—' : v)),
        ]),
      );

  Widget _chip(String k, int v, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$v', style: TextStyle(fontWeight: FontWeight.bold, color: c, fontSize: 16)),
          const SizedBox(width: 6),
          Text(k, style: const TextStyle(color: Colors.black54)),
        ]),
      );

  Widget _vacio(String t) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(t, style: const TextStyle(color: Colors.black45)));
}

// ─── Tab Evaluaciones (del empleado) ──────────────────────────────────────────
class _EvaluacionesTab extends StatefulWidget {
  final Empleado empleado;
  const _EvaluacionesTab({required this.empleado});

  @override
  State<_EvaluacionesTab> createState() => _EvaluacionesTabState();
}

class _EvaluacionesTabState extends State<_EvaluacionesTab> with AutomaticKeepAliveClientMixin {
  List<Evaluacion> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final svc = await getEvaluacionService();
    final r = await svc.listar(empleadoId: widget.empleado.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _items = r.data ?? [];
      } else {
        _error = r.errorMessage;
      }
    });
  }

  Color _color(String e) => switch (e) {
        'completada' => Colors.green,
        'enviada' => Colors.blue,
        _ => Colors.orange,
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      floatingActionButton: AppSession.i.canCrearEvaluacion
          ? FloatingActionButton.extended(
              onPressed: () async {
                final creada = await Navigator.push<bool>(
                    context, MaterialPageRoute(builder: (_) => CrearEvaluacionScreen(empleadoPre: widget.empleado)));
                if (creada == true) _cargar();
              },
              icon: const Icon(Icons.add),
              label: const Text('Nueva'))
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('Sin evaluaciones de este empleado.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = _items[i];
                          final color = _color(e.estado);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: color.withValues(alpha: 0.15),
                              child: Text(e.promedio?.toStringAsFixed(1) ?? '—',
                                  style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                            title: Text('Periodo: ${e.periodo}'),
                            subtitle: Text('${e.fecha ?? '-'} · ${e.estado}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final cambio = await Navigator.push<bool>(context,
                                  MaterialPageRoute(builder: (_) => DetalleEvaluacionScreen(evaluacionId: e.id)));
                              if (cambio == true) _cargar();
                            },
                          );
                        },
                      ),
                    ),
    );
  }
}

// ─── Tab Vacaciones (del empleado) ────────────────────────────────────────────
class _VacacionesTab extends StatefulWidget {
  final Empleado empleado;
  const _VacacionesTab({required this.empleado});

  @override
  State<_VacacionesTab> createState() => _VacacionesTabState();
}

class _VacacionesTabState extends State<_VacacionesTab> with AutomaticKeepAliveClientMixin {
  VacacionesService? _svc;
  SaldoVacaciones? _saldo;
  List<SolicitudVacaciones> _solicitudes = [];
  bool _cargando = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getVacacionesService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final sld = await _svc!.listarSaldos();
    final sol = await _svc!.listarSolicitudes(empleadoId: widget.empleado.id);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (sld.ok) {
        final lista = sld.data ?? [];
        _saldo = lista.where((s) => s.empleadoId == widget.empleado.id).firstOrNull;
      }
      if (sol.ok) {
        _solicitudes = sol.data ?? [];
      } else {
        _error = sol.errorMessage;
      }
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Color _color(String e) => switch (e) {
        'aprobada' => Colors.green,
        'rechazada' => Colors.red,
        'cancelada' => Colors.grey,
        _ => Colors.orange,
      };

  Future<void> _resolver(SolicitudVacaciones s, bool aprobar) async {
    final r = await _svc!.resolver(s.id, aprobar: aprobar);
    if (!mounted) return;
    r.ok ? _cargar() : _snack(r.errorMessage, error: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (_saldo != null) _tarjetaSaldo(_saldo!),
            const SizedBox(height: 8),
            const Text('SOLICITUDES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            if (_solicitudes.isEmpty)
              const Padding(padding: EdgeInsets.all(12), child: Text('Sin solicitudes.', style: TextStyle(color: Colors.black45)))
            else
              ..._solicitudes.map(_filaSolicitud),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaSaldo(SaldoVacaciones s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.disponible.toStringAsFixed(1)} días',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.teal)),
            const Text('disponibles', style: TextStyle(color: Colors.black54)),
          ]),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Devengado: ${s.devengado.toStringAsFixed(1)}'),
            Text('Gozado: ${s.gozado}'),
            Text('${s.mesesServicio} meses · tope ${s.topeAcumulacion}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ]),
      );

  Widget _filaSolicitud(SolicitudVacaciones s) {
    final color = _color(s.estado);
    final puedeResolver = s.estado == 'pendiente' &&
        (AppSession.i.canAprobarVacaciones || AppSession.i.canRechazarVacaciones);
    return ListTile(
      leading: Icon(Icons.beach_access_outlined, color: color),
      title: Text('${s.fechaInicio ?? '-'} → ${s.fechaFin ?? '-'} · ${s.dias} día(s)'),
      subtitle: s.motivo != null ? Text(s.motivo!) : null,
      trailing: puedeResolver
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              if (AppSession.i.canAprobarVacaciones)
                IconButton(icon: const Icon(Icons.check_circle_outline, color: Colors.green), onPressed: () => _resolver(s, true)),
              if (AppSession.i.canRechazarVacaciones)
                IconButton(icon: Icon(Icons.cancel_outlined, color: Colors.red.shade400), onPressed: () => _resolver(s, false)),
            ])
          : Chip(
              label: Text(s.estado, style: TextStyle(color: color, fontSize: 11)),
              backgroundColor: color.withValues(alpha: 0.12),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
    );
  }
}
