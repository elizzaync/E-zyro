import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';

/// Configuración de un servicio (HU-13): asigna el equipo técnico y arma el
/// cronograma de tareas (procedimientos con responsable y fechas) que alimenta
/// el Diagrama de Gantt. Guarda con POST /operaciones/servicio/{id}/configurar.
///
/// Equivalente móvil del `asignacion-servicio-modal` del frontend Angular.
class PantallaAsignacionServicio extends StatefulWidget {
  final String servicioId;
  final ProyectoService service;

  /// 'crear' = primera configuración · 'editar' = precarga equipo y cronograma.
  final String mode;

  const PantallaAsignacionServicio({
    super.key,
    required this.servicioId,
    required this.service,
    this.mode = 'editar',
  });

  @override
  State<PantallaAsignacionServicio> createState() =>
      _PantallaAsignacionServicioState();
}

class _TareaForm {
  final TextEditingController nombre;
  String? responsableId;
  String? fechaInicio; // YYYY-MM-DD
  String? fechaFin; // YYYY-MM-DD
  String? cruceMsg; // advertencia de cruce de horario
  bool validando = false;

  _TareaForm({
    String nombre = '',
    this.responsableId,
    this.fechaInicio,
    this.fechaFin,
  }) : nombre = TextEditingController(text: nombre);

  bool get completa =>
      nombre.text.trim().isNotEmpty &&
      (responsableId ?? '').isNotEmpty &&
      (fechaInicio ?? '').isNotEmpty &&
      (fechaFin ?? '').isNotEmpty;
}

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFE53935);
const _amber = Color(0xFFF59E0B);

