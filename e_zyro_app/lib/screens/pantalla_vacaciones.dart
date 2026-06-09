import 'package:flutter/material.dart';

import '../models/personal_models.dart';
import '../models/vacaciones_models.dart';
import '../services/vacaciones_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Vacaciones por ley (Punto 3.3): configuración del régimen, saldos por
/// empleado y solicitudes con aprobación/rechazo.
class PantallaVacaciones extends StatefulWidget {
  const PantallaVacaciones({super.key});

  @override
  State<PantallaVacaciones> createState() => _PantallaVacacionesState();
}

class _PantallaVacacionesState extends State<PantallaVacaciones> {
  VacacionesService? _svc;
  ConfigVacaciones? _config;
  List<SaldoVacaciones> _saldos = [];
  List<SolicitudVacaciones> _solicitudes = [];
  bool _cargando = true;
  String? _error;

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
    final cfg = await _svc!.obtenerConfig();
    final sal = await _svc!.listarSaldos();
    final sol = await _svc!.listarSolicitudes();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (cfg.ok) _config = cfg.data;
      if (sal.ok) _saldos = sal.data ?? [];
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

  Color _colorEstado(String e) => switch (e) {
        'aprobada' => Colors.green,
        'rechazada' => Colors.red,
        'cancelada' => Colors.grey,
        _ => Colors.orange,
      };

