import 'package:flutter/material.dart';

import '../core/api_result.dart';
import '../models/catalogo_models.dart';
import '../services/catalogo_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';

class PantallaCatalogos extends StatefulWidget {
  const PantallaCatalogos({super.key});

  @override
  State<PantallaCatalogos> createState() => _PantallaCatalogosState();
}

class _PantallaCatalogosState extends State<PantallaCatalogos>
    with SingleTickerProviderStateMixin {
  CatalogoService? _svc;
  late final TabController _tab;

  List<UbicacionArbol> _arbol = [];
  List<Ubicacion> _ubic = [];
  List<Zona> _zonas = [];
  bool _cargando = true;

  static const _kVerde = Color(0xFF8FD11B);

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
    final results = await Future.wait([
      _svc!.arbol(),
      _svc!.ubicaciones(),
      _svc!.zonas(),
    ]);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      final arbol = results[0] as ApiResult<List<UbicacionArbol>>;
      final u = results[1] as ApiResult<List<Ubicacion>>;
      final z = results[2] as ApiResult<List<Zona>>;
      if (arbol.ok) _arbol = arbol.data ?? [];
      if (u.ok) _ubic = u.data ?? [];
      if (z.ok) _zonas = z.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _afterMutation(ApiResult<void> res) async {
    if (!mounted) return;
    if (res.ok) {
      await _cargar();
    } else {
      _snack(res.errorMessage, error: true);
    }
  }

  // ── FAB: agrega según la pestaña activa ─────────────────────────────────────
  Future<void> _add() async {
    switch (_tab.index) {
      case 0:
      case 1:
        await _dlgAddUbicacion();
      default:
        await _dlgAddZona();
    }
  }

  // ── Diálogos: crear ─────────────────────────────────────────────────────────

  Future<void> _dlgAddUbicacion() async {
    final n = TextEditingController();
    final r = TextEditingController();
    final ok = await _dlg('Nueva ubicación', [
      _field(n, 'Nombre'),
      _field(r, 'Región (opcional)'),
    ]);
    if (ok != true || n.text.trim().isEmpty) return;
    await _afterMutation(await _svc!.crearUbicacion(
      n.text.trim(),
      r.text.trim().isEmpty ? null : r.text.trim(),
    ));
  }

  Future<void> _dlgAddZona({String? ubicacionIdFijo}) async {
    final n = TextEditingController();
    final t = TextEditingController();
    String? ubicId = ubicacionIdFijo ?? (_ubic.isNotEmpty ? _ubic.first.id : null);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setL) => AlertDialog(
          title: const Text('Nueva zona'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(n, 'Nombre'),
            _field(t, 'Tipo (opcional)'),
            if (ubicacionIdFijo == null && _ubic.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: ubicId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Ubicación'),
                items: _ubic
                    .map((u) => DropdownMenuItem(
                          value: u.id,
                          child: Text(u.nombre, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setL(() => ubicId = v),
              ),
          ]),
          actions: _acciones(ctx),
        ),
      ),
    );
    if (ok != true || n.text.trim().isEmpty) return;
    await _afterMutation(await _svc!.crearZona(
      n.text.trim(),
      t.text.trim().isEmpty ? null : t.text.trim(),
      ubicId,
    ));
  }

  // ── Diálogos: editar ────────────────────────────────────────────────────────

  Future<void> _dlgEditUbicacion(String id, String nombre, String? region) async {
    final n = TextEditingController(text: nombre);
    final r = TextEditingController(text: region ?? '');
    final ok = await _dlg('Editar ubicación', [
      _field(n, 'Nombre'),
      _field(r, 'Región (opcional)'),
    ]);
    if (ok != true || n.text.trim().isEmpty) return;
    await _afterMutation(await _svc!.actualizarUbicacion(
      id,
      n.text.trim(),
      r.text.trim().isEmpty ? null : r.text.trim(),
    ));
  }

  Future<void> _dlgEditZona(String id, String nombre, String? tipo) async {
    final n = TextEditingController(text: nombre);
    final t = TextEditingController(text: tipo ?? '');
    final ok = await _dlg('Editar zona', [
      _field(n, 'Nombre'),
      _field(t, 'Tipo (opcional)'),
    ]);
    if (ok != true || n.text.trim().isEmpty) return;
    await _afterMutation(await _svc!.actualizarZona(
      id,
      n.text.trim(),
      t.text.trim().isEmpty ? null : t.text.trim(),
      null,
    ));
  }

  // ── Confirmar eliminación ────────────────────────────────────────────────────
  Future<void> _confirmDel(String tipo, String id, String nombre) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Eliminar "$nombre"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _afterMutation(await _svc!.eliminar(tipo, id));
  }

  // ── Helpers de diálogo ───────────────────────────────────────────────────────
  Future<bool?> _dlg(String titulo, List<Widget> campos) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Column(mainAxisSize: MainAxisSize.min, children: campos),
          actions: _acciones(ctx),
        ),
      );

  List<Widget> _acciones(BuildContext ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Guardar'),
        ),
      ];

  Widget _field(TextEditingController ctrl, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
          textCapitalization: TextCapitalization.characters,
        ),
      );

  // ── BUILD ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogos',
            style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Jerarquía'),
            Tab(text: 'Ubicaciones'),
            Tab(text: 'Zonas'),
          ],
        ),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        backgroundColor: _kVerde,
        child: const Icon(Icons.add),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _arbolTab(),
                _ubicTab(),
                _zonasTab(),
              ],
            ),
    );
  }

  // ── TAB: Jerarquía ──────────────────────────────────────────────────────────

  Widget _arbolTab() {
    if (_arbol.isEmpty) {
      return RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(children: const [
          SizedBox(height: 120),
          Center(
            child: Text(
              'Sin ubicaciones registradas.\nUsa el botón + para comenzar.',
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: bottomSafePadding(context, left: 0, top: 4, right: 0, extra: 90),
        children: [
          for (final u in _arbol) _ubicacionCard(u),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _ubicacionCard(UbicacionArbol u) {
    return Card(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _arbol.length <= 5,
        leading: const Icon(Icons.location_on_outlined, color: _kVerde),
        title: Text(u.nombre,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [u.region, '${u.zonas.length} zona(s)']
              .where((x) => (x ?? '').isNotEmpty)
              .join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuNodo(items: [
              _MenuOpt(Icons.add_circle_outline, 'Agregar zona', () {
                _dlgAddZona(ubicacionIdFijo: u.id);
              }),
              _MenuOpt(Icons.edit_outlined, 'Editar', () {
                _dlgEditUbicacion(u.id, u.nombre, u.region);
              }),
              _MenuOpt(Icons.delete_outline, 'Eliminar', () {
                _confirmDel('ubicaciones', u.id, u.nombre);
              }, danger: true),
            ]),
            const Icon(Icons.expand_more),
          ],
        ),
        childrenPadding: const EdgeInsets.only(left: 8, bottom: 8),
        children: [
          if (u.zonas.isEmpty)
            ListTile(
              dense: true,
              title: const Text('— sin zonas —',
                  style: TextStyle(color: Colors.grey)),
              trailing: TextButton.icon(
                onPressed: () => _dlgAddZona(ubicacionIdFijo: u.id),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Zona'),
              ),
            ),
          for (final z in u.zonas) _zonaExpansion(z),
        ],
      ),
    );
  }

  Widget _zonaExpansion(ZonaArbol z) {
    return ListTile(
      leading: const Icon(Icons.crop_free, size: 20),
      title: Text(z.nombre),
      subtitle: z.tipo != null ? Text(z.tipo!) : null,
      trailing: _menuNodo(items: [
        _MenuOpt(Icons.edit_outlined, 'Editar', () {
          _dlgEditZona(z.id, z.nombre, z.tipo);
        }),
        _MenuOpt(Icons.delete_outline, 'Eliminar', () {
          _confirmDel('zonas', z.id, z.nombre);
        }, danger: true),
      ]),
    );
  }

  Widget _menuNodo({required List<_MenuOpt> items}) {
    return PopupMenuButton<_MenuOpt>(
      icon: const Icon(Icons.more_vert, size: 20),
      padding: EdgeInsets.zero,
      onSelected: (opt) => opt.accion(),
      itemBuilder: (_) => items
          .map((o) => PopupMenuItem(
                value: o,
                child: Row(children: [
                  Icon(o.icon,
                      size: 18,
                      color: o.danger ? Colors.red : null),
                  const SizedBox(width: 10),
                  Text(o.label,
                      style: TextStyle(
                          color: o.danger ? Colors.red : null)),
                ]),
              ))
          .toList(),
    );
  }

  // ── TAB: Ubicaciones (lista plana) ───────────────────────────────────────────

  Widget _ubicTab() {
    if (_ubic.isEmpty) {
      return const Center(child: Text('Sin ubicaciones.'));
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: bottomSafePadding(context, left: 0, top: 0, right: 0, extra: 90),
        children: _ubic
            .map((u) => ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(u.nombre),
                  subtitle: Text(u.region ?? '-'),
                  trailing: _rowAcciones(
                    onEdit: () => _dlgEditUbicacion(u.id, u.nombre, u.region),
                    onDel: () => _confirmDel('ubicaciones', u.id, u.nombre),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ── TAB: Zonas (lista plana) ─────────────────────────────────────────────────

  Widget _zonasTab() {
    if (_zonas.isEmpty) return const Center(child: Text('Sin zonas.'));
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: bottomSafePadding(context, left: 0, top: 0, right: 0, extra: 90),
        children: _zonas
            .map((z) => ListTile(
                  leading: const Icon(Icons.crop_free),
                  title: Text(z.nombre),
                  subtitle: Text(
                    [z.tipo, z.ubicacionNombre]
                        .where((x) => (x ?? '').isNotEmpty)
                        .join(' · '),
                  ),
                  trailing: _rowAcciones(
                    onEdit: () => _dlgEditZona(z.id, z.nombre, z.tipo),
                    onDel: () => _confirmDel('zonas', z.id, z.nombre),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _rowAcciones({required VoidCallback onEdit, required VoidCallback onDel}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          onPressed: onEdit,
          tooltip: 'Editar',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
          onPressed: onDel,
          tooltip: 'Eliminar',
        ),
      ],
    );
  }
}

// ── Modelos internos ─────────────────────────────────────────────────────────
class _MenuOpt {
  final IconData icon;
  final String label;
  final VoidCallback accion;
  final bool danger;
  const _MenuOpt(this.icon, this.label, this.accion, {this.danger = false});
}
