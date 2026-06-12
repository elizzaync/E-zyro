import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/control_asistencia_models.dart';
import '../services/asistencia_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';

/// Tablero de supervisión de asistencias diarias (permiso asistencia:ver).
/// Muestra, por empleado: entrada/salida, almuerzo, horas netas trabajadas y
/// cumplimiento contra su turno (8 h por defecto; excepciones por turno).
class PantallaControlAsistencias extends StatefulWidget {
  const PantallaControlAsistencias({super.key});

  @override
  State<PantallaControlAsistencias> createState() =>
      _PantallaControlAsistenciasState();
}

class _PantallaControlAsistenciasState
    extends State<PantallaControlAsistencias> {
  static const _green = Color(0xFF8FD11B);
  static const _amber = Color(0xFFF59E0B);
  static const _danger = Color(0xFFE53935);
  static const _blue = Color(0xFF3B82F6);

  AsistenciaService? _svc;
  DateTime _fecha = DateTime.now();
  bool _cargando = true;
  ControlAsistenciaDia? _data;

  bool get _puedeGestionar => AppSession.i.canConfigurarTurnos;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _svc = await getAsistenciaService();
    await _cargar();
  }

  String get _fechaIso =>
      '${_fecha.year}-${_fecha.month.toString().padLeft(2, '0')}-${_fecha.day.toString().padLeft(2, '0')}';

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final data = await _svc?.getControlDiario(fecha: _fechaIso);
    if (!mounted) return;
    setState(() {
      _data = data;
      _cargando = false;
    });
  }

  Future<void> _pickFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _fecha = picked);
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de Asistencias'),
        actions: [
          IconButton(
            tooltip: 'Descargar asistencias',
            icon: const Icon(Icons.download_outlined),
            onPressed: _cargando ? null : _abrirDescarga,
          ),
          IconButton(
            tooltip: 'Elegir fecha',
            icon: const Icon(Icons.calendar_today_outlined),
            onPressed: _pickFecha,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: _data == null
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(
                            child: Text(
                                'No se pudo cargar el control de asistencias.')),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [
                        _barraFecha(isDark),
                        const SizedBox(height: 12),
                        _resumen(_data!.resumen),
                        const SizedBox(height: 16),
                        if (_data!.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 60),
                            child: Center(
                                child: Text('No hay empleados para mostrar.')),
                          )
                        else
                          ..._data!.items.map(_tarjetaEmpleado),
                      ],
                    ),
            ),
    );
  }

  Widget _barraFecha(bool isDark) {
    final etiqueta = _esHoy(_fecha) ? 'Hoy · $_fechaIso' : _fechaIso;
    return Row(
      children: [
        const Icon(Icons.event_note_outlined, size: 18, color: Colors.grey),
        const SizedBox(width: 8),
        Text(etiqueta,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const Spacer(),
        TextButton.icon(
          onPressed: _pickFecha,
          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
          label: const Text('Cambiar'),
        ),
      ],
    );
  }

  bool _esHoy(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  Widget _resumen(ControlResumen r) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _chip('Completos', r.completos, _green),
        _chip('Incompletos', r.incompletos, _amber),
        _chip('En curso', r.enCurso, _blue),
        _chip('Ausentes', r.ausentes, _danger),
      ],
    );
  }

  Widget _chip(String label, int valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$valor',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  ({Color color, String texto, IconData icon}) _estadoVisual(String estado) {
    switch (estado) {
      case 'completo':
        return (color: _green, texto: 'Completo', icon: Icons.check_circle);
      case 'incompleto':
        return (color: _amber, texto: 'Incompleto', icon: Icons.error_outline);
      case 'en_curso':
        return (color: _blue, texto: 'En curso', icon: Icons.timelapse);
      default:
        return (color: _danger, texto: 'Ausente', icon: Icons.remove_circle_outline);
    }
  }

  Widget _tarjetaEmpleado(ControlItem it) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vis = _estadoVisual(it.estado);
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: vis.color.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.nombreCompleto,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(it.cargo,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              _badgeEstado(vis),
            ],
          ),
          const SizedBox(height: 10),
          // Turno + horario designado
          Row(
            children: [
              Icon(
                it.esExcepcion ? Icons.star_outline : Icons.schedule,
                size: 15,
                color: it.esExcepcion ? _amber : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  it.turnoHorario.isEmpty
                      ? (it.esExcepcion ? 'Excepción · ${it.turnoNombre}' : it.turnoNombre)
                      : '${it.esExcepcion ? 'Excepción · ' : ''}${it.turnoNombre} · ${it.turnoHorario}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: it.esExcepcion ? _amber : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          // Puntualidad: tardanza / salida temprana
          if (it.llegoTarde || it.salioTemprano) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (it.llegoTarde)
                  _flagPuntualidad(
                      Icons.login, 'Tardanza ${_min(it.minutosTarde)}', _danger),
                if (it.salioTemprano)
                  _flagPuntualidad(Icons.logout,
                      'Salió ${_min(it.minutosAntesSalida)} antes', _amber),
              ],
            ),
          ],
          const SizedBox(height: 10),
          // Marcas
          Row(
            children: [
              _marca('Entrada', it.entradaHora),
              _marca('Salida', it.salidaHora),
              _marca('Almuerzo',
                  _rangoAlmuerzo(it.inicioAlmuerzoHora, it.finAlmuerzoHora)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          const SizedBox(height: 10),
          // Horas
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                'Trabajado: ${it.trabajadoLabel}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: it.cumple ? _green : (it.estado == 'incompleto' ? _amber : null),
                ),
              ),
              const Spacer(),
              Text('Requerido: ${it.requeridoLabel}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          if (_puedeGestionar) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _abrirAsignarTurno(it),
                icon: const Icon(Icons.tune, size: 16),
                label: const Text('Asignar horario'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _badgeEstado(({Color color, String texto, IconData icon}) vis) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: vis.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vis.icon, size: 14, color: vis.color),
          const SizedBox(width: 4),
          Text(vis.texto,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: vis.color)),
        ],
      ),
    );
  }

  String _min(int mins) {
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  Widget _flagPuntualidad(IconData icon, String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(texto,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _marca(String label, String? valor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(valor ?? '—',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: valor == null ? Colors.grey : null)),
        ],
      ),
    );
  }

  String? _rangoAlmuerzo(String? ini, String? fin) {
    if (ini == null && fin == null) return null;
    return '${ini ?? '—'} - ${fin ?? '—'}';
  }

  // ── Descarga de asistencias (día / semana / mes) ────────────────────────────
  Future<void> _abrirDescarga() async {
    if (_svc == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SheetDescarga(
        svc: _svc!,
        fechaAncla: _fechaIso,
      ),
    );
  }

  // ── Asignar turno-excepción ─────────────────────────────────────────────────
  Future<void> _abrirAsignarTurno(ControlItem it) async {
    final svc = _svc;
    if (svc == null) return;
    final turnos = await svc.getTurnos();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SheetAsignarTurno(
        empleado: it,
        turnos: turnos,
        svc: svc,
        onCreado: () async {
          Navigator.pop(ctx);
          await _cargar();
        },
      ),
    );
  }
}