  // ── Config ─────────────────────────────────────────────────────────────────
  Future<void> _editarConfig() async {
    String regimen = _config?.regimen ?? 'general';
    final dias = TextEditingController(text: '${_config?.diasPorAnio ?? 30}');
    final tope = TextEditingController(text: '${_config?.topeAcumulacion ?? 30}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Configuración de vacaciones'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: regimen,
              decoration: const InputDecoration(labelText: 'Régimen'),
              items: const [
                DropdownMenuItem(value: 'general', child: Text('General (30 días/año)')),
                DropdownMenuItem(value: 'remype', child: Text('REMYPE (15 días/año)')),
                DropdownMenuItem(value: 'otro', child: Text('Otro (personalizado)')),
              ],
              onChanged: (v) => setLocal(() {
                regimen = v ?? 'general';
                if (regimen == 'general') dias.text = '30';
                if (regimen == 'remype') dias.text = '15';
              }),
            ),
            TextField(
              controller: dias,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Días por año'),
              enabled: regimen == 'otro',
            ),
            TextField(
              controller: tope,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Tope de acumulación (días)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await _svc!.guardarConfig(
      regimen: regimen,
      diasPorAnio: int.tryParse(dias.text.trim()),
      topeAcumulacion: int.tryParse(tope.text.trim()),
    );
    if (!mounted) return;
    if (res.ok) {
      _snack('Configuración actualizada');
      _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  // ── Nueva solicitud ──────────────────────────────────────────────────────
  Future<void> _nuevaSolicitud() async {
    final esAdmin = AppSession.i.canAprobarVacaciones;
    List<Empleado> empleados = [];
    Empleado? sel;
    if (esAdmin) {
      final ps = await getPersonalService();
      final r = await ps.listar();
      if (r.ok) empleados = r.data ?? [];
      sel = empleados.isNotEmpty ? empleados.first : null;
    }
    DateTime? ini;
    DateTime? fin;
    final motivo = TextEditingController();
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          String fmt(DateTime? d) => d == null
              ? 'Seleccionar'
              : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          Future<void> pick(bool inicio) async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: ctx, initialDate: now,
              firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 2));
            if (d != null) setLocal(() => inicio ? ini = d : fin = d);
          }
          return AlertDialog(
            title: const Text('Solicitar vacaciones'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              if (esAdmin)
                DropdownButtonFormField<Empleado>(
                  initialValue: sel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Empleado'),
                  items: empleados
                      .map((e) => DropdownMenuItem(value: e, child: Text(e.nombre ?? e.id, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setLocal(() => sel = v),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Desde'),
                trailing: Text(fmt(ini)),
                onTap: () => pick(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hasta'),
                trailing: Text(fmt(fin)),
                onTap: () => pick(false),
              ),
              TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo (opcional)')),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Solicitar')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    if (ini == null || fin == null) {
      _snack('Selecciona las fechas', error: true);
      return;
    }
    String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final res = await _svc!.crearSolicitud(
      empleadoId: esAdmin ? sel?.id : null,
      fechaInicio: iso(ini!),
      fechaFin: iso(fin!),
      motivo: motivo.text.trim().isEmpty ? null : motivo.text.trim(),
    );
    if (!mounted) return;
    if (res.ok) {
      _snack('Solicitud creada');
      _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  Future<void> _resolver(SolicitudVacaciones s, bool aprobar) async {
    final res = await _svc!.resolver(s.id, aprobar: aprobar);
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vacaciones', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Saldos'), Tab(text: 'Solicitudes')]),
          actions: [
            if (AppSession.i.canConfigurarVacaciones)
              IconButton(onPressed: _editarConfig, icon: const Icon(Icons.settings_outlined), tooltip: 'Configurar'),
            IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
          ],
        ),
        floatingActionButton: AppSession.i.canSolicitarVacaciones
            ? FloatingActionButton.extended(
                onPressed: _nuevaSolicitud, icon: const Icon(Icons.add), label: const Text('Solicitar'))
            : null,
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_saldosTab(), _solicitudesTab()]),
      ),
    );
  }

  Widget _saldosTab() {
    return Column(
      children: [
        if (_config != null)
          Container(
            width: double.infinity,
            color: Colors.green.withValues(alpha: 0.08),
            padding: const EdgeInsets.all(10),
            child: Text(
              'Régimen: ${_config!.regimen} · ${_config!.diasPorAnio} días/año · tope ${_config!.topeAcumulacion} días',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        Expanded(
          child: _saldos.isEmpty
              ? const Center(child: Text('Sin empleados.'))
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    itemCount: _saldos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final s = _saldos[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.withValues(alpha: 0.15),
                          child: Text(s.disponible.toStringAsFixed(0),
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ),
                        title: Text(s.empleadoNombre ?? s.empleadoId),
                        subtitle: Text(
                            'Disponible: ${s.disponible.toStringAsFixed(1)} d · Devengado: ${s.devengado.toStringAsFixed(1)} · Gozado: ${s.gozado}\n'
                            '${s.mesesServicio} meses de servicio'),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _solicitudesTab() {
    if (_solicitudes.isEmpty) return const Center(child: Text('Sin solicitudes.'));
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _solicitudes.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final s = _solicitudes[i];
          final color = _colorEstado(s.estado);
          final puedeResolver = s.estado == 'pendiente';
          return ListTile(
            leading: Icon(Icons.beach_access_outlined, color: color),
            title: Text(s.empleadoNombre ?? s.empleadoId),
            subtitle: Text('${s.fechaInicio ?? '-'} → ${s.fechaFin ?? '-'} · ${s.dias} día(s)'
                '${s.motivo != null ? '\n${s.motivo}' : ''}'),
            isThreeLine: s.motivo != null,
            trailing: puedeResolver && (AppSession.i.canAprobarVacaciones || AppSession.i.canRechazarVacaciones)
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    if (AppSession.i.canAprobarVacaciones)
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                        tooltip: 'Aprobar',
                        onPressed: () => _resolver(s, true)),
                    if (AppSession.i.canRechazarVacaciones)
                      IconButton(
                        icon: Icon(Icons.cancel_outlined, color: Colors.red.shade400),
                        tooltip: 'Rechazar',
                        onPressed: () => _resolver(s, false)),
                  ])
                : Chip(
                    label: Text(s.estado, style: TextStyle(color: color, fontSize: 11)),
                    backgroundColor: color.withValues(alpha: 0.12),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
          );
        },
      ),
    );
  }
}
