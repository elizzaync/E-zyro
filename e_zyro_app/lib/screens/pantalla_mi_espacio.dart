import 'package:flutter/material.dart';

import '../core/api_result.dart';
import '../models/evaluacion_models.dart';
import '../models/vacaciones_models.dart';
import '../services/vacaciones_service.dart';
import '../utils/api_provider.dart';
import '../widgets/vacaciones_gauge.dart';
import 'pantalla_evaluaciones.dart' show DetalleEvaluacionScreen;

/// "Mi espacio" — vista de autoservicio del empleado (sin permisos de RR.HH.):
/// sus vacaciones (saldo + solicitar) y las evaluaciones que le asignaron.
class PantallaMiEspacio extends StatelessWidget {
  const PantallaMiEspacio({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mi espacio', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [
            Tab(text: 'Mis vacaciones'),
            Tab(text: 'Mis evaluaciones'),
          ]),
        ),
        body: const TabBarView(children: [
          _MisVacacionesTab(),
          _MisEvaluacionesTab(),
        ]),
      ),
    );
  }
}

// ─── Mis vacaciones ────────────────────────────────────────────────────────────
class _MisVacacionesTab extends StatefulWidget {
  const _MisVacacionesTab();

  @override
  State<_MisVacacionesTab> createState() => _MisVacacionesTabState();
}

class _MisVacacionesTabState extends State<_MisVacacionesTab> with AutomaticKeepAliveClientMixin {
  VacacionesService? _svc;
  SaldoVacaciones? _saldo;
  List<SolicitudVacaciones> _solicitudes = [];
  bool _cargando = true;
  String? _error;
  bool _sinFicha = false;

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
      _sinFicha = false;
    });
    final sld = await _svc!.miSaldo();
    final sol = await _svc!.misSolicitudes();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (sld.ok) {
        _saldo = sld.data;
      } else if (sld.error?.kind == ApiErrorKind.notFound) {
        // El usuario no tiene ficha de empleado (p. ej. cuenta de sistema):
        // no es un error que mostrar en rojo, sino un estado vacío amable.
        _sinFicha = true;
      } else {
        _error = sld.errorMessage;
      }
      if (sol.ok) _solicitudes = sol.data ?? [];
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

  Future<void> _solicitar() async {
    DateTime? ini;
    DateTime? fin;
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        String fmt(DateTime? d) => d == null
            ? 'Seleccionar'
            : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        Future<void> pick(bool inicio) async {
          final now = DateTime.now();
          final d = await showDatePicker(
              context: ctx, initialDate: now, firstDate: now, lastDate: DateTime(now.year + 2));
          if (d != null) setLocal(() => inicio ? ini = d : fin = d);
        }
        return AlertDialog(
          title: const Text('Solicitar vacaciones'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('Desde'), trailing: Text(fmt(ini)), onTap: () => pick(true)),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('Hasta'), trailing: Text(fmt(fin)), onTap: () => pick(false)),
            TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Solicitar')),
          ],
        );
      }),
    );
    if (ok != true) return;
    if (ini == null || fin == null) {
      _snack('Selecciona las fechas', error: true);
      return;
    }
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final r = await _svc!.crearSolicitud(fechaInicio: iso(ini!), fechaFin: iso(fin!),
        motivo: motivo.text.trim().isEmpty ? null : motivo.text.trim());
    if (!mounted) return;
    if (r.ok) {
      _snack('Solicitud enviada');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_sinFicha) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.badge_outlined, size: 48, color: Colors.black26),
              SizedBox(height: 12),
              Text('Aún no tienes ficha de empleado',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              SizedBox(height: 6),
              Text(
                'Tus vacaciones aparecerán aquí cuando Recursos Humanos\nregistre tu ficha de empleado.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
        ),
      );
    }
    final s = _saldo;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _solicitar, icon: const Icon(Icons.add), label: const Text('Solicitar')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (s != null) ...[
              const SizedBox(height: 12),
              Center(
                child: VacacionesGauge(
                  disponible: s.disponible,
                  max: s.topeAcumulacion.toDouble(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _mini('Devengado', s.devengado.toStringAsFixed(1), Colors.indigo),
                  _mini('Gozado', '${s.gozado}', Colors.orange),
                  _mini('Antigüedad', '${s.mesesServicio} m', Colors.blueGrey),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('Régimen: ${s.diasPorAnio} días/año',
                    style: const TextStyle(color: Colors.black45, fontSize: 12)),
              ),
            ],
            const SizedBox(height: 16),
            const Text('MIS SOLICITUDES', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            if (_solicitudes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Aún no tienes solicitudes.', style: TextStyle(color: Colors.black45)),
              )
            else
              ..._solicitudes.map((sol) {
                final color = _color(sol.estado);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.beach_access_outlined, color: color),
                  title: Text('${sol.fechaInicio ?? '-'} → ${sol.fechaFin ?? '-'} · ${sol.dias} día(s)'),
                  subtitle: sol.motivo != null ? Text(sol.motivo!) : null,
                  trailing: Chip(
                    label: Text(sol.estado, style: TextStyle(color: color, fontSize: 11)),
                    backgroundColor: color.withValues(alpha: 0.12),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _mini(String k, String v, Color c) => Column(children: [
        Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c)),
        Text(k, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]);
}

// ─── Mis evaluaciones ──────────────────────────────────────────────────────────
class _MisEvaluacionesTab extends StatefulWidget {
  const _MisEvaluacionesTab();

  @override
  State<_MisEvaluacionesTab> createState() => _MisEvaluacionesTabState();
}

class _MisEvaluacionesTabState extends State<_MisEvaluacionesTab> with AutomaticKeepAliveClientMixin {
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
    final r = await svc.mias();
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
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_items.isEmpty) {
      return const Center(child: Text('No tienes evaluaciones asignadas.'));
    }
    return RefreshIndicator(
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
            subtitle: Text('${e.fecha ?? '-'} · ${e.estado}'
                '${e.evaluadorNombre != null ? ' · por ${e.evaluadorNombre}' : ''}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => DetalleEvaluacionScreen(evaluacionId: e.id))),
          );
        },
      ),
    );
  }
}