// ── Bottom sheet: asignar un turno existente o crear uno nuevo ─────────────────
class _SheetAsignarTurno extends StatefulWidget {
  final ControlItem empleado;
  final List<TurnoItem> turnos;
  final AsistenciaService svc;
  final Future<void> Function() onCreado;

  const _SheetAsignarTurno({
    required this.empleado,
    required this.turnos,
    required this.svc,
    required this.onCreado,
  });

  @override
  State<_SheetAsignarTurno> createState() => _SheetAsignarTurnoState();
}

class _SheetAsignarTurnoState extends State<_SheetAsignarTurno> {
  String? _turnoId;
  bool _guardando = false;
  bool _modoCrear = false;

  // Campos de turno nuevo
  final _nombre = TextEditingController();
  TimeOfDay _entrada = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _salida = const TimeOfDay(hour: 17, minute: 0);
  final _almuerzo = TextEditingController(text: '60');

  @override
  void dispose() {
    _nombre.dispose();
    _almuerzo.dispose();
    super.dispose();
  }

  String _hhmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _guardarAsignacion() async {
    if (_turnoId == null) return;
    setState(() => _guardando = true);
    final ok = await widget.svc.asignarTurno(
      empleadoId: widget.empleado.empleadoId,
      turnoId: _turnoId!,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (ok) {
      await widget.onCreado();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo asignar el horario')),
      );
    }
  }

