import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import '../services/programacion_campo_service.dart';
import '../utils/api_provider.dart';

/// HU-54: asignar la cuadrilla de campo de un día/proyecto — separado del
/// fichaje de asistencia. Solo Jefe de Operaciones/Admin (backend valida con
/// exigir_no_tecnico). Alimenta el reporte de horas hombre por proyecto.
class PantallaCuadrillaCampo extends StatefulWidget {
  const PantallaCuadrillaCampo({super.key});

  @override
  State<PantallaCuadrillaCampo> createState() =>
      _PantallaCuadrillaCampoState();
}

class _PantallaCuadrillaCampoState extends State<PantallaCuadrillaCampo> {
  static const _green = Color(0xFF8FD11B);

  ProyectoService? _proyectoService;
  ProgramacionCampoService? _programacionService;

  bool _cargando = true;
  bool _guardando = false;

  List<ProyectoItem> _proyectos = [];
  List<TecnicoDisponible> _tecnicos = [];
  String? _proyectoId;
  DateTime _fecha = DateTime.now();
  final Set<String> _seleccionados = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _proyectoService = await getProyectoService();
    _programacionService = await getProgramacionCampoService();
    final results = await Future.wait([
      _proyectoService!.getProyectos(),
      _proyectoService!.getPersonalTecnicos(),
    ]);
    if (!mounted) return;
    final kpis = results[0] as ProyectosConKpis?;
    final personal = results[1] as PersonalTecnicos;
    setState(() {
      _proyectos = kpis?.proyectos ?? [];
      _tecnicos = personal.tecnicos;
      _cargando = false;
    });
    if (_proyectoId != null) _cargarAsignacionExistente();
  }

  Future<void> _cargarAsignacionExistente() async {
    if (_proyectoId == null || _programacionService == null) return;
    final fechaStr = DateFormat('yyyy-MM-dd').format(_fecha);
    final existentes = await _programacionService!.listarProgramacion(
      fecha: fechaStr,
      proyectoId: _proyectoId,
    );
    if (!mounted) return;
    setState(() {
      _seleccionados.clear();
      if (existentes.isNotEmpty) {
        _seleccionados.addAll(existentes.first.empleados.map((e) => e.empleadoId));
      }
    });
  }

  Future<void> _guardar() async {
    if (_proyectoId == null || _programacionService == null) return;
    setState(() => _guardando = true);
    final ok = await _programacionService!.asignarCuadrilla(
      proyectoId: _proyectoId!,
      fecha: DateFormat('yyyy-MM-dd').format(_fecha),
      empleadoIds: _seleccionados.toList(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok != null
          ? 'Cuadrilla guardada (${_seleccionados.length} personas)'
          : 'No se pudo guardar la cuadrilla'),
    ));
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (elegida == null) return;
    setState(() => _fecha = elegida);
    _cargarAsignacionExistente();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuadrilla de Campo')),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_green)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Proyecto',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _proyectoId,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  hint: const Text('Selecciona un proyecto'),
                  items: _proyectos
                      .map((p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.nombreProyecto,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _proyectoId = v);
                    _cargarAsignacionExistente();
                  },
                ),
                const SizedBox(height: 16),
                Text('Fecha', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _elegirFecha,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(DateFormat('dd/MM/yyyy').format(_fecha)),
                ),
                const SizedBox(height: 20),
                Text('Empleados asignados (${_seleccionados.length})',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                ..._tecnicos.map((t) => CheckboxListTile(
                      value: _seleccionados.contains(t.id),
                      title: Text('${t.nombre} ${t.apellido}'),
                      subtitle: Text(t.cargo),
                      activeColor: _green,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _seleccionados.add(t.id);
                          } else {
                            _seleccionados.remove(t.id);
                          }
                        });
                      },
                    )),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed:
                      (_proyectoId == null || _guardando) ? null : _guardar,
                  style: FilledButton.styleFrom(backgroundColor: _green),
                  child: _guardando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Guardar cuadrilla'),
                ),
              ],
            ),
    );
  }
}
