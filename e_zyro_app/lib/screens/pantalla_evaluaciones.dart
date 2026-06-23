import 'package:flutter/material.dart';

import '../models/evaluacion_models.dart';
import '../models/personal_models.dart';
import '../services/evaluacion_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import 'pantalla_plantillas_evaluacion.dart';

/// Evaluaciones de desempeño (Punto 3.2): lista, creación con puntuación de
/// criterios y flujo borrador → enviada → completada.
class PantallaEvaluaciones extends StatefulWidget {
  const PantallaEvaluaciones({super.key});

  @override
  State<PantallaEvaluaciones> createState() => _PantallaEvaluacionesState();
}

class _PantallaEvaluacionesState extends State<PantallaEvaluaciones> {
  EvaluacionService? _svc;
  List<Evaluacion> _items = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getEvaluacionService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final r = await _svc!.listar();
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

  Future<void> _nueva() async {
    final creada = await Navigator.push<bool>(
      context, MaterialPageRoute(builder: (_) => const CrearEvaluacionScreen()));
    if (creada == true) _cargar();
  }

  Color _colorEstado(String e) => switch (e) {
        'completada' => Colors.green,
        'enviada' => Colors.blue,
        _ => Colors.orange,
      };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Evaluaciones', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [
            Tab(text: 'Evaluaciones'),
            Tab(text: 'Plantillas'),
            Tab(text: 'Criterios'),
          ]),
          actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
        ),
        body: const TabBarView(children: [
          _EvaluacionesTabBody(),
          PantallaPlantillasEvaluacion(),
          CriteriosTab(),
        ]),
      ),
    );
  }

  Widget _evaluacionesTab() {
    return Scaffold(
      floatingActionButton: AppSession.i.canCrearEvaluacion
          ? FloatingActionButton.extended(onPressed: _nueva, icon: const Icon(Icons.add), label: const Text('Nueva'))
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('Sin evaluaciones.'))
                  : RefreshIndicator(onRefresh: _cargar, child: _lista()),
    );
  }

  Widget _lista() {
    return ListView.separated(
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = _items[i];
        final color = _colorEstado(e.estado);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(e.promedio?.toStringAsFixed(1) ?? '—',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          title: Text(e.empleadoNombre ?? e.empleadoId),
          subtitle: Text('Periodo: ${e.periodo} · ${e.fecha ?? '-'}'),
          trailing: Chip(
            label: Text(e.estado, style: TextStyle(color: color, fontSize: 11)),
            backgroundColor: color.withValues(alpha: 0.12),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
          onTap: () async {
            final cambio = await Navigator.push<bool>(
              context, MaterialPageRoute(builder: (_) => DetalleEvaluacionScreen(evaluacionId: e.id)));
            if (cambio == true) _cargar();
          },
        );
      },
    );
  }
}

// ─── Crear evaluación ─────────────────────────────────────────────────────────
class CrearEvaluacionScreen extends StatefulWidget {
  /// Si se indica, la evaluación se crea para este empleado (preseleccionado).
  final Empleado? empleadoPre;

  /// Tipo de evaluación a realizar (rrhh|jefe_directo|companero).
  final String tipo;
  const CrearEvaluacionScreen({super.key, this.empleadoPre, this.tipo = TipoEvaluacion.rrhh});

  @override
  State<CrearEvaluacionScreen> createState() => _CrearEvaluacionScreenState();
}

