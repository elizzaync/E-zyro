import 'package:flutter/material.dart';

import '../models/calibracion_models.dart';
import '../services/calibracion_service.dart';
import '../utils/api_provider.dart';

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
    final cal = await _svc!.listar();
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
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : TabBarView(children: [_calTab(), _estadoTab()]),
      ),
    );
  }

  Widget _calTab() {
    if (_calibraciones.isEmpty) return const Center(child: Text('Sin calibraciones registradas.'));
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        itemCount: _calibraciones.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = _calibraciones[i];
          return ListTile(
            leading: const Icon(Icons.straighten_outlined),
            title: Text(c.equipoNombre ?? c.equipoId),
            subtitle: Text('Última: ${c.fechaUltima ?? '-'} · Próxima: ${c.fechaProxima ?? '-'}'),
            trailing: c.certificadoUrl != null ? const Icon(Icons.verified_outlined, color: Colors.green) : null,
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
