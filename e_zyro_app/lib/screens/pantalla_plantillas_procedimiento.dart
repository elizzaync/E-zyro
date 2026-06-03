import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFE53935);

/// Gestión del estándar (tipo manual) de **Procedimientos** fijos por tipo de
/// trabajo. Se carga un JSON con los procesos; al crear un servicio de ese tipo
/// se instancian esos pasos (llevan evidencias y alimentan el informe).
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
  List<Map<String, dynamic>> _plantillas = [];
  List<String> _tiposTrabajo = [];

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
    final plantillas = await s.getPlantillas();
    final catalogos = await s.getCatalogoServicios();
    final tipos = <String>{
      for (final c in catalogos)
        if (c.tipoTrabajo.trim().isNotEmpty) c.tipoTrabajo.trim(),
      for (final p in plantillas)
        if ((p['tipo_trabajo'] as String? ?? '').trim().isNotEmpty)
          (p['tipo_trabajo'] as String).trim(),
    }.toList()
      ..sort();
    if (!mounted) return;
    setState(() {
      _plantillas = plantillas;
      _tiposTrabajo = tipos;
      _cargando = false;
    });
  }

  Future<void> _editar({Map<String, dynamic>? plantilla}) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _EditorPlantilla(
          service: _service!,
          plantilla: plantilla,
          tiposSugeridos: _tiposTrabajo,
        ),
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
              onPressed: () => _editar(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)))
          : _plantillas.isEmpty
              ? _vacio()
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _plantillas.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(_plantillas[i]),
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
            const Text('Sin plantillas',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'Crea un estándar de procedimientos por tipo de trabajo (pozo, ups…). '
              'Se aplicará a los nuevos servicios de ese tipo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> p) {
    final surface = Theme.of(context).colorScheme.surface;
    final procesos = (p['procesos'] as List? ?? []);
    final activo = p['activo'] as bool? ?? true;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _editar(plantilla: p),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment_turned_in_outlined,
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
                        child: Text(p['nombre'] as String? ?? '',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                      if (!activo)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Inactiva',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tipo: ${p['tipo_trabajo'] ?? '—'} · ${procesos.length} pasos · v${p['version'] ?? 1}',
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
}

// ── Editor de una plantilla ───────────────────────────────────────────────────

class _EditorPlantilla extends StatefulWidget {
  final ProyectoService service;
  final Map<String, dynamic>? plantilla;
  final List<String> tiposSugeridos;

  const _EditorPlantilla({
    required this.service,
    required this.plantilla,
    required this.tiposSugeridos,
  });

  @override
  State<_EditorPlantilla> createState() => _EditorPlantillaState();
}

class _EditorPlantillaState extends State<_EditorPlantilla> {
  late final TextEditingController _tipo;
  late final TextEditingController _nombre;
  late final TextEditingController _json;
  bool _activo = true;
  bool _guardando = false;
  String? _error;

  bool get _esNuevo => widget.plantilla == null;

  @override
  void initState() {
    super.initState();
    final p = widget.plantilla;
    _tipo = TextEditingController(text: p?['tipo_trabajo'] as String? ?? '');
    _nombre = TextEditingController(text: p?['nombre'] as String? ?? '');
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
    _tipo.dispose();
    _nombre.dispose();
    _json.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _error = null);
    final tipo = _tipo.text.trim();
    final nombre = _nombre.text.trim();
    if (tipo.isEmpty) {
      setState(() => _error = 'Indica el tipo de trabajo.');
      return;
    }
    if (nombre.isEmpty) {
      setState(() => _error = 'Indica un nombre para la plantilla.');
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
      'tipo_trabajo': tipo,
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
        title: Text(_esNuevo ? 'Nueva plantilla' : 'Editar plantilla',
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
            TextField(
              controller: _tipo,
              decoration: InputDecoration(
                labelText: 'Tipo de trabajo (p. ej. pozo, ups)',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (widget.tiposSugeridos.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.tiposSugeridos
                    .map((t) => ActionChip(
                          label: Text(t, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() => _tipo.text = t),
                        ))
                    .toList(),
              ),
            ],
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
              Container(
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
                        child: Text(_error!,
                            style: const TextStyle(
                                color: _danger, fontSize: 12.5))),
                  ],
                ),
              ),
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
