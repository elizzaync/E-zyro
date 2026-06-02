import 'package:flutter/material.dart';

import '../models/catalogo_models.dart';
import '../services/catalogo_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Selección de la geografía actual: ubicación, zona y (opcional) área.
class GeoSeleccion {
  final String? ubicacionId;
  final String? zonaId;
  final String? areaId;
  const GeoSeleccion({this.ubicacionId, this.zonaId, this.areaId});

  GeoSeleccion copyWith({String? ubicacionId, String? zonaId, String? areaId, bool clearZona = false, bool clearArea = false}) =>
      GeoSeleccion(
        ubicacionId: ubicacionId ?? this.ubicacionId,
        zonaId: clearZona ? null : (zonaId ?? this.zonaId),
        areaId: clearArea ? null : (areaId ?? this.areaId),
      );
}

/// Selector en cascada Ubicación → Zona → Área (estricto: solo elige del
/// catálogo). Con permiso `catalogos:crear`, muestra un botón "+ nuevo" en cada
/// nivel que crea la entrada respetando la jerarquía y la deja seleccionada.
///
/// Es la única vía recomendada para capturar geografía en formularios: evita el
/// texto libre y mantiene el orden del catálogo.
class GeoCascadePicker extends StatefulWidget {
  final GeoSeleccion valor;
  final ValueChanged<GeoSeleccion> onChanged;

  /// Si false, oculta el nivel Área (p. ej. al crear un servicio, que solo
  /// necesita ubicación/zona).
  final bool mostrarArea;

  /// Texto de ayuda opcional bajo el título.
  final bool denso;

  const GeoCascadePicker({
    super.key,
    required this.valor,
    required this.onChanged,
    this.mostrarArea = true,
    this.denso = false,
  });

  @override
  State<GeoCascadePicker> createState() => _GeoCascadePickerState();
}

class _GeoCascadePickerState extends State<GeoCascadePicker> {
  CatalogoService? _svc;
  List<Ubicacion> _ubic = [];
  List<Zona> _zonas = [];
  List<Area> _areas = [];
  bool _cargandoUbic = true;
  bool _cargandoZonas = false;
  bool _cargandoAreas = false;