class _CrearEvaluacionScreenState extends State<CrearEvaluacionScreen> {
  final _periodo = TextEditingController();
  List<Empleado> _empleados = [];
  List<CriterioEvaluacion> _criterios = [];
  Empleado? _sel;
  final Map<String, int> _puntajes = {};
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _periodo.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ps = await getPersonalService();
    final es = await getEvaluacionService();
    final emp = await ps.listar();
    final crit = await es.listarCriterios(tipo: widget.tipo);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (emp.ok) _empleados = emp.data ?? [];
      if (crit.ok) {
        _criterios = crit.data ?? [];
        for (final c in _criterios) {
          _puntajes[c.id] = 7;
        }
      }
      final pre = widget.empleadoPre;
      if (pre != null) {
        _sel = _empleados.where((e) => e.id == pre.id).firstOrNull ?? pre;
        if (_empleados.where((e) => e.id == pre.id).isEmpty) _empleados = [pre, ..._empleados];
      } else {
        _sel = _empleados.isNotEmpty ? _empleados.first : null;
      }
      if (!emp.ok) _error = emp.errorMessage;
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _guardar() async {
    if (_sel == null) {
      _snack('Selecciona un empleado', error: true);
      return;
    }
    if (_periodo.text.trim().isEmpty) {
      _snack('Indica el periodo (ej. 2026-S1)', error: true);
      return;
    }
    if (_criterios.isEmpty) {
      _snack('No hay criterios definidos. Crea criterios primero.', error: true);
      return;
    }
    setState(() => _guardando = true);
    final svc = await getEvaluacionService();
    final detalles = _criterios
        .map((c) => DetalleEvaluacion(criterioId: c.id, puntaje: _puntajes[c.id] ?? 7))
        .toList();
    final r = await svc.crear(
      empleadoId: _sel!.id, periodo: _periodo.text.trim(),
      tipo: widget.tipo, detalles: detalles);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(TipoEvaluacion.etiqueta(widget.tipo))),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<Empleado>(
                      initialValue: _sel,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Empleado a evaluar'),
                      items: _empleados
                          .map((e) => DropdownMenuItem(value: e, child: Text(e.nombre ?? e.id, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _sel = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _periodo,
                      decoration: const InputDecoration(labelText: 'Periodo (ej. 2026-S1)'),
                    ),
                    const SizedBox(height: 16),
                    const Text('Criterios', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (_criterios.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No hay criterios definidos para la empresa.',
                            style: TextStyle(color: Colors.black54)),
                      )
                    else
                      ..._criterios.map(_criterioTile),
                  ],
                ),
      bottomNavigationBar: _criterios.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _guardando ? null : _guardar,
                  icon: _guardando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Guardar borrador'),
                ),
              ),
            ),
    );
  }

  Widget _criterioTile(CriterioEvaluacion c) {
    final v = _puntajes[c.id] ?? 7;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.nombre, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('peso ${c.peso.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
              const SizedBox(width: 8),
              Container(
                width: 34, alignment: Alignment.center,
                child: Text('$v', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ],
          ),
          Slider(
            value: v.toDouble(), min: 1, max: 10, divisions: 9, label: '$v',
            onChanged: (nv) => setState(() => _puntajes[c.id] = nv.round()),
          ),
        ],
      ),
    );
  }
}

// ─── Detalle de evaluación ────────────────────────────────────────────────────
class DetalleEvaluacionScreen extends StatefulWidget {
  final String evaluacionId;
  const DetalleEvaluacionScreen({super.key, required this.evaluacionId});

  @override
  State<DetalleEvaluacionScreen> createState() => _DetalleEvaluacionScreenState();
}