class _PantallaAsignacionServicioState
    extends State<PantallaAsignacionServicio> {
  // ── Datos ──────────────────────────────────────────────────────────────────
  ServicioDetalle? _servicio;
  List<TecnicoDisponible> _todosTecnicos = [];
  List<GrupoDisponible> _grupos = [];
  final List<TecnicoDisponible> _equipo = [];
  final List<_TareaForm> _tareas = [];

  // ── UI ───────────────────────────────────────────────────────────────────
  int _seccion = 0; // 0=resumen 1=equipo 2=cronograma
  bool _cargando = true;
  bool _guardando = false;
  String _busqueda = '';
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final t in _tareas) {
      t.nombre.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final results = await Future.wait([
      widget.service.getDetalleServicio(widget.servicioId),
      widget.service.getPersonalTecnicos(),
    ]);
    if (!mounted) return;

    final detalle = results[0] as ServicioDetalle?;
    final personal = results[1] as PersonalTecnicos;

    _todosTecnicos = personal.tecnicos;
    _grupos = personal.grupos;
    _servicio = detalle;

    _equipo.clear();
    _tareas.clear();

    if (widget.mode == 'editar' && detalle != null) {
      // Precargar equipo ya asignado
      for (final m in detalle.equipo) {
        // Preferir el técnico del catálogo (trae grupoActual), si existe.
        final existente = _todosTecnicos.where((t) => t.id == m.id);
        _equipo.add(existente.isNotEmpty
            ? existente.first
            : TecnicoDisponible.fromMiembro(m));
      }
      // Precargar cronograma (Tareas)
      for (final t in detalle.tareas) {
        _tareas.add(_TareaForm(
          nombre: t.nombre,
          responsableId: t.responsableId,
          fechaInicio: _soloFecha(t.fechaInicioTarea),
          fechaFin: _soloFecha(t.fechaLimite),
        ));
      }
    }

    if (_tareas.isEmpty) _tareas.add(_TareaForm());

    setState(() => _cargando = false);
  }

  String? _soloFecha(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    return iso.contains('T') ? iso.split('T').first : iso.trim();
  }

  // ── Técnicos ────────────────────────────────────────────────────────────────

  List<TecnicoDisponible> get _tecnicosFiltrados {
    final disponibles =
        _todosTecnicos.where((t) => !_estaSeleccionado(t.id)).toList();
    final q = _busqueda.toLowerCase().trim();
    if (q.isEmpty) return disponibles;
    return disponibles
        .where((t) =>
            t.nombreCompleto.toLowerCase().contains(q) ||
            t.cargo.toLowerCase().contains(q) ||
            (t.grupoActual ?? '').toLowerCase().contains(q))
        .toList();
  }

  bool _estaSeleccionado(String id) => _equipo.any((t) => t.id == id);

  Future<void> _seleccionarTecnico(TecnicoDisponible t) async {
    if (_estaSeleccionado(t.id)) return;
    if (t.grupoActual != null && t.grupoActual!.isNotEmpty) {
      final ok = await _confirmarGrupo(t);
      if (ok != true) return;
    }
    setState(() => _equipo.add(t));
  }

  Future<bool?> _confirmarGrupo(TecnicoDisponible t) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Técnico en un grupo'),
        content: Text(
          '${t.nombreCompleto} pertenece al grupo "${t.grupoActual}". '
          '¿Deseas añadirlo igualmente a este servicio?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Añadir', style: TextStyle(color: _green))),
        ],
      ),
    );
  }

  void _agregarGrupo(GrupoDisponible g) {
    var cambio = false;
    for (final m in g.miembros) {
      if (!_estaSeleccionado(m.id)) {
        _equipo.add(m);
        cambio = true;
      }
    }
    if (cambio) setState(() {});
  }

  void _removerTecnico(String id) {
    setState(() {
      _equipo.removeWhere((t) => t.id == id);
      for (final t in _tareas) {
        if (t.responsableId == id) {
          t.responsableId = null;
          t.cruceMsg = null;
        }
      }
    });
  }

  // ── Cronograma ───────────────────────────────────────────────────────────────

  void _agregarTarea() => setState(() => _tareas.add(_TareaForm()));

  void _removerTarea(int i) {
    if (_tareas.length <= 1) return;
    setState(() {
      _tareas[i].nombre.dispose();
      _tareas.removeAt(i);
    });
  }

  Future<void> _pickFecha(int i, bool inicio) async {
    final t = _tareas[i];
    final base = DateTime.tryParse(
            (inicio ? t.fechaInicio : t.fechaFin) ?? '') ??
        DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    final str = DateFormat('yyyy-MM-dd').format(picked);
    setState(() {
      if (inicio) {
        t.fechaInicio = str;
        // si fin < inicio, igualar
        if (t.fechaFin != null && t.fechaFin!.compareTo(str) < 0) {
          t.fechaFin = str;
        }
      } else {
        t.fechaFin = str;
      }
    });
    _validarCruce(i);
  }

  Future<void> _validarCruce(int i) async {
    final t = _tareas[i];
    if (!t.completa) {
      setState(() => t.cruceMsg = null);
      return;
    }
    setState(() {
      t.validando = true;
      t.cruceMsg = null;
    });
    final conflicto = await widget.service.validarHorario(
      empleadoId: t.responsableId!,
      fechaInicio: t.fechaInicio!,
      fechaFin: t.fechaFin!,
      excluirServicioId: widget.servicioId,
    );
    if (!mounted) return;
    setState(() {
      t.validando = false;
      t.cruceMsg = conflicto?.mensaje;
    });
  }

  // ── Navegación de secciones ──────────────────────────────────────────────────

  void _irSeccion(int n) => setState(() {
        _seccion = n;
        _errorMsg = null;
      });

  void _siguiente() {
    if (_seccion == 0 && _servicio == null) {
      setState(() => _errorMsg = 'El servicio aún no cargó. Espera un momento.');
      return;
    }
    if (_seccion < 2) _irSeccion(_seccion + 1);
  }

  void _anterior() {
    if (_seccion > 0) _irSeccion(_seccion - 1);
  }

  // ── Guardar ──────────────────────────────────────────────────────────────────

  Future<void> _guardar() async {
    setState(() => _errorMsg = null);

    if (_equipo.isEmpty) {
      setState(() {
        _errorMsg = 'Debes asignar al menos un técnico al equipo.';
        _seccion = 1;
      });
      return;
    }

    for (var i = 0; i < _tareas.length; i++) {
      final t = _tareas[i];
      if (!t.completa) {
        setState(() {
          _errorMsg = 'Completa nombre, responsable y fechas en cada tarea.';
          _seccion = 2;
        });
        return;
      }
      if (t.fechaFin!.compareTo(t.fechaInicio!) < 0) {
        setState(() {
          _errorMsg = 'La fecha de fin no puede ser anterior a la de inicio.';
          _seccion = 2;
        });
        return;
      }
    }

    setState(() => _guardando = true);

    final procedimientos = _tareas
        .map((t) => {
              'nombre': t.nombre.text.trim(),
              'responsable_id': t.responsableId,
              'fecha_inicio': t.fechaInicio,
              'fecha_fin': t.fechaFin,
            })
        .toList();

    final ok = await widget.service.configurarServicio(
      widget.servicioId,
      equipo: _equipo.map((t) => t.id).toList(),
      procedimientos: procedimientos,
    );

    if (!mounted) return;
    setState(() => _guardando = false);

    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _errorMsg = 'No se pudo guardar. Intenta nuevamente.');
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Configurar asignación',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(_green)),
            )
          : Column(
              children: [
                _buildStepper(),
                if (_errorMsg != null) _buildError(),
                Expanded(
                  child: switch (_seccion) {
                    0 => _buildResumen(),
                    1 => _buildEquipo(),
                    _ => _buildCronograma(),
                  },
                ),
                _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildStepper() {
    const labels = ['Resumen', 'Equipo', 'Cronograma'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: List.generate(3, (i) {
          final activo = i == _seccion;
          final hecho = i < _seccion;
          return Expanded(
            child: GestureDetector(
              onTap: () => _irSeccion(i),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (i > 0)
                        Expanded(
                            child: Container(
                                height: 2,
                                color: (hecho || activo)
                                    ? _green
                                    : Colors.grey.shade300)),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: (activo || hecho) ? _green : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: (activo || hecho)
                                  ? _green
                                  : Colors.grey.shade400,
                              width: 1.5),
                        ),
                        child: Center(
                          child: hecho
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : Text('${i + 1}',
                                  style: TextStyle(
                                      color: activo
                                          ? Colors.white
                                          : Colors.grey.shade500,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                        ),
                      ),
                      if (i < 2)
                        Expanded(
                            child: Container(
                                height: 2,
                                color: hecho
                                    ? _green
                                    : Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(labels[i],
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              activo ? FontWeight.w700 : FontWeight.w500,
                          color: activo ? _green : Colors.grey)),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
              child: Text(_errorMsg!,
                  style: const TextStyle(color: _danger, fontSize: 12.5))),
        ],
      ),
    );
  }

  // ── Sección 1: Resumen ───────────────────────────────────────────────────────

  Widget _buildResumen() {
    final s = _servicio;
    if (s == null) {
      return const Center(child: Text('No se pudo cargar el servicio.'));
    }
    final surface = Theme.of(context).colorScheme.surface;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _green.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.tipoServicio,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            if (s.descripcion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(s.descripcion,
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ),
            _infoRow(Icons.business_outlined, 'Cliente', s.cliente),
            _infoRow(Icons.location_on_outlined, 'Ubicación', s.ubicacion),
            _infoRow(Icons.calendar_today_outlined, 'Fecha', s.fechaStr),
            _infoRow(Icons.flag_outlined, 'Estado',
                s.estado == 'En_Proceso' ? 'En Proceso' : s.estado),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: _green, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Asigna el equipo técnico y arma el cronograma de tareas. '
                      'Las fechas alimentan el Diagrama de Gantt.',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  // ── Sección 2: Equipo ────────────────────────────────────────────────────────

  Widget _buildEquipo() {
    return Column(
      children: [
        // Seleccionados
        if (_equipo.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Equipo seleccionado (${_equipo.length})',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(() {
                        _equipo.clear();
                        for (final t in _tareas) {
                          t.responsableId = null;
                          t.cruceMsg = null;
                        }
                      }),
                      child: const Text('Limpiar',
                          style: TextStyle(color: _danger, fontSize: 12)),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _equipo
                      .map((t) => Chip(
                            avatar: _avatar(t, 11),
                            label: Text(t.nombreCompleto,
                                style: const TextStyle(fontSize: 12)),
                            onDeleted: () => _removerTecnico(t.id),
                            deleteIconColor: _danger,
                            backgroundColor: _green.withValues(alpha: 0.10),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        // Buscador
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _busqueda = v),
            decoration: InputDecoration(
              hintText: 'Buscar técnico, cargo o grupo...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        // Grupos (chips para agregar todo el grupo)
        if (_grupos.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _grupos
                  .map((g) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.groups_outlined,
                              size: 16, color: _green),
                          label: Text('${g.nombre} (${g.miembros.length})',
                              style: const TextStyle(fontSize: 12)),
                          onPressed: () => _agregarGrupo(g),
                        ),
                      ))
                  .toList(),
            ),
          ),
        // Lista disponible
        Expanded(
          child: _tecnicosFiltrados.isEmpty
              ? Center(
                  child: Text(
                      _todosTecnicos.isEmpty
                          ? 'No hay técnicos disponibles.'
                          : 'Todos los técnicos ya están seleccionados.',
                      style: const TextStyle(color: Colors.grey)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _tecnicosFiltrados.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final t = _tecnicosFiltrados[i];
                    return ListTile(
                      onTap: () => _seleccionarTecnico(t),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      tileColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      leading: _avatar(t, 18),
                      title: Text(t.nombreCompleto,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        t.grupoActual != null && t.grupoActual!.isNotEmpty
                            ? '${t.cargo} · Grupo: ${t.grupoActual}'
                            : t.cargo,
                        style: TextStyle(
                            fontSize: 12,
                            color: t.grupoActual != null &&
                                    t.grupoActual!.isNotEmpty
                                ? _amber
                                : Colors.grey),
                      ),
                      trailing: const Icon(Icons.add_circle_outline,
                          color: _green),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _avatar(TecnicoDisponible t, double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _green.withValues(alpha: 0.18),
      backgroundImage: t.fotoUrl.isNotEmpty ? CachedNetworkImageProvider(t.fotoUrl) : null,
      child: t.fotoUrl.isEmpty
          ? Text(t.iniciales,
              style: TextStyle(
                  color: _green,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.8))
          : null,
    );
  }

  // ── Sección 3: Cronograma ─────────────────────────────────────────────────────

  Widget _buildCronograma() {
    if (_equipo.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Primero selecciona el equipo en el paso anterior.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _tareas.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        if (i == _tareas.length) {
          return OutlinedButton.icon(
            onPressed: _agregarTarea,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _green),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.add, color: _green),
            label: const Text('Agregar tarea',
                style: TextStyle(color: _green, fontWeight: FontWeight.w600)),
          );
        }
        return _buildTareaCard(i);
      },
    );
  }

  Widget _buildTareaCard(int i) {
    final t = _tareas[i];
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: t.cruceMsg != null
                ? _amber.withValues(alpha: 0.6)
                : Colors.grey.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                    color: _green, shape: BoxShape.circle),
                child: Center(
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 8),
              const Text('Tarea',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const Spacer(),
              if (_tareas.length > 1)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline,
                      color: _danger, size: 20),
                  onPressed: () => _removerTarea(i),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: t.nombre,
            decoration: InputDecoration(
              labelText: 'Nombre de la tarea',
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _equipo.any((e) => e.id == t.responsableId)
                ? t.responsableId
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Responsable',
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            items: _equipo
                .map((e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(e.nombreCompleto,
                          overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) {
              setState(() => t.responsableId = v);
              _validarCruce(i);
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _fechaBtn(
                      'Inicio', t.fechaInicio, () => _pickFecha(i, true))),
              const SizedBox(width: 10),
              Expanded(
                  child: _fechaBtn(
                      'Fin', t.fechaFin, () => _pickFecha(i, false))),
            ],
          ),
          if (t.validando)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Validando horario...',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          if (t.cruceMsg != null)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _amber, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(t.cruceMsg!,
                          style: const TextStyle(
                              fontSize: 11.5, color: Color(0xFF8A6100)))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _fechaBtn(String label, String? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 14),
            const SizedBox(width: 6),
            Text(value ?? 'Elegir',
                style: TextStyle(
                    fontSize: 13,
                    color: value == null ? Colors.grey : null)),
          ],
        ),
      ),
    );
  }

  // ── Barra inferior ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() {
    final esUltima = _seccion == 2;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            if (_seccion > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: _guardando ? null : _anterior,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Anterior'),
                ),
              ),
            if (_seccion > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _guardando
                    ? null
                    : (esUltima ? _guardar : _siguiente),
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
                    : Text(esUltima ? 'Guardar asignación' : 'Siguiente',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