  bool get _puedeCrear => AppSession.i.canCrearCatalogo;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getCatalogoService();
    await _cargarUbic();
    // Si ya venía una selección (modo editar), precargar zonas/áreas.
    if (widget.valor.ubicacionId != null) await _cargarZonas(widget.valor.ubicacionId!);
    if (widget.mostrarArea && widget.valor.zonaId != null) await _cargarAreas(widget.valor.zonaId!);
  }

  Future<void> _cargarUbic() async {
    setState(() => _cargandoUbic = true);
    final r = await _svc!.ubicaciones();
    if (!mounted) return;
    setState(() {
      _cargandoUbic = false;
      if (r.ok) _ubic = r.data ?? [];
    });
  }

  Future<void> _cargarZonas(String ubicacionId) async {
    setState(() => _cargandoZonas = true);
    final r = await _svc!.zonas(ubicacionId: ubicacionId);
    if (!mounted) return;
    setState(() {
      _cargandoZonas = false;
      if (r.ok) _zonas = r.data ?? [];
    });
  }

  Future<void> _cargarAreas(String zonaId) async {
    setState(() => _cargandoAreas = true);
    final r = await _svc!.areas(zonaId: zonaId);
    if (!mounted) return;
    setState(() {
      _cargandoAreas = false;
      if (r.ok) _areas = r.data ?? [];
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  // ── Cambios de selección ──────────────────────────────────────────────────
  Future<void> _onUbicChanged(String? id) async {
    widget.onChanged(GeoSeleccion(ubicacionId: id)); // resetea zona/área
    setState(() {
      _zonas = [];
      _areas = [];
    });
    if (id != null) await _cargarZonas(id);
  }

  Future<void> _onZonaChanged(String? id) async {
    widget.onChanged(widget.valor.copyWith(zonaId: id, clearArea: true));
    setState(() => _areas = []);
    if (widget.mostrarArea && id != null) await _cargarAreas(id);
  }

  void _onAreaChanged(String? id) {
    widget.onChanged(widget.valor.copyWith(areaId: id));
  }

  // ── Crear inline ────────────────────────────────────────────────────────────
  Future<String?> _prompt(String titulo, String label) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    final txt = ctrl.text.trim();
    return (ok == true && txt.isNotEmpty) ? txt : null;
  }

  Future<void> _crearUbic() async {
    final nombre = await _prompt('Nueva ubicación', 'Nombre');
    if (nombre == null) return;
    final r = await _svc!.crearUbicacionRet(nombre, null);
    if (!r.ok) return _snack(r.errorMessage, error: true);
    await _cargarUbic();
    await _onUbicChanged(r.data!.id);
  }

  Future<void> _crearZona() async {
    final ubic = widget.valor.ubicacionId;
    if (ubic == null) return _snack('Elige primero una ubicación', error: true);
    final nombre = await _prompt('Nueva zona', 'Nombre');
    if (nombre == null) return;
    final r = await _svc!.crearZonaRet(nombre, null, ubic);
    if (!r.ok) return _snack(r.errorMessage, error: true);
    await _cargarZonas(ubic);
    await _onZonaChanged(r.data!.id);
  }

  Future<void> _crearArea() async {
    final zona = widget.valor.zonaId;
    if (zona == null) return _snack('Elige primero una zona', error: true);
    final nombre = await _prompt('Nueva área', 'Nombre');
    if (nombre == null) return;
    final r = await _svc!.crearAreaRet(nombre, zonaId: zona);
    if (!r.ok) return _snack(r.errorMessage, error: true);
    await _cargarAreas(zona);
    _onAreaChanged(r.data!.id);
  }

  // ── UI ──────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _nivel<Ubicacion>(
          label: 'Ubicación',
          icon: Icons.location_on_outlined,
          cargando: _cargandoUbic,
          valor: widget.valor.ubicacionId,
          items: _ubic,
          idOf: (u) => u.id,
          nombreOf: (u) => u.nombre,
          onChanged: _onUbicChanged,
          onCrear: _crearUbic,
        ),
        const SizedBox(height: 10),
        _nivel<Zona>(
          label: 'Zona',
          icon: Icons.crop_free,
          cargando: _cargandoZonas,
          habilitado: widget.valor.ubicacionId != null,
          valor: widget.valor.zonaId,
          items: _zonas,
          idOf: (z) => z.id,
          nombreOf: (z) => z.nombre,
          onChanged: _onZonaChanged,
          onCrear: _crearZona,
        ),
        if (widget.mostrarArea) ...[
          const SizedBox(height: 10),
          _nivel<Area>(
            label: 'Área',
            icon: Icons.workspaces_outline,
            cargando: _cargandoAreas,
            habilitado: widget.valor.zonaId != null,
            valor: widget.valor.areaId,
            items: _areas,
            idOf: (a) => a.id,
            nombreOf: (a) => a.nombre,
            onChanged: _onAreaChanged,
            onCrear: _crearArea,
          ),
        ],
      ],
    );
  }

  Widget _nivel<T>({
    required String label,
    required IconData icon,
    required bool cargando,
    required String? valor,
    required List<T> items,
    required String Function(T) idOf,
    required String Function(T) nombreOf,
    required ValueChanged<String?> onChanged,
    required VoidCallback onCrear,
    bool habilitado = true,
  }) {
    // Guarda contra valor seleccionado que no esté en la lista (evita crash de Dropdown).
    final ids = items.map(idOf).toSet();
    final valorSeguro = (valor != null && ids.contains(valor)) ? valor : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: valorSeguro,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon),
              isDense: widget.denso,
              border: const OutlineInputBorder(),
            ),
            hint: cargando
                ? const Text('Cargando…')
                : Text(habilitado ? 'Selecciona…' : 'Elige el nivel anterior'),
            items: items
                .map((e) => DropdownMenuItem(
                      value: idOf(e),
                      child: Text(nombreOf(e), overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (!habilitado || cargando) ? null : onChanged,
          ),
        ),
        if (_puedeCrear) ...[
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Nuevo $label',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: habilitado ? onCrear : null,
          ),
        ],
      ],
    );
  }
}
