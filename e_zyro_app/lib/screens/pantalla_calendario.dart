import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/asistencia_models.dart';
import '../models/comunicado_models.dart';
import '../models/dashboard_models.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/app_notifiers.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';

// ── Tipos de evento ───────────────────────────────────────────────────────────
enum _EventType { asistencia, proyecto, comunicado, nota }

class _CalEvent {
  final _EventType type;
  final String title;
  final String? subtitle;
  final Color color;

  const _CalEvent({
    required this.type,
    required this.title,
    this.subtitle,
    required this.color,
  });
}

DateTime _dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String _toDateStr(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

// ── Pantalla principal ────────────────────────────────────────────────────────
class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  static const _green  = Color(0xFF8FD11B);
  static const _orange = Color(0xFFF59E0B);
  static const _blue   = Color(0xFF3B82F6);
  static const _violet = Color(0xFF8B5CF6);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  Map<DateTime, List<_CalEvent>> _events = {};
  CalendarioData? _calData;
  List<DetalleServicioDia> _detallesDia = [];

  bool _isLoading    = true;
  bool _loadDetalle  = false;
  bool _savingNota   = false;
  StreamSubscription<RemoteMessage>? _fcmSub;
  DateTime? _lastFullLoad;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dayKey(DateTime.now());
    _loadAll();
    _fcmSub = FcmFlutterService.messageStream.listen(_onFcmMessage);
    syncCompletedNotifier.addListener(_onSyncCompleted);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    syncCompletedNotifier.removeListener(_onSyncCompleted);
    super.dispose();
  }

  void _onFcmMessage(RemoteMessage msg) {
    final tipo = msg.data['tipo'] as String? ?? '';
    if (tipo == 'recordatorio' ||
        tipo == 'asignacion_servicio' ||
        tipo == 'asignacion_proyecto') {
      _throttledLoad();
    }
  }

  void _onSyncCompleted() => _throttledLoad();

  void _throttledLoad() {
    if (!mounted) return;
    final ahora = DateTime.now();
    if (_lastFullLoad != null &&
        ahora.difference(_lastFullLoad!) < const Duration(seconds: 60)) {
      return;
    }
    _lastFullLoad = ahora;
    _loadAll();
  }

  // ── Carga principal ───────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    try {
      final dashSvc  = await getDashboardService();
      final asistSvc = await getAsistenciaService();
      final comSvc   = await getComunicadoService();

      final results = await Future.wait([
        dashSvc.getCalendario(),
        asistSvc.getHistorial(pagina: 1),
        asistSvc.getHistorial(pagina: 2),
        comSvc.getComunicados(),
      ], eagerError: false);

      if (!mounted) return;

      final calData    = results[0] as CalendarioData?;
      final registros1 = results[1] is List ? results[1] as List<RegistroAsistencia> : <RegistroAsistencia>[];
      final registros2 = results[2] is List ? results[2] as List<RegistroAsistencia> : <RegistroAsistencia>[];
      final comunicados = results[3] is List ? results[3] as List<Comunicado> : <Comunicado>[];
      final registros  = [...registros1, ...registros2];

      final Map<DateTime, List<_CalEvent>> events = {};

      // ── Proyectos y notas desde el calendario ─────────────────────
      if (calData != null) {
        for (final fechaStr in calData.diasConServicio) {
          final dt = DateTime.tryParse(fechaStr);
          if (dt == null) continue;
          (events[_dayKey(dt)] ??= []).add(_CalEvent(
            type:     _EventType.proyecto,
            title:    'Servicio programado',
            subtitle: 'Toca para ver detalle',
            color:    _orange,
          ));
        }
        for (final entry in calData.notas.entries) {
          final dt = DateTime.tryParse(entry.key);
          if (dt == null) continue;
          (events[_dayKey(dt)] ??= []).add(_CalEvent(
            type:     _EventType.nota,
            title:    entry.value,
            subtitle: 'Nota personal',
            color:    _violet,
          ));
        }
      }

      // ── Asistencia ────────────────────────────────────────────────
      final Map<DateTime, List<RegistroAsistencia>> byDay = {};
      for (final r in registros) {
        (byDay[_dayKey(r.timestamp)] ??= []).add(r);
      }
      for (final entry in byDay.entries) {
        final regs       = entry.value;
        final aprobados  = regs.where((r) => r.status == 'APROBADO');
        final tieneEntrada = aprobados.any((r) => r.tipo == 'ENTRADA');
        final tieneSalida  = aprobados.any((r) => r.tipo == 'SALIDA');
        final rechazado    = regs.any((r) => r.status == 'RECHAZADO');

        final Color dotColor;
        final String label;
        if (tieneEntrada && tieneSalida) {
          dotColor = _green;  label = 'Jornada completa';
        } else if (tieneEntrada) {
          dotColor = _orange; label = 'Solo entrada registrada';
        } else if (rechazado) {
          dotColor = Colors.red; label = 'Marcación rechazada';
        } else {
          dotColor = _orange; label = 'Asistencia parcial';
        }

        final tipos = aprobados.map((r) => _fmtTipo(r.tipo)).join(' · ');
        (events[entry.key] ??= []).add(_CalEvent(
          type:     _EventType.asistencia,
          title:    label,
          subtitle: tipos.isNotEmpty ? tipos : null,
          color:    dotColor,
        ));
      }

      // ── Comunicados ───────────────────────────────────────────────
      for (final c in comunicados) {
        if (c.fecha.isEmpty) continue;
        final dt = DateTime.tryParse(c.fecha);
        if (dt == null) continue;
        (events[_dayKey(dt)] ??= []).add(_CalEvent(
          type:     _EventType.comunicado,
          title:    c.titulo,
          subtitle: c.leido ? 'Leído' : 'Sin leer',
          color:    _blue,
        ));
      }

      setState(() {
        _events  = events;
        _calData = calData;
        _isLoading = false;
      });

      // Carga detalle del día seleccionado si tiene proyectos
      if (_selectedDay != null) _maybeLoadDetalle(_selectedDay!);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _events    = {};
        _calData   = null;
        _isLoading = false;
      });
    }
  }

  // ── Carga detalle de servicios del día ───────────────────────────────────
  void _maybeLoadDetalle(DateTime day) {
    final fechaStr = _toDateStr(day);
    if (_calData == null || !_calData!.diasConServicio.contains(fechaStr)) {
      setState(() => _detallesDia = []);
      return;
    }
    _loadDetalleDia(fechaStr);
  }

  Future<void> _loadDetalleDia(String fechaStr) async {
    setState(() { _loadDetalle = true; _detallesDia = []; });
    try {
      final svc    = await getDashboardService();
      final result = await svc.getDetalleServicioDia(fechaStr);
      if (!mounted) return;
      setState(() { _detallesDia = result; _loadDetalle = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _detallesDia = []; _loadDetalle = false; });
    }
  }

  // ── Selección de día ──────────────────────────────────────────────────────
  void _onDaySelected(DateTime selected, DateTime focused) {
    setState(() {
      _selectedDay = selected;
      _focusedDay  = focused;
      _detallesDia = [];
    });
    _maybeLoadDetalle(selected);
  }

  // ── Notas ─────────────────────────────────────────────────────────────────
  Future<void> _editarNota() async {
    if (_selectedDay == null) return;
    final fechaStr   = _toDateStr(_selectedDay!);
    final notaActual = _calData?.notas[fechaStr] ?? '';

    final ctrl = TextEditingController(text: notaActual);
    final resultado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ModalNota(ctrl: ctrl, isDark: Theme.of(context).brightness == Brightness.dark),
    );
    if (resultado == null || !mounted) return;

    setState(() => _savingNota = true);
    try {
      final svc = await getDashboardService();
      await svc.guardarNota(fechaStr, resultado);
      if (!mounted) return;

      // Actualiza estado local sin recargar todo
      final newNotas  = Map<String, String>.from(_calData?.notas ?? {});
      if (resultado.isEmpty) {
        newNotas.remove(fechaStr);
      } else {
        newNotas[fechaStr] = resultado;
      }

      final dt  = DateTime.tryParse(fechaStr);
      Map<DateTime, List<_CalEvent>> newEvents = Map.from(_events);
      if (dt != null) {
        final key     = _dayKey(dt);
        final sinNota = (_events[key] ?? []).where((e) => e.type != _EventType.nota).toList();
        if (resultado.isNotEmpty) {
          sinNota.add(_CalEvent(
            type: _EventType.nota, title: resultado,
            subtitle: 'Nota personal', color: _violet,
          ));
        }
        if (sinNota.isEmpty) {
          newEvents.remove(key);
        } else {
          newEvents[key] = sinNota;
        }
      }

      setState(() {
        _savingNota = false;
        _events     = newEvents;
        if (_calData != null) {
          _calData = CalendarioData(
            proximosEventos: _calData!.proximosEventos,
            notas:           newNotas,
            diasConServicio: _calData!.diasConServicio,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingNota = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al guardar nota: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  static String _fmtTipo(String tipo) => switch (tipo) {
    'ENTRADA'          => 'Entrada',
    'SALIDA'           => 'Salida',
    'ENTRADA_ALMUERZO' => 'Salida almuerzo',
    'SALIDA_ALMUERZO'  => 'Regreso almuerzo',
    _                  => tipo,
  };

  List<_CalEvent> _eventsFor(DateTime day) => _events[_dayKey(day)] ?? const [];

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final surface  = Theme.of(context).colorScheme.surface;
    final fechaStr = _selectedDay != null ? _toDateStr(_selectedDay!) : null;
    final nota     = fechaStr != null ? (_calData?.notas[fechaStr] ?? '') : '';
    final hasProyects = fechaStr != null &&
        (_calData?.diasConServicio.contains(fechaStr) ?? false);
    final otherEvents = (_selectedDay != null ? _eventsFor(_selectedDay!) : <_CalEvent>[])
        .where((e) => e.type != _EventType.proyecto && e.type != _EventType.nota)
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Calendario',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (_savingNota)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_violet),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            onPressed: _editarNota,
            color: _violet,
            tooltip: 'Agregar / editar nota',
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_green),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadAll,
              color: _green,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── TableCalendar ────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: surface,
              boxShadow: isDark
                  ? [BoxShadow(color: _green.withValues(alpha: 0.08), blurRadius: 12)]
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: TableCalendar<_CalEvent>(
              firstDay: DateTime(2024),
              lastDay: DateTime(2027),
              focusedDay: _focusedDay,
              calendarFormat: _format,
              locale: 'es_ES',
              selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
              eventLoader: _eventsFor,
              startingDayOfWeek: StartingDayOfWeek.monday,
              daysOfWeekHeight: 32,
              headerStyle: HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                formatButtonShowsNext: false,
                formatButtonDecoration: BoxDecoration(
                  color: _green,
                  borderRadius: BorderRadius.circular(12),
                ),
                formatButtonTextStyle: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                leftChevronIcon: Icon(Icons.chevron_left,
                    color: isDark ? Colors.white70 : Colors.black54),
                rightChevronIcon: Icon(Icons.chevron_right,
                    color: isDark ? Colors.white70 : Colors.black54),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                todayDecoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.18), shape: BoxShape.circle),
                selectedDecoration:
                    const BoxDecoration(color: _green, shape: BoxShape.circle),
                todayTextStyle:
                    const TextStyle(color: _green, fontWeight: FontWeight.bold),
                weekendTextStyle: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey.shade500),
                markersMaxCount: 4,
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (_, day, events) {
                  if (events.isEmpty) return null;
                  return Positioned(
                    bottom: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: events.take(4).map((e) => Container(
                        width: 5, height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                            color: e.color, shape: BoxShape.circle),
                      )).toList(),
                    ),
                  );
                },
              ),
              onDaySelected: _onDaySelected,
              onFormatChanged: (fmt) => setState(() => _format = fmt),
              onPageChanged: (focused) => setState(() => _focusedDay = focused),
            ),
          ),

          // ── Próximos eventos strip ────────────────────────────────
          if (_calData != null && _calData!.proximosEventos.isNotEmpty)
            _ProximosStrip(eventos: _calData!.proximosEventos, isDark: isDark),

          // ── Leyenda ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: Row(
              children: [
                _Dot(color: _green,  label: 'Asistencia'),
                const SizedBox(width: 12),
                _Dot(color: _orange, label: 'Proyecto'),
                const SizedBox(width: 12),
                _Dot(color: _violet, label: 'Nota'),
                const SizedBox(width: 12),
                _Dot(color: _blue,   label: 'Comunicado'),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Contenido del día seleccionado ────────────────────────
          Expanded(
            child: _buildDayContent(
              nota: nota,
              hasProyects: hasProyects,
              otherEvents: otherEvents,
              isDark: isDark,
              surface: surface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayContent({
    required String nota,
    required bool hasProyects,
    required List<_CalEvent> otherEvents,
    required bool isDark,
    required Color surface,
  }) {
    final anyContent = nota.isNotEmpty || hasProyects || otherEvents.isNotEmpty;

    if (!anyContent) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 10),
            const Text('Sin eventos este día',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView(
      padding: bottomSafePadding(context, left: 20, top: 14, right: 20, extra: 24),
      children: [
        // Nota del día
        if (nota.isNotEmpty) ...[
          _NotaCard(nota: nota, isDark: isDark, surface: surface, onEdit: _editarNota),
          const SizedBox(height: 8),
        ],

        // Proyectos del día
        if (hasProyects)
          if (_loadDetalle)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_orange),
                ),
              ),
            )
          else
            ..._detallesDia.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ProyectoCard(detalle: d, isDark: isDark, surface: surface),
            )),

        // Asistencia y comunicados
        ...otherEvents.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _EventCard(event: e, isDark: isDark, surface: surface),
        )),
      ],
    );
  }
}