  Future<void> _crearYAsignar() async {
    if (_nombre.text.trim().isEmpty) return;
    setState(() => _guardando = true);
    final almu = int.tryParse(_almuerzo.text.trim()) ?? 60;
    final ok = await widget.svc.crearTurno(
      nombre: _nombre.text.trim(),
      horaEntrada: _hhmm(_entrada),
      horaSalida: _hhmm(_salida),
      duracionAlmuerzoMinutos: almu,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo crear el turno')),
      );
      return;
    }
    // Recargar lista de turnos y asignar el recién creado (por nombre).
    final turnos = await widget.svc.getTurnos();
    TurnoItem? nuevo;
    for (final t in turnos) {
      if (t.nombre == _nombre.text.trim()) nuevo = t;
    }
    if (nuevo != null) {
      await widget.svc.asignarTurno(
        empleadoId: widget.empleado.empleadoId,
        turnoId: nuevo.id,
      );
    }
    if (!mounted) return;
    setState(() => _guardando = false);
    await widget.onCreado();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Horario de ${widget.empleado.nombreCompleto}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Asigna un turno distinto (practicantes o contratos con horario especial). '
              'Si no se asigna ninguno, se usa el horario normal de 8 h.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (!_modoCrear) ...[
              if (widget.turnos.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Aún no hay turnos. Crea uno nuevo.',
                      style: TextStyle(color: Colors.grey)),
                )
              else
                ...widget.turnos.map((t) => RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: t.id,
                      groupValue: _turnoId,
                      onChanged: (v) => setState(() => _turnoId = v),
                      title: Text(t.nombre,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${t.horaEntrada}–${t.horaSalida} · almuerzo ${t.duracionAlmuerzoMinutos}m · ${t.horasNetas}h netas'),
                    )),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _modoCrear = true),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Crear turno nuevo'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed:
                        (_guardando || _turnoId == null) ? null : _guardarAsignacion,
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Asignar'),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _nombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre del turno',
                  hintText: 'Ej. Practicante mañana',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _selectorHora('Entrada', _entrada,
                        (t) => setState(() => _entrada = t)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _selectorHora('Salida', _salida,
                        (t) => setState(() => _salida = t)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _almuerzo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Almuerzo (minutos)',
                  hintText: '60',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _modoCrear = false),
                    child: const Text('Volver'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _guardando ? null : _crearYAsignar,
                    child: _guardando
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Crear y asignar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectorHora(
      String label, TimeOfDay valor, ValueChanged<TimeOfDay> onPick) {
    return InkWell(
      onTap: () async {
        final t = await showTimePicker(context: context, initialTime: valor);
        if (t != null) onPick(t);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(
            '${valor.hour.toString().padLeft(2, '0')}:${valor.minute.toString().padLeft(2, '0')}'),
      ),
    );
  }
}

// ── Bottom sheet: descargar asistencias (día / semana / mes) ───────────────────
class _SheetDescarga extends StatefulWidget {
  final AsistenciaService svc;
  final String fechaAncla; // YYYY-MM-DD seleccionada en el tablero

  const _SheetDescarga({required this.svc, required this.fechaAncla});

  @override
  State<_SheetDescarga> createState() => _SheetDescargaState();
}

class _SheetDescargaState extends State<_SheetDescarga> {
  static const _green = Color(0xFF8FD11B);
  static const _danger = Color(0xFFE53935);

  String _periodo = 'dia'; // dia | semana | mes
  String _formato = 'xlsx'; // xlsx | csv
  bool _descargando = false;

  Future<void> _descargar() async {
    setState(() => _descargando = true);
    final bytes = await widget.svc.descargarAsistencias(
      periodo: _periodo,
      formato: _formato,
      fecha: widget.fechaAncla,
    );
    if (!mounted) return;

    if (bytes == null) {
      setState(() => _descargando = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo generar la descarga'),
        backgroundColor: _danger,
      ));
      return;
    }

    final nombre = 'asistencias_${_periodo}_${widget.fechaAncla}.$_formato';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar asistencias',
        fileName: nombre,
        bytes: Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      setState(() => _descargando = false);
      if (path == null) return; // cancelado
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Descargado: $nombre',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _descargando = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo guardar el archivo'),
        backgroundColor: _danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Descargar asistencias',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Rango basado en la fecha ${widget.fechaAncla}. La semana abarca '
            'lunes a domingo; el mes, el mes calendario completo.',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Text('Periodo',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'dia', label: Text('Día')),
              ButtonSegment(value: 'semana', label: Text('Semana')),
              ButtonSegment(value: 'mes', label: Text('Mes')),
            ],
            selected: {_periodo},
            onSelectionChanged: (s) => setState(() => _periodo = s.first),
          ),
          const SizedBox(height: 16),
          const Text('Formato',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'xlsx',
                  label: Text('Excel'),
                  icon: Icon(Icons.grid_on, size: 16)),
              ButtonSegment(
                  value: 'csv',
                  label: Text('CSV'),
                  icon: Icon(Icons.description_outlined, size: 16)),
            ],
            selected: {_formato},
            onSelectionChanged: (s) => setState(() => _formato = s.first),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _descargando ? null : _descargar,
              icon: _descargando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download),
              label: Text(_descargando ? 'Generando…' : 'Descargar'),
            ),
          ),
        ],
      ),
    );
  }
}
