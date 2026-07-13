import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/control_asistencia_models.dart';
import '../services/asistencia_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import '../utils/descarga_archivo.dart';
import '../widgets/verdant_charts.dart';
import '../widgets/verdant_theme.dart';

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

  static const _avatarPalette = [
    Color(0xFF3E9A4E), Color(0xFF3E80C0), Color(0xFFD98A16),
    Color(0xFF7E57C2), Color(0xFFD6584F), Color(0xFF2BA89F),
  ];

  @override
  Widget build(BuildContext context) {
    final v = VerdantColors.of(context);
    return Scaffold(
      backgroundColor: v.dark ? const Color(0xFF0E1611) : const Color(0xFFF3F1E6),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _hero(v)),
                  if (_data == null)
                    const SliverFillRemaining(
                      child: Center(
                          child: Text(
                              'No se pudo cargar el control de asistencias.')),
                    )
                  else if (_data!.items.isEmpty)
                    const SliverPadding(
                      padding: EdgeInsets.only(top: 60),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                            child: Text('No hay empleados para mostrar.')),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: _data!.items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) =>
                            _tarjetaEmpleado(v, _data!.items[i], i),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _hero(VerdantColors v) {
    final etiqueta = _esHoy(_fecha) ? 'Hoy · $_fechaIso' : _fechaIso;
    final r = _data?.resumen;
    final total = r?.total ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      decoration: BoxDecoration(
        gradient: v.heroGradient,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: Icon(Icons.arrow_back, color: v.onHero),
                ),
                Expanded(
                  child: Text('Control de Asistencias',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 19, fontWeight: FontWeight.w700, color: v.onHero)),
                ),
                IconButton(
                  tooltip: 'Descargar asistencias',
                  onPressed: _cargando ? null : _abrirDescarga,
                  icon: Icon(Icons.download_outlined, color: v.onHero),
                  style: IconButton.styleFrom(backgroundColor: v.heroChip),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    decoration: BoxDecoration(
                      color: v.heroChip,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 15, color: v.onHero),
                        const SizedBox(width: 7),
                        Text(etiqueta,
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700, color: v.onHero)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _pickFecha,
                    child: Text('Cambiar',
                        style: TextStyle(fontWeight: FontWeight.w700, color: v.lime)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: v.heroCard,
                border: Border.all(color: v.heroBd),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Asistencia de hoy',
                      style: TextStyle(fontSize: 12, color: v.onHeroSub)),
                  RichText(
                    text: TextSpan(children: [
                      TextSpan(
                          text: '${r?.completos ?? 0} + ${(r?.enCurso ?? 0)} ',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 21, fontWeight: FontWeight.w700, color: v.onHero)),
                      TextSpan(
                          text: '/ $total marcaron',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: v.onHeroSub)),
                    ]),
                  ),
                  const SizedBox(height: 11),
                  StackBarChart(segments: [
                    StackBarSegment((r?.completos ?? 0).toDouble(), v.grn),
                    StackBarSegment((r?.incompletos ?? 0).toDouble(), v.amb),
                    StackBarSegment((r?.enCurso ?? 0).toDouble(), v.blu),
                    StackBarSegment((r?.ausentes ?? 0).toDouble(), v.red),
                  ], height: 13),
                  const SizedBox(height: 13),
                  Wrap(
                    spacing: 13,
                    runSpacing: 8,
                    children: [
                      _resumenDot('Completos', r?.completos ?? 0, v.grn, v),
                      _resumenDot('Incompletos', r?.incompletos ?? 0, v.amb, v),
                      _resumenDot('En curso', r?.enCurso ?? 0, v.blu, v),
                      _resumenDot('Ausentes', r?.ausentes ?? 0, v.red, v),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resumenDot(String label, int count, Color color, VerdantColors v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: v.onHero)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11.5, color: v.onHeroSub)),
      ],
    );
  }

  bool _esHoy(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  ({Color color, String texto, IconData icon}) _estadoVisual(VerdantColors v, String estado) {
    switch (estado) {
      case 'completo':
        return (color: v.grn, texto: 'Completo', icon: Icons.check_circle);
      case 'incompleto':
        return (color: v.amb, texto: 'Incompleto', icon: Icons.error_outline);
      case 'en_curso':
        return (color: v.blu, texto: 'En curso', icon: Icons.timelapse);
      default:
        return (color: v.red, texto: 'Ausente', icon: Icons.remove_circle_outline);
    }
  }

  String _iniciales(ControlItem it) {
    final n = it.nombre.trim();
    final a = it.apellido.trim();
    final i1 = n.isNotEmpty ? n[0] : '';
    final i2 = a.isNotEmpty ? a[0] : '';
    return ('$i1$i2').toUpperCase();
  }

  Widget _tarjetaEmpleado(VerdantColors v, ControlItem it, int index) {
    final vis = _estadoVisual(v, it.estado);
    final avatarColor = _avatarPalette[index % _avatarPalette.length];
    final pct = it.minutosRequeridos > 0
        ? ((it.minutosTrabajados ?? 0) / it.minutosRequeridos * 100).clamp(0, 100).toDouble()
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: v.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: v.bd),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: v.dark ? 0.30 : 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: avatarColor, borderRadius: BorderRadius.circular(14)),
                alignment: Alignment.center,
                child: Text(_iniciales(it), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.nombreCompleto,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: v.ink)),
                    const SizedBox(height: 2),
                    Text(
                      it.turnoHorario.isEmpty
                          ? '${it.cargo} · ${it.esExcepcion ? "Excepción · " : ""}${it.turnoNombre}'
                          : '${it.cargo} · ${it.turnoHorario}',
                      style: TextStyle(fontSize: 12, color: v.mut),
                    ),
                  ],
                ),
              ),
              _badgeEstado(vis),
            ],
          ),
          if (it.llegoTarde || it.salioTemprano) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (it.llegoTarde)
                  _flagPuntualidad(Icons.login, 'Tardanza ${_min(it.minutosTarde)}', v.red),
                if (it.salioTemprano)
                  _flagPuntualidad(Icons.logout, 'Salió ${_min(it.minutosAntesSalida)} antes', v.amb),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(color: v.cardAlt, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                _marca(v, 'Entrada', it.entradaHora, it.entradaHora == null ? v.mut : v.grn),
                _marca(v, 'Salida', it.salidaHora, it.salidaHora == null ? v.mut : v.ink),
                _marca(v, 'Almuerzo', _rangoAlmuerzo(it.inicioAlmuerzoHora, it.finAlmuerzoHora), v.sub),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Trabajado', style: TextStyle(fontSize: 12, color: v.mut)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 7,
                    backgroundColor: v.track,
                    valueColor: AlwaysStoppedAnimation<Color>(it.estado == 'ausente' ? v.red : (it.cumple ? v.grn : v.lime)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(it.trabajadoLabel,
                  style: GoogleFonts.spaceGrotesk(fontSize: 12.5, fontWeight: FontWeight.w800, color: v.ink)),
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
      child: Text(vis.texto,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: vis.color)),
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

  Widget _marca(VerdantColors v, String label, String? valor, Color valColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, color: v.mut)),
          const SizedBox(height: 2),
          Text(valor ?? '—',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: valor == null ? v.mut : valColor)),
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
  // Vigencia de la excepción: por defecto hoy, pero editable. Importa para los
  // reportes: la puntualidad se mide contra este turno solo desde esta fecha.
  DateTime _vigenteDesde = DateTime.now();

  String _fmtFecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Campos de turno nuevo
  final _nombre = TextEditingController();
  TimeOfDay _entrada = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _salida = const TimeOfDay(hour: 17, minute: 0);
  final _almuerzo = TextEditingController(text: '60');
  // Días laborales del turno nuevo (ISO 1=Lun … 7=Dom). Por defecto L-V.
  final Set<int> _diasLaborales = {1, 2, 3, 4, 5};

  // Etiquetas cortas de los 7 días, en orden Lun→Dom.
  static const _diasSemana = <({int iso, String label})>[
    (iso: 1, label: 'L'),
    (iso: 2, label: 'M'),
    (iso: 3, label: 'X'),
    (iso: 4, label: 'J'),
    (iso: 5, label: 'V'),
    (iso: 6, label: 'S'),
    (iso: 7, label: 'D'),
  ];

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
      fechaDesde: _fmtFecha(_vigenteDesde),
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
    if (_diasLaborales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona al menos un día de trabajo')),
      );
      return;
    }
    setState(() => _guardando = true);
    final almu = int.tryParse(_almuerzo.text.trim()) ?? 60;
    final diasCsv = (_diasLaborales.toList()..sort()).join(',');
    final ok = await widget.svc.crearTurno(
      nombre: _nombre.text.trim(),
      horaEntrada: _hhmm(_entrada),
      horaSalida: _hhmm(_salida),
      duracionAlmuerzoMinutos: almu,
      diasLaborales: diasCsv,
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
        fechaDesde: _fmtFecha(_vigenteDesde),
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
                          '${t.horaEntrada}–${t.horaSalida} · ${t.diasLabel} · almuerzo ${t.duracionAlmuerzoMinutos}m · ${t.horasNetas}h netas'),
                    )),
              const SizedBox(height: 8),
              // Vigencia: desde cuándo aplica esta excepción (afecta reportes).
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _vigenteDesde,
                    firstDate: DateTime(2024, 1, 1),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _vigenteDesde = picked);
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    const Icon(Icons.event_outlined, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('Vigente desde: ${_fmtFecha(_vigenteDesde)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Text('(toca para cambiar)',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                ),
              ),
              const SizedBox(height: 4),
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
              const Text('Días de trabajo',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _diasSemana.map((d) {
                  final sel = _diasLaborales.contains(d.iso);
                  return FilterChip(
                    label: Text(d.label),
                    selected: sel,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _diasLaborales.add(d.iso);
                      } else {
                        _diasLaborales.remove(d.iso);
                      }
                    }),
                  );
                }).toList(),
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
  static const _danger = Color(0xFFD6584F);

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
      final path = await guardarArchivo(
        dialogTitle: 'Guardar asistencias',
        fileName: nombre,
        bytes: bytes,
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
                  value: 'pdf',
                  label: Text('PDF'),
                  icon: Icon(Icons.picture_as_pdf_outlined, size: 16)),
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