// ─── Modal de nota ────────────────────────────────────────────────────────────

class _ModalNota extends StatelessWidget {
  final TextEditingController ctrl;
  final bool isDark;
  const _ModalNota({required this.ctrl, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF8B5CF6);
    final bg = isDark ? const Color(0xFF1C1F2E) : Colors.white;
    final border = isDark ? violet.withValues(alpha: 0.35) : Colors.grey.shade300;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Nota del día',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Escribe una nota para este día...',
                filled: true,
                fillColor: isDark ? const Color(0xFF0F1117) : Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: violet, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: border),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, ''),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Eliminar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: violet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Guardar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Strip de próximos eventos ────────────────────────────────────────────────

class _ProximosStrip extends StatelessWidget {
  final List<EventoProximo> eventos;
  final bool isDark;
  const _ProximosStrip({required this.eventos, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      color: surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          const Text('Próximos',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey)),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: eventos.map((e) => _EventoChip(evento: e, isDark: isDark)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventoChip extends StatelessWidget {
  final EventoProximo evento;
  final bool isDark;
  const _EventoChip({required this.evento, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF59E0B);
    const green  = Color(0xFF8FD11B);
    final color  = evento.activo ? green : orange;

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.25 : 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(evento.dia,
                    style: TextStyle(
                        color: color, fontSize: 11, fontWeight: FontWeight.bold,
                        height: 1.1)),
                Text(evento.mes,
                    style: TextStyle(
                        color: color, fontSize: 8, fontWeight: FontWeight.w600,
                        height: 1.1)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                evento.empresa.length > 18
                    ? '${evento.empresa.substring(0, 16)}…'
                    : evento.empresa,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Text(evento.tipo,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Tarjeta de nota ──────────────────────────────────────────────────────────

class _NotaCard extends StatelessWidget {
  final String nota;
  final bool isDark;
  final Color surface;
  final VoidCallback onEdit;
  const _NotaCard({
    required this.nota,
    required this.isDark,
    required this.surface,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    const violet = Color(0xFF8B5CF6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: const BorderSide(color: violet, width: 3.5)),
        boxShadow: isDark
            ? [BoxShadow(color: violet.withValues(alpha: 0.08), blurRadius: 8)]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: violet.withValues(alpha: isDark ? 0.15 : 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.sticky_note_2_outlined, color: violet, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nota personal',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13, color: violet)),
                const SizedBox(height: 3),
                Text(nota,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          GestureDetector(
            onTap: onEdit,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tarjeta de proyecto del día ──────────────────────────────────────────────

class _ProyectoCard extends StatelessWidget {
  final DetalleServicioDia detalle;
  final bool isDark;
  final Color surface;
  const _ProyectoCard({
    required this.detalle,
    required this.isDark,
    required this.surface,
  });

  Color get _estadoColor => switch (detalle.estado) {
    'Completado' => const Color(0xFF8FD11B),
    'En Proceso' => const Color(0xFF3B82F6),
    'Cancelado'  => Colors.red,
    _            => const Color(0xFFF59E0B),
  };

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFF59E0B);
    final statusColor = _estadoColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: const BorderSide(color: orange, width: 3.5)),
        boxShadow: isDark
            ? [BoxShadow(color: orange.withValues(alpha: 0.08), blurRadius: 8)]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Encabezado ───────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.work_outline, color: orange, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detalle.nombre,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (detalle.ordenTrabajo.isNotEmpty)
                      Text(detalle.ordenTrabajo,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(detalle.estado,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Info cliente / servicio ───────────────────────────────
          Row(
            children: [
              const Icon(Icons.business_outlined, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(detalle.cliente,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.build_outlined, size: 12, color: Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                child: Text(detalle.servicio,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),

          // ── Jefe de operaciones ───────────────────────────────────
          if (detalle.jefe != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 12, color: Colors.grey),
                const SizedBox(width: 4),
                Text('${detalle.jefe!.nombre} · ${detalle.jefe!.cargo}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],

          // ── Equipo ────────────────────────────────────────────────
          if (detalle.equipo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: detalle.equipo.map((m) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(m.nombre,
                    style: const TextStyle(fontSize: 11)),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Tarjeta genérica de evento (asistencia / comunicado) ─────────────────────

class _EventCard extends StatelessWidget {
  final _CalEvent event;
  final bool isDark;
  final Color surface;
  const _EventCard({
    required this.event,
    required this.isDark,
    required this.surface,
  });

  IconData get _icon => switch (event.type) {
    _EventType.asistencia => Icons.fingerprint,
    _EventType.proyecto   => Icons.work_outline,
    _EventType.comunicado => Icons.campaign_outlined,
    _EventType.nota       => Icons.sticky_note_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: event.color, width: 3.5)),
        boxShadow: isDark
            ? [BoxShadow(color: event.color.withValues(alpha: 0.08), blurRadius: 8)]
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: isDark ? 0.15 : 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_icon, color: event.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (event.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(event.subtitle!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dot de leyenda ───────────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}
