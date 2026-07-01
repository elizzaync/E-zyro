import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFE53935);
const _amber = Color(0xFFF59E0B);

/// Gestión del estándar (tipo manual) de **Procedimientos** fijos por **tipo
/// de servicio**: cada tipo del catálogo tiene su propia plantilla de pasos.
/// Al crear un servicio de ese tipo se instancian esos pasos (llevan
/// evidencias y alimentan el avance/informe/certificado).
class PantallaPlantillasProcedimiento extends StatefulWidget {
  const PantallaPlantillasProcedimiento({super.key});

  @override
  State<PantallaPlantillasProcedimiento> createState() =>
      _PantallaPlantillasProcedimientoState();
}

class _PantallaPlantillasProcedimientoState
    extends State<PantallaPlantillasProcedimiento> {
  ProyectoService? _service;
  bool _cargando = true;
  List<CatalogoServicio> _catalogos = [];
  List<Map<String, dynamic>> _plantillas = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _service = await getProyectoService();
    await _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final s = _service!;
    final results = await Future.wait([
      s.getCatalogoServicios(incluirInactivos: true),
      s.getPlantillas(),
    ]);
    if (!mounted) return;
    setState(() {
      _catalogos = results[0] as List<CatalogoServicio>;
      _plantillas = results[1] as List<Map<String, dynamic>>;
      _cargando = false;
    });
  }

  Map<String, dynamic>? _plantillaDe(String catalogoId) {
    for (final p in _plantillas) {
      if (p['catalogo_servicio_id'] == catalogoId) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> get _plantillasHuerfanas => _plantillas
      .where((p) => (p['catalogo_servicio_id'] as String?) == null)
      .toList();

  Future<void> _editarPlantilla(CatalogoServicio catalogo) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorPlantilla(
          service: _service!,
          catalogo: catalogo,
          plantilla: _plantillaDe(catalogo.id),
        ),
      ),
    );
    if (ok == true) await _cargar();
  }

  Future<void> _editarPlantillaLegacy(Map<String, dynamic> plantilla) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorPlantilla(
          service: _service!,
          catalogo: null,
          plantilla: plantilla,
        ),
      ),
    );
    if (ok == true) await _cargar();
  }

  Future<void> _nuevoTipoServicio() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorCatalogo(service: _service!),
      ),
    );
    if (ok == true) await _cargar();
  }

  Future<void> _editarTipoServicio(CatalogoServicio catalogo) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorCatalogo(service: _service!, catalogo: catalogo),
      ),
    );
    if (ok == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Procedimientos estándar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      floatingActionButton: _cargando
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              onPressed: _nuevoTipoServicio,
              icon: const Icon(Icons.add),
              label: const Text('Tipo de servicio'),
            ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : _catalogos.isEmpty
              ? _vacio()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: bottomSafePadding(context, extra: 90),
                    children: [
                      const Padding(
                        padding:
                            EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Cada tipo de servicio tiene un único estándar de '
                          'procedimientos. Tócalo para verlo o editarlo.',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final c in _catalogos) ...[
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: _catalogoCard(c),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_plantillasHuerfanas.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            'Sin tipo de servicio vinculado (revisar)',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: _amber,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        for (final p in _plantillasHuerfanas) ...[
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: _legacyCard(p),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _vacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Sin tipos de servicio',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Crea un tipo de servicio (pozo a tierra, UPS, tablero…) y luego '
              'su estándar de procedimientos. Se aplicará a los nuevos '
              'servicios de ese tipo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogoCard(CatalogoServicio c) {
    final surface = Theme.of(context).colorScheme.surface;
    final plantilla = _plantillaDe(c.id);
    final tienePlantilla = plantilla != null;
    final procesos = (plantilla?['procesos'] as List? ?? []);
    final plantillaActiva = plantilla?['activo'] as bool? ?? true;

    return Opacity(
      opacity: c.activo ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editarPlantilla(c),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: (tienePlantilla ? _green : _amber)
                    .withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (tienePlantilla ? _green : _amber)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  tienePlantilla
                      ? Icons.assignment_turned_in_outlined
                      : Icons.warning_amber_rounded,
                  color: tienePlantilla ? _green : _amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(c.nombre,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                        ),
                        if (!c.activo)
                          _chip('Tipo inactivo', Colors.grey)
                        else if (tienePlantilla && !plantillaActiva)
                          _chip('Plantilla inactiva', Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tienePlantilla
                          ? '${procesos.length} pasos · v${plantilla['version'] ?? 1}'
                          : 'Sin procedimientos estándar definidos',
                      style: TextStyle(
                          fontSize: 12,
                          color: tienePlantilla ? Colors.grey : _amber,
                          fontWeight:
                              tienePlantilla ? FontWeight.w400 : FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
                tooltip: 'Editar tipo de servicio',
                onPressed: () => _editarTipoServicio(c),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legacyCard(Map<String, dynamic> p) {
    final surface = Theme.of(context).colorScheme.surface;
    final procesos = (p['procesos'] as List? ?? []);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _editarPlantillaLegacy(p),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _amber.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_off, color: _amber, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['nombre'] as String? ?? '',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    'Tipo (texto libre): ${p['tipo_trabajo'] ?? '—'} · ${procesos.length} pasos',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.9))),
      );
}

// ── Editor de tipo de servicio (catalogo_servicio) ────────────────────────────

class _EditorCatalogo extends StatefulWidget {
  final ProyectoService service;
  final CatalogoServicio? catalogo;

  const _EditorCatalogo({required this.service, this.catalogo});

  @override
  State<_EditorCatalogo> createState() => _EditorCatalogoState();
}

class _EditorCatalogoState extends State<_EditorCatalogo> {
  late final TextEditingController _nombre;
  late final TextEditingController _tipoTrabajo;
  late final TextEditingController _descripcion;
  bool _guardando = false;
  String? _error;

  bool get _esNuevo => widget.catalogo == null;

  @override
  void initState() {
    super.initState();
    final c = widget.catalogo;
    _nombre = TextEditingController(text: c?.nombre ?? '');
    _tipoTrabajo = TextEditingController(text: c?.tipoTrabajo ?? '');
    _descripcion = TextEditingController(text: c?.descripcion ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _tipoTrabajo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _error = null);
    final nombre = _nombre.text.trim();
    final tipo = _tipoTrabajo.text.trim();
    if (nombre.isEmpty || tipo.isEmpty) {
      setState(() => _error = 'Indica el nombre y el tipo de trabajo.');
      return;
    }
    setState(() => _guardando = true);
    final body = {
      'nombre': nombre,
      'tipo_trabajo': tipo,
      'descripcion':
          _descripcion.text.trim().isEmpty ? null : _descripcion.text.trim(),
    };
    final ok = _esNuevo
        ? await widget.service.crearCatalogoServicio(body)
        : await widget.service
            .editarCatalogoServicio(widget.catalogo!.id, body);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'No se pudo guardar. Intenta nuevamente.');
    }
  }

  Future<void> _cambiarEstado(bool activo) async {
    final c = widget.catalogo;
    if (c == null) return;
    setState(() => _guardando = true);
    final ok = await widget.service.cambiarEstadoCatalogoServicio(c.id, activo);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'No se pudo cambiar el estado.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.catalogo;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_esNuevo ? 'Nuevo tipo de servicio' : 'Editar tipo de servicio',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          if (c != null)
            IconButton(
              icon: Icon(c.activo ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              tooltip: c.activo ? 'Desactivar' : 'Activar',
              onPressed: _guardando ? null : () => _cambiarEstado(!c.activo),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nombre,
              decoration: InputDecoration(
                labelText: 'Nombre (p. ej. Mantenimiento de pozo a tierra)',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tipoTrabajo,
              decoration: InputDecoration(
                labelText: 'Tipo de trabajo (clave corta, p. ej. pozo, ups)',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descripcion,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Descripción (opcional)',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBox(_error!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _errorBox(String error) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(error,
                  style: const TextStyle(color: _danger, fontSize: 12.5))),
        ],
      ),
    );

// ── Editor de una plantilla (procedimientos estándar de un tipo de servicio) ──

class _EditorPlantilla extends StatefulWidget {
  final ProyectoService service;
  /// Tipo de servicio dueño de la plantilla. Null = edición legacy de una
  /// plantilla aún no vinculada a ningún tipo de servicio (revisar).
  final CatalogoServicio? catalogo;
  final Map<String, dynamic>? plantilla;

  const _EditorPlantilla({
    required this.service,
    required this.catalogo,
    required this.plantilla,
  });

  @override
  State<_EditorPlantilla> createState() => _EditorPlantillaState();
}

class _EditorPlantillaState extends State<_EditorPlantilla> {
  late final TextEditingController _tipoTrabajoLegacy;
  late final TextEditingController _nombre;
  late final TextEditingController _json;
  bool _activo = true;
  bool _guardando = false;
  String? _error;

  bool get _esLegacy => widget.catalogo == null;
  bool get _esNuevo => widget.plantilla == null;

  @override
  void initState() {
    super.initState();
    final p = widget.plantilla;
    _tipoTrabajoLegacy =
        TextEditingController(text: p?['tipo_trabajo'] as String? ?? '');
    _nombre = TextEditingController(
        text: p?['nombre'] as String? ?? widget.catalogo?.nombre ?? '');
    _activo = p?['activo'] as bool? ?? true;
    final procesos = (p?['procesos'] as List? ?? []);
    _json = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(
        procesos.isEmpty
            ? [
                {'orden': 1, 'nombre': '', 'descripcion': ''}
              ]
            : procesos,
      ),
    );
  }

  @override
  void dispose() {
    _tipoTrabajoLegacy.dispose();
    _nombre.dispose();
    _json.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _error = null);
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Indica un nombre para la plantilla.');
      return;
    }
    if (_esLegacy && _tipoTrabajoLegacy.text.trim().isEmpty) {
      setState(() => _error = 'Indica el tipo de trabajo.');
      return;
    }

    // Validar y normalizar el JSON de procesos.
    List<Map<String, dynamic>> procesos;
    try {
      final parsed = jsonDecode(_json.text);
      if (parsed is! List) {
        setState(() => _error = 'El JSON debe ser una lista de procesos.');
        return;
      }
      procesos = [];
      var i = 1;
      for (final e in parsed) {
        if (e is! Map) continue;
        final nom = (e['nombre'] as String? ?? '').trim();
        if (nom.isEmpty) continue;
        procesos.add({
          'orden': (e['orden'] as num?)?.toInt() ?? i,
          'nombre': nom,
          'descripcion': (e['descripcion'] as String? ?? '').trim(),
        });
        i++;
      }
    } catch (_) {
      setState(() => _error = 'JSON inválido. Revisa el formato.');
      return;
    }
    if (procesos.isEmpty) {
      setState(() => _error = 'Añade al menos un proceso con nombre.');
      return;
    }

    setState(() => _guardando = true);
    final ok = await widget.service.guardarPlantilla({
      if (widget.catalogo != null) 'catalogo_servicio_id': widget.catalogo!.id,
      if (_esLegacy) 'tipo_trabajo': _tipoTrabajoLegacy.text.trim(),
      'nombre': nombre,
      'procesos': procesos,
      'activo': _activo,
    });
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'No se pudo guardar. Intenta nuevamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
            widget.catalogo?.nombre ??
                (_esNuevo ? 'Nueva plantilla' : 'Editar plantilla'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_esLegacy)
              TextField(
                controller: _tipoTrabajoLegacy,
                decoration: InputDecoration(
                  labelText: 'Tipo de trabajo (legado, texto libre)',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              )
            else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _green.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.category_outlined, size: 16, color: _green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Tipo de servicio: ${widget.catalogo!.nombre} (${widget.catalogo!.tipoTrabajo})',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _nombre,
              decoration: InputDecoration(
                labelText: 'Nombre de la plantilla',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activa',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: const Text(
                  'Solo las plantillas activas se aplican a nuevos servicios.',
                  style: TextStyle(fontSize: 12)),
              value: _activo,
              activeThumbColor: _green,
              onChanged: (v) => setState(() => _activo = v),
            ),
            const SizedBox(height: 8),
            const Text('Procesos (JSON)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Lista de objetos: {"orden", "nombre", "descripcion"}.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _json,
              maxLines: 14,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                alignLabelWithHint: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBox(_error!),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
