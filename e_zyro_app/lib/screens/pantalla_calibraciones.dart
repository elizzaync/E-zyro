import 'package:flutter/material.dart';

import '../models/calibracion_models.dart';
import '../models/prestamo_models.dart';
import '../services/calibracion_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import 'pantalla_calibracion_historial.dart';

/// Calibraciones + Estado operativo de equipos (Fase 3).
class PantallaCalibraciones extends StatefulWidget {
  const PantallaCalibraciones({super.key});

  @override
  State<PantallaCalibraciones> createState() => _PantallaCalibracionesState();
}

class _PantallaCalibracionesState extends State<PantallaCalibraciones> {
  CalibracionService? _svc;
  List<Calibracion> _calibraciones = [];
  List<EquipoEstado> _estados = [];
  bool _cargando = true;
  bool _soloPorVencer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getCalibracionService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final cal = await _svc!.listar(porVencer: _soloPorVencer);
    final est = await _svc!.listarEstado(solo: 'inoperativos');
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (cal.ok) {
        _calibraciones = cal.data ?? [];
      } else {
        _error = cal.errorMessage;
      }
      if (est.ok) _estados = est.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  /// Semáforo (color) según la próxima calibración respecto de hoy.
  (Color, String) _semaforo(String? fechaProxima) {
    final f = DateTime.tryParse(fechaProxima ?? '');
    if (f == null) return (Colors.grey, 'Sin próxima');
    final dias = f.difference(DateTime.now()).inDays;
    if (dias < 0) return (Colors.red, 'Vencida');
    if (dias <= 30) return (Colors.orange, 'Por vencer');
    return (Colors.green, 'Vigente');
  }

  /// Selecciona un equipo del catálogo y abre su historial para registrar.
  Future<void> _nuevaCalibracion() async {
    final prestamo = await getPrestamoService();
    final equipos = await prestamo.getCatalogo();
    if (!mounted) return;
    if (equipos.isEmpty) {
      _snack('No hay equipos en el catálogo', error: true);
      return;
    }
    EquipoCatalogo sel = equipos.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Calibrar equipo'),
          content: DropdownButtonFormField<EquipoCatalogo>(
            initialValue: sel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Equipo'),
            items: equipos.map((e) => DropdownMenuItem(value: e, child: Text(e.nombre, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setLocal(() => sel = v ?? sel),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaCalibracionHistorial(equipoId: sel.id, equipoNombre: sel.nombre),
      ),
    );
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Calibraciones', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(tabs: [Tab(text: 'Calibraciones'), Tab(text: 'Inoperativos')]),
          actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
        ),
        floatingActionButton: AppSession.i.canCrearCalibracion
            ? FloatingActionButton.extended(
                onPressed: _nuevaCalibracion, icon: const Icon(Icons.add), label: const Text('Nueva'),
              )
            : null,
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_calTab(), _estadoTab()]),
      ),
    );
  }

  Widget _calTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              avatar: Icon(Icons.notification_important_outlined,
                  size: 18, color: _soloPorVencer ? Colors.orange.shade800 : null),
              label: const Text('Solo por vencer'),
              selected: _soloPorVencer,
              onSelected: (v) {
                setState(() => _soloPorVencer = v);
                _cargar();
              },
            ),
          ),
        ),
        Expanded(
          child: _calibraciones.isEmpty
              ? Center(child: Text(_soloPorVencer
                  ? 'No hay calibraciones por vencer.'
                  : 'Sin calibraciones registradas.'))
              : _lista(),
        ),
      ],
    );
  }

  Widget _lista() {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _calibraciones.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = _calibraciones[i];
          final (color, _) = _semaforo(c.fechaProxima);
          return ListTile(
            leading: Icon(Icons.straighten_outlined, color: color),
            title: Text(c.equipoNombre ?? c.equipoId),
            subtitle: Text('Última: ${c.fechaUltima ?? '-'} · Próxima: ${c.fechaProxima ?? '-'}'
                '${c.totalEventos > 0 ? ' · ${c.totalEventos} calibr.' : ''}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.certificadoUrl != null) const Icon(Icons.verified_outlined, color: Colors.green, size: 18),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PantallaCalibracionHistorial(
                  equipoId: c.equipoId,
                  equipoNombre: c.equipoNombre ?? c.equipoId,
                ),
              ),
            ).then((_) => _cargar()),
          );
        },
      ),
    );
  }

  Widget _estadoTab() {
    if (_estados.isEmpty) return const Center(child: Text('No hay equipos inoperativos.'));
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _estados.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final e = _estados[i];
          return ListTile(
            leading: const Icon(Icons.report_problem_outlined, color: Colors.orange),
            title: Text(e.nombre ?? e.equipoId),
            subtitle: Text('Inoperativos: ${e.cantidadInoperativa} de ${e.cantidad} · ${e.estadoOperativo}'),
          );
        },
      ),
    );
  }
}
