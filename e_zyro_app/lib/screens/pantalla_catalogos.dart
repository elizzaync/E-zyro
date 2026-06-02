import 'package:flutter/material.dart';

import '../core/api_result.dart';
import '../models/catalogo_models.dart';
import '../services/catalogo_service.dart';
import '../utils/api_provider.dart';

/// Gestión de catálogos base (Fase 0): Ubicaciones, Zonas, Áreas.
class PantallaCatalogos extends StatefulWidget {
  const PantallaCatalogos({super.key});

  @override
  State<PantallaCatalogos> createState() => _PantallaCatalogosState();
}

class _PantallaCatalogosState extends State<PantallaCatalogos> with SingleTickerProviderStateMixin {
  CatalogoService? _svc;
  late final TabController _tab;
  List<Ubicacion> _ubic = [];
  List<Zona> _zonas = [];
  List<Area> _areas = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _svc = await getCatalogoService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() => _cargando = true);
    final u = await _svc!.ubicaciones();
    final z = await _svc!.zonas();
    final a = await _svc!.areas();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (u.ok) _ubic = u.data ?? [];
      if (z.ok) _zonas = z.data ?? [];
      if (a.ok) _areas = a.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _afterMutation(ApiResult<void> res) async {
    if (!mounted) return;
    res.ok ? await _cargar() : _snack(res.errorMessage, error: true);
  }

  Future<void> _add() async {
    switch (_tab.index) {
      case 0:
        await _addUbicacion();
      case 1:
        await _addZona();
      default:
        await _addArea();
    }
  }

  Future<void> _addUbicacion() async {
    final n = TextEditingController();
    final r = TextEditingController();
    final ok = await _dialogo('Nueva ubicación', [
      TextField(controller: n, decoration: const InputDecoration(labelText: 'Nombre')),
      TextField(controller: r, decoration: const InputDecoration(labelText: 'Región')),
    ]);
    if (ok != true || n.text.trim().isEmpty) return;
    await _afterMutation(await _svc!.crearUbicacion(n.text.trim(), r.text.trim().isEmpty ? null : r.text.trim()));
  }

  Future<void> _addZona() async {
    final n = TextEditingController();
    final t = TextEditingController();
    String? ubicId = _ubic.isNotEmpty ? _ubic.first.id : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nueva zona'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: t, decoration: const InputDecoration(labelText: 'Tipo')),
            if (_ubic.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: ubicId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ubicación'),
                items: _ubic.map((u) => DropdownMenuItem(value: u.id, child: Text(u.nombre, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setLocal(() => ubicId = v),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true || n.text.trim().isEmpty) return;
    await _afterMutation(await _svc!.crearZona(n.text.trim(), t.text.trim().isEmpty ? null : t.text.trim(), ubicId));
  }

  Future<void> _addArea() async {
    final n = TextEditingController();
    // Cascada Ubicación → Zona: el área cuelga de una zona (mantiene el orden).
    String? ubicId = _ubic.isNotEmpty ? _ubic.first.id : null;
    List<Zona> zonasUbic = _zonas.where((z) => z.ubicacionId == ubicId).toList();
    String? zonaId = zonasUbic.isNotEmpty ? zonasUbic.first.id : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          zonasUbic = _zonas.where((z) => z.ubicacionId == ubicId).toList();
          return AlertDialog(
            title: const Text('Nueva área'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: n, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 8),
              if (_ubic.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: ubicId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Ubicación'),
                  items: _ubic.map((u) => DropdownMenuItem(value: u.id, child: Text(u.nombre, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setLocal(() {
                    ubicId = v;
                    final zs = _zonas.where((z) => z.ubicacionId == v).toList();
                    zonaId = zs.isNotEmpty ? zs.first.id : null;
                  }),
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: zonaId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Zona'),
                hint: const Text('Selecciona una zona'),
                items: zonasUbic.map((z) => DropdownMenuItem(value: z.id, child: Text(z.nombre, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setLocal(() => zonaId = v),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
            ],
          );
        },
      ),
    );
    if (ok != true || n.text.trim().isEmpty) return;
    if (zonaId == null) {
      _snack('Selecciona una zona para el área', error: true);
      return;
    }
    await _afterMutation(await _svc!.crearArea(n.text.trim(), zonaId: zonaId));
  }

  Future<bool?> _dialogo(String titulo, List<Widget> campos) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Column(mainAxisSize: MainAxisSize.min, children: campos),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      );

  Future<void> _del(String tipo, String id) async {
    await _afterMutation(await _svc!.eliminar(tipo, id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogos', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Ubicaciones'), Tab(text: 'Zonas'), Tab(text: 'Áreas')]),
        actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tab, children: [_ubicTab(), _zonasTab(), _areasTab()]),
    );
  }

  Widget _lista(List<Widget> tiles, String vacio) =>
      tiles.isEmpty ? Center(child: Text(vacio)) : RefreshIndicator(onRefresh: _cargar, child: ListView(children: tiles));

  Widget _ubicTab() => _lista([
        for (final u in _ubic)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(u.nombre),
            subtitle: Text(u.region ?? '-'),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _del('ubicaciones', u.id)),
          ),
      ], 'Sin ubicaciones.');

  Widget _zonasTab() => _lista([
        for (final z in _zonas)
          ListTile(
            leading: const Icon(Icons.crop_free),
            title: Text(z.nombre),
            subtitle: Text([z.tipo, z.ubicacionNombre].where((x) => (x ?? '').isNotEmpty).join(' · ')),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _del('zonas', z.id)),
          ),
      ], 'Sin zonas.');

  Widget _areasTab() => _lista([
        for (final a in _areas)
          ListTile(
            leading: const Icon(Icons.workspaces_outline),
            title: Text(a.nombre),
            subtitle: Text(
              [a.ubicacionNombre, a.zonaNombre].where((x) => (x ?? '').isNotEmpty).join(' › '),
            ),
            trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _del('areas', a.id)),
          ),
      ], 'Sin áreas.');
}
