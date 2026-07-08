import 'package:flutter/material.dart';
import '../models/intervencion_models.dart';
import '../models/proyecto_models.dart';
import '../services/intervencion_service.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFE53935);
const _amber = Color(0xFFF59E0B);

/// Procedimientos estándar de mantenimiento: checklist por **tipo de equipo
/// intervenido** (tab principal). El tab "Tipos de servicio" es solo el
/// catálogo de tipos de servicio (sin plantillas de procedimientos: los
/// procedimientos pertenecen a los equipos, no a los servicios).
class PantallaPlantillasProcedimiento extends StatefulWidget {
  const PantallaPlantillasProcedimiento({super.key});

  @override
  State<PantallaPlantillasProcedimiento> createState() =>
      _PantallaPlantillasProcedimientoState();
}

class _PantallaPlantillasProcedimientoState
    extends State<PantallaPlantillasProcedimiento>
    with SingleTickerProviderStateMixin {
  ProyectoService? _service;
  IntervencionService? _intSvc;
  bool _cargando = true;
  List<CatalogoServicio> _catalogos = [];
  // Tipos de equipo intervenido: id, nombre + conteo de pasos de su plantilla
  List<CatalogoItemSimple> _tiposEquipo = [];
  final Map<String, List<Map<String, dynamic>>> _pasosPorTipo = {};
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getProyectoService();
    _intSvc = await getIntervencionService();
    await _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final s = _service!;
    final results = await Future.wait([
      s.getCatalogoServicios(incluirInactivos: true),
      _intSvc!.getTiposEquipo(),
    ]);
    if (!mounted) return;
    _catalogos = results[0] as List<CatalogoServicio>;
    _tiposEquipo = results[1] as List<CatalogoItemSimple>;
    // Cargar las plantillas de cada tipo (pocas: una llamada por tipo).
    _pasosPorTipo.clear();
    await Future.wait([
      for (final t in _tiposEquipo)
        _intSvc!.getProcedimientosTipoEquipo(t.id).then((r) {
          _pasosPorTipo[t.id] = r.data ?? [];
        }),
    ]);
    if (!mounted) return;
    setState(() => _cargando = false);
  }

  /// Placeholder = plantilla vacía o pasos genéricos "Procedimiento N".
  bool _esPlaceholder(String tipoId) {
    final pasos = _pasosPorTipo[tipoId] ?? [];
    if (pasos.isEmpty) return true;
    return pasos.every((p) => RegExp(r'^Procedimiento \d+$')
        .hasMatch((p['nombre'] as String? ?? '').trim()));
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
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _green,
          indicatorColor: _green,
          tabs: const [
            Tab(text: 'Equipos intervenidos'),
            Tab(text: 'Tipos de servicio'),
          ],
        ),
      ),
      floatingActionButton: _cargando
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              onPressed:
                  _tabCtrl.index == 0 ? _nuevoTipoEquipo : _nuevoTipoServicio,
              icon: const Icon(Icons.add),
              label: Text(
                  _tabCtrl.index == 0 ? 'Tipo de equipo' : 'Tipo de servicio'),
            ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _tabEquipos(),
                _tabServicios(),
              ],
            ),
    );
  }

  // ── Tab: plantillas por tipo de EQUIPO intervenido (mantenimiento) ─────────

  Widget _tabEquipos() {
    if (_tiposEquipo.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Sin tipos de equipo. Crea uno con el botón + y define los '
            'procedimientos de su mantenimiento.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: bottomSafePadding(context, extra: 90),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Checklist de mantenimiento por tipo de equipo. Estos pasos se '
              'cargan al inspeccionar un equipo de ese tipo.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 6),
          for (final t in _tiposEquipo) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _tipoEquipoCard(t),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _tipoEquipoCard(CatalogoItemSimple t) {
    final surface = Theme.of(context).colorScheme.surface;
    final pasos = _pasosPorTipo[t.id] ?? [];
    final placeholder = _esPlaceholder(t.id);
    final color = placeholder ? _amber : _green;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _editarPasosEquipo(t),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                placeholder
                    ? Icons.warning_amber_rounded
                    : Icons.assignment_turned_in_outlined,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.nombre,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    placeholder
                        ? (pasos.isEmpty
                            ? 'Sin procedimientos: defínelos'
                            : '${pasos.length} pasos genéricos: redactar contenido real')
                        : '${pasos.length} paso${pasos.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: placeholder ? _amber : Colors.grey),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _editarPasosEquipo(CatalogoItemSimple t) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorPasosEquipo(
          service: _intSvc!,
          tipo: t,
          pasos: _pasosPorTipo[t.id] ?? [],
        ),
      ),
    );
    if (ok == true) await _cargar();
  }

  Future<void> _nuevoTipoEquipo() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo tipo de equipo'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              hintText: 'p. ej. GRUPOS ELECTRÓGENOS'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child:
                  const Text('Crear', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty || !mounted) return;
    final res = await _intSvc!.crearTipoEquipo(nombre);
    if (!mounted) return;
    if (res.ok) {
      await _cargar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.errorMessage.isEmpty
              ? 'No se pudo crear el tipo.'
              : res.errorMessage),
          backgroundColor: _danger));
    }
  }

  // ── Tab: catálogo de tipos de SERVICIO (solo alta/edición del catálogo) ────

  Widget _tabServicios() {
    if (_catalogos.isEmpty) return _vacio();
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: bottomSafePadding(context, extra: 90),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Catálogo de tipos de servicio. Añade nuevos con el botón + '
              'o toca uno para editarlo.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 6),
          for (final c in _catalogos) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _catalogoCard(c),
            ),
            const SizedBox(height: 10),
          ],
        ],
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
              'Crea un tipo de servicio (mantenimiento, instalación, ITSE…) '
              'con el botón +. Quedará disponible al registrar servicios.',
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
    return Opacity(
      opacity: c.activo ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editarTipoServicio(c),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _green.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.category_outlined,
                    color: _green, size: 20),
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
                        if (!c.activo) _chip('Inactivo', Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tipo de trabajo: ${c.tipoTrabajo}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
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

// ─── Editor de pasos por TIPO DE EQUIPO intervenido ───────────────────────────
// Edita tipo_equipo.procedimientos_template: el checklist que se instancia al
// inspeccionar un equipo de este tipo en un servicio de mantenimiento.

class _EditorPasosEquipo extends StatefulWidget {
  final IntervencionService service;
  final CatalogoItemSimple tipo;
  final List<Map<String, dynamic>> pasos;

  const _EditorPasosEquipo({
    required this.service,
    required this.tipo,
    required this.pasos,
  });

  @override
  State<_EditorPasosEquipo> createState() => _EditorPasosEquipoState();
}

class _EditorPasosEquipoState extends State<_EditorPasosEquipo> {
  late List<TextEditingController> _ctrls;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    final ordenados = [...widget.pasos]
      ..sort((a, b) =>
          (a['orden'] as int? ?? 0).compareTo(b['orden'] as int? ?? 0));
    _ctrls = [
      for (final p in ordenados)
        TextEditingController(text: p['nombre'] as String? ?? ''),
    ];
    if (_ctrls.isEmpty) _ctrls.add(TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _mover(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _ctrls.length) return;
    setState(() {
      final tmp = _ctrls[i];
      _ctrls[i] = _ctrls[j];
      _ctrls[j] = tmp;
    });
  }

  Future<void> _guardar() async {
    final pasos = <Map<String, dynamic>>[];
    var orden = 0;
    for (final c in _ctrls) {
      final txt = c.text.trim();
      if (txt.isEmpty) continue;
      orden++;
      pasos.add({'orden': orden, 'nombre': txt, 'descripcion': ''});
    }
    if (pasos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escribe al menos un procedimiento'),
          backgroundColor: _danger));
      return;
    }
    setState(() => _guardando = true);
    final res = await widget.service
        .guardarProcedimientosTipoEquipo(widget.tipo.id, pasos);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.errorMessage.isEmpty
              ? 'No se pudo guardar.'
              : res.errorMessage),
          backgroundColor: _danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.tipo.nombre,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: ListView(
        padding: bottomSafePadding(context, extra: 90),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Un paso por tarjeta, en el orden en que se ejecutan. '
              'Incluye la norma de referencia si aplica (CNE/RNE/NTP).',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
          ),
          for (var i = 0; i < _ctrls.length; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _green.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('PASO ${i + 1}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _green)),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: i == 0 ? null : () => _mover(i, -1),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.arrow_downward, size: 16),
                          onPressed: i == _ctrls.length - 1
                              ? null
                              : () => _mover(i, 1),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: _danger),
                          onPressed: () => setState(() {
                            _ctrls.removeAt(i).dispose();
                            if (_ctrls.isEmpty) {
                              _ctrls.add(TextEditingController());
                            }
                          }),
                        ),
                      ],
                    ),
                    TextField(
                      controller: _ctrls[i],
                      maxLines: null,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Describe el procedimiento…',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _ctrls.add(TextEditingController())),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _green),
                foregroundColor: _green,
              ),
              icon: const Icon(Icons.add),
              label: const Text('Añadir paso'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                : const Text('Guardar checklist',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}