class _DetalleEvaluacionScreenState extends State<DetalleEvaluacionScreen> {
  Evaluacion? _e;
  bool _cargando = true;
  bool _cambio = false;
  String? _error;

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
    final r = await svc.detalle(widget.evaluacionId);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) {
        _e = r.data;
      } else {
        _error = r.errorMessage;
      }
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _transicion(String estado) async {
    final svc = await getEvaluacionService();
    final r = await svc.cambiarEstado(widget.evaluacionId, estado);
    if (!mounted) return;
    if (r.ok) {
      _cambio = true;
      _snack(estado == 'enviada' ? 'Evaluación enviada' : 'Evaluación completada');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _eliminar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evaluación'),
        content: const Text('¿Eliminar esta evaluación?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    final svc = await getEvaluacionService();
    final r = await svc.eliminar(widget.evaluacionId);
    if (!mounted) return;
    if (r.ok) {
      Navigator.pop(context, true);
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _cambio);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Evaluación'),
          leading: IconButton(
            icon: const BackButtonIcon(),
            onPressed: () => Navigator.pop(context, _cambio),
          ),
          actions: [
            if (_e != null && AppSession.i.canEliminarEvaluacion)
              IconButton(onPressed: _eliminar, icon: const Icon(Icons.delete_outline)),
          ],
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _e == null
                    ? const Center(child: Text('Sin datos.'))
                    : _contenido(_e!),
        bottomNavigationBar: _e == null ? null : _acciones(_e!),
      ),
    );
  }

  Widget _contenido(Evaluacion e) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(e.empleadoNombre ?? e.empleadoId,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Periodo: ${e.periodo} · Estado: ${e.estado}'),
        Text('Evaluador: ${e.evaluadorNombre ?? '-'} · Fecha: ${e.fecha ?? '-'}'),
        const SizedBox(height: 8),
        Row(children: [
          const Text('Promedio ponderado: ', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(e.promedio?.toStringAsFixed(2) ?? '—',
              style: const TextStyle(fontSize: 18, color: Colors.green, fontWeight: FontWeight.bold)),
          const Text(' / 10'),
        ]),
        const Divider(height: 24),
        const Text('Criterios', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        ...e.detalles.map((d) => ListTile(
              dense: true,
              title: Text(d.criterioNombre ?? d.criterioId),
              subtitle: d.comentario != null ? Text(d.comentario!) : null,
              trailing: Text('${d.puntaje}/10',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            )),
      ],
    );
  }

  Widget? _acciones(Evaluacion e) {
    final botones = <Widget>[];
    if (e.estado == 'borrador' && AppSession.i.canEnviarEvaluacion) {
      botones.add(Expanded(
        child: FilledButton.icon(
          onPressed: () => _transicion('enviada'),
          icon: const Icon(Icons.send), label: const Text('Enviar')),
      ));
    }
    if (e.estado == 'enviada' && AppSession.i.canCompletarEvaluacion) {
      botones.add(Expanded(
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
          onPressed: () => _transicion('completada'),
          icon: const Icon(Icons.check_circle_outline), label: const Text('Completar')),
      ));
    }
    if (botones.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: botones),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Gestión de criterios de evaluación (catálogo de la empresa)
// ═══════════════════════════════════════════════════════════════════════════
class CriteriosTab extends StatefulWidget {
  /// Tipo de evaluación cuyos criterios gestiona esta pestaña.
  final String tipo;
  const CriteriosTab({super.key, this.tipo = TipoEvaluacion.rrhh});

  @override
  State<CriteriosTab> createState() => _CriteriosTabState();
}

class _CriteriosTabState extends State<CriteriosTab> {
  List<CriterioEvaluacion> _items = [];
  bool _cargando = true;
  String? _error;

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
    final r = await svc.listarCriterios(tipo: widget.tipo);
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

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _nuevo() async {
    final nombre = TextEditingController();
    final desc = TextEditingController();
    final peso = TextEditingController(text: '1.0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo criterio'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nombre, decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción (opcional)')),
          TextField(
            controller: peso,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Peso (ponderación)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    if (nombre.text.trim().isEmpty) {
      _snack('El nombre es obligatorio', error: true);
      return;
    }
    final svc = await getEvaluacionService();
    final r = await svc.crearCriterio(
      nombre: nombre.text.trim(),
      descripcion: desc.text.trim().isEmpty ? null : desc.text.trim(),
      peso: double.tryParse(peso.text.trim()) ?? 1.0,
      tipo: widget.tipo,
    );
    if (!mounted) return;
    r.ok ? _cargar() : _snack(r.errorMessage, error: true);
  }

  Future<void> _eliminar(CriterioEvaluacion c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar criterio'),
        content: Text('¿Eliminar "${c.nombre}"? Las evaluaciones pasadas lo conservan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    final svc = await getEvaluacionService();
    final r = await svc.eliminarCriterio(c.id);
    if (!mounted) return;
    r.ok ? _cargar() : _snack(r.errorMessage, error: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: AppSession.i.canCrearEvaluacion
          ? FloatingActionButton.extended(onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text('Criterio'))
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _items.isEmpty
                  ? const Center(child: Text('Sin criterios. Crea el primero con el botón +.'))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final c = _items[i];
                          return ListTile(
                            leading: const Icon(Icons.checklist_outlined),
                            title: Text(c.nombre),
                            subtitle: c.descripcion != null ? Text(c.descripcion!) : null,
                            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                              Chip(
                                label: Text('peso ${c.peso.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                              ),
                              if (AppSession.i.canEliminarEvaluacion)
                                IconButton(
                                  icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
                                  onPressed: () => _eliminar(c)),
                            ]),
                          );
                        },
                      ),
                    ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Configuración de evaluaciones: arma los criterios de cada uno de los 3 tipos.
// (Botón superior del módulo de Personal/RR.HH.)
// ═══════════════════════════════════════════════════════════════════════════
class ConfigEvaluacionesScreen extends StatelessWidget {
  const ConfigEvaluacionesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: TipoEvaluacion.todos.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Config. Evaluaciones',
              style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              for (final t in TipoEvaluacion.todos)
                Tab(text: TipoEvaluacion.etiquetaCorta(t)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in TipoEvaluacion.todos)
              Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Criterios de la ${TipoEvaluacion.etiqueta(t)}. '
                      'Estos forman el formulario que se aplicará al asignarla a un colaborador.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Expanded(child: CriteriosTab(tipo: t)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
