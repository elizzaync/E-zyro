import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/calibracion_models.dart';
import '../models/prestamo_models.dart';
import '../services/calibracion_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Calibraciones + Estado operativo de equipos (Fase 3).
class PantallaCalibraciones extends StatefulWidget {
  const PantallaCalibraciones({super.key});

  @override
  State<PantallaCalibraciones> createState() => _PantallaCalibracionesState();
}

class _PantallaCalibracionesState extends State<PantallaCalibraciones> {
  CalibracionService? _svc;
  final _picker = ImagePicker();
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

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _nuevaCalibracion() async {
    final prestamo = await getPrestamoService();
    final equipos = await prestamo.getCatalogo();
    if (!mounted) return;
    if (equipos.isEmpty) {
      _snack('No hay equipos en el catálogo', error: true);
      return;
    }
    EquipoCatalogo sel = equipos.first;
    final prox = TextEditingController();
    final resp = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nueva calibración'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<EquipoCatalogo>(
              initialValue: sel,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Equipo'),
              items: equipos.map((e) => DropdownMenuItem(value: e, child: Text(e.nombre, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setLocal(() => sel = v ?? sel),
            ),
            TextField(controller: prox, decoration: const InputDecoration(labelText: 'Próxima calibración (yyyy-mm-dd)')),
            TextField(controller: resp, decoration: const InputDecoration(labelText: 'Empresa responsable')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final res = await _svc!.crear(
      equipoId: sel.id,
      fechaProxima: prox.text.trim().isEmpty ? null : prox.text.trim(),
      empresaResponsable: resp.text.trim().isEmpty ? null : resp.text.trim(),
    );
    if (!mounted) return;
    res.ok ? _cargar() : _snack(res.errorMessage, error: true);
  }

  Future<void> _subirCert(Calibracion c) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Elegir de galería'), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await _picker.pickImage(source: src, imageQuality: 80, maxWidth: 1920);
    if (x == null) return;
    final b64 = base64Encode(await x.readAsBytes());
    final res = await _svc!.subirCertificado(c.id, b64);
    if (!mounted) return;
    if (res.ok) {
      _snack('Certificado subido');
      _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.certificadoUrl != null) const Icon(Icons.verified_outlined, color: Colors.green, size: 18),
                if (AppSession.i.canEditarCalibracion)
                  IconButton(
                    icon: const Icon(Icons.upload_file_outlined, size: 20),
                    tooltip: 'Subir certificado',
                    onPressed: () => _subirCert(c),
                  ),
              ],
            ),
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
