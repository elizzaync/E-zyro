import 'package:flutter/material.dart';

import '../core/api_result.dart';
import '../models/evaluacion_models.dart';
import '../models/personal_models.dart';
import '../services/evaluacion_service.dart';
import '../services/personal_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Pantalla de gestión de plantillas de evaluación.
/// Permite crear/editar/eliminar plantillas y asignarlas a empleados.
class PantallaPlantillasEvaluacion extends StatefulWidget {
  const PantallaPlantillasEvaluacion({super.key});

  @override
  State<PantallaPlantillasEvaluacion> createState() => _PantallaPlantillasEvaluacionState();
}

class _PantallaPlantillasEvaluacionState extends State<PantallaPlantillasEvaluacion> {
  EvaluacionService? _svc;
  List<PlantillaEvaluacion> _plantillas = [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getEvaluacionService();
    await _cargar();
  }

  Future<void> _cargar() async {
    if (_svc == null) return;
    setState(() { _cargando = true; _error = null; });
    final r = await _svc!.listarPlantillas();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.ok) _plantillas = r.data ?? [];
      else _error = r.errorMessage;
    });
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _editarPlantilla([PlantillaEvaluacion? existing]) async {
    final svc = _svc;
    if (svc == null) return;

    final criteriosR = await svc.listarCriterios();
    if (!mounted) return;
    if (!criteriosR.ok) {
      _snack('No se pudieron cargar los criterios', error: true);
      return;
    }
    final criterios = criteriosR.data ?? [];

    final nombreCtrl = TextEditingController(text: existing?.nombre ?? '');
    final descCtrl = TextEditingController(text: existing?.descripcion ?? '');
    String tipo = existing?.tipo ?? TipoEvaluacion.rrhh;
    // criterioId → peso seleccionado
    final Map<String, double> seleccionados = {
      for (final item in existing?.items ?? []) item.criterioId: item.peso,
    };
    final int orden = 0;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Nueva plantilla' : 'Editar plantilla'),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: TipoEvaluacion.todos.map((t) => DropdownMenuItem(
                  value: t, child: Text(TipoEvaluacion.etiqueta(t)))).toList(),
                onChanged: (v) => setLocal(() => tipo = v ?? tipo),
              ),
              const SizedBox(height: 16),
              const Text('Criterios incluidos', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              if (criterios.isEmpty)
                const Text('Sin criterios disponibles. Créalos primero en la pestaña Criterios.',
                    style: TextStyle(fontSize: 12, color: Colors.grey))
              else
                ...criterios.map((c) {
                  final seleccionado = seleccionados.containsKey(c.id);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.nombre, style: const TextStyle(fontSize: 13)),
                    subtitle: Text('Peso base: ${c.peso.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11)),
                    value: seleccionado,
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        seleccionados[c.id] = c.peso;
                      } else {
                        seleccionados.remove(c.id);
                      }
                    }),
                  );
                }),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (nombreCtrl.text.trim().isEmpty) return;
                if (seleccionados.isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;

    final items = seleccionados.entries.toList().asMap().entries.map((e) => {
      'criterio_id': e.value.key,
      'peso': e.value.value,
      'orden': e.key,
    }).toList();

    ApiResult<PlantillaEvaluacion> r;
    if (existing == null) {
      r = await svc.crearPlantilla(
        nombre: nombreCtrl.text.trim(),
        descripcion: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        tipo: tipo, items: items,
      );
    } else {
      r = await svc.editarPlantilla(
        id: existing.id,
        nombre: nombreCtrl.text.trim(),
        descripcion: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        tipo: tipo, items: items,
      );
    }

    if (!mounted) return;
    if (r.ok) {
      _snack('Plantilla guardada');
      _cargar();
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  Future<void> _eliminarPlantilla(PlantillaEvaluacion p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar plantilla'),
        content: Text('¿Eliminar "${p.nombre}"? Esta acción no borra evaluaciones existentes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final r = await _svc!.eliminarPlantilla(p.id);
    if (!mounted) return;
    r.ok ? _cargar() : _snack(r.errorMessage, error: true);
  }

  Future<void> _asignarPlantilla(PlantillaEvaluacion plantilla) async {
    final psvc = await getPersonalService();
    final empR = await psvc.listar();
    if (!mounted) return;
    if (!empR.ok) {
      _snack('No se pudieron cargar los empleados', error: true);
      return;
    }
    final empleados = empR.data ?? [];
    final Set<String> selIds = {};
    final periodoCtrl = TextEditingController(
      text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
    );

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Asignar: ${plantilla.nombre}'),
          scrollable: true,
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: periodoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Periodo *',
                  helperText: 'Ej: 2026-06 o "Q2 2026"',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Seleccionar empleados', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              ...empleados.map((e) {
                final nombre = e.nombre ?? e.id;
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(nombre, style: const TextStyle(fontSize: 13)),
                  value: selIds.contains(e.id),
                  onChanged: (v) => setLocal(() {
                    if (v == true) selIds.add(e.id);
                    else selIds.remove(e.id);
                  }),
                );
              }),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (periodoCtrl.text.trim().isEmpty || selIds.isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Asignar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final r = await _svc!.asignarPlantilla(
      plantillaId: plantilla.id,
      empleadoIds: selIds.toList(),
      periodo: periodoCtrl.text.trim(),
    );
    if (!mounted) return;
    if (r.ok) {
      _snack('Plantilla asignada a ${r.data?.length ?? 0} empleado(s)');
    } else {
      _snack(r.errorMessage, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plantillas de Evaluación', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: AppSession.i.canCrearEvaluacion
          ? FloatingActionButton.extended(
              onPressed: () => _editarPlantilla(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva plantilla'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _plantillas.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment_outlined, size: 48, color: Colors.grey),
                          SizedBox(height: 12),
                          Text('Sin plantillas de evaluación.\nCrea la primera con el botón +',
                              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.separated(
                        itemCount: _plantillas.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = _plantillas[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.indigo.shade50,
                              child: Text('${p.items.length}',
                                  style: TextStyle(color: Colors.indigo.shade700, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${TipoEvaluacion.etiqueta(p.tipo)} · ${p.items.length} criterio(s)'
                              '${p.descripcion != null ? '\n${p.descripcion}' : ''}',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: p.descripcion != null,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'asignar') _asignarPlantilla(p);
                                if (v == 'editar') _editarPlantilla(p);
                                if (v == 'eliminar') _eliminarPlantilla(p);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'asignar', child: ListTile(
                                  dense: true, leading: Icon(Icons.person_add_outlined),
                                  title: Text('Asignar a empleado(s)'))),
                                if (AppSession.i.canEditarEvaluacion)
                                  const PopupMenuItem(value: 'editar', child: ListTile(
                                    dense: true, leading: Icon(Icons.edit_outlined),
                                    title: Text('Editar'))),
                                if (AppSession.i.canEliminarEvaluacion)
                                  const PopupMenuItem(value: 'eliminar', child: ListTile(
                                    dense: true, leading: Icon(Icons.delete_outline, color: Colors.red),
                                    title: Text('Eliminar', style: TextStyle(color: Colors.red)))),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
