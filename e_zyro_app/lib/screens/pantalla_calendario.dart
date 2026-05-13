import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/asistencia_models.dart';
import '../models/comunicado_models.dart';
import '../models/proyecto_models.dart';
import '../utils/api_provider.dart';

// ── Tipos de evento ───────────────────────────────────────────────────────────
enum _EventType { asistencia, proyecto, comunicado }

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

// Normaliza a medianoche local para que el Map<DateTime,…> funcione correctamente
DateTime _dayKey(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

// ── Pantalla principal ────────────────────────────────────────────────────────
class CalendarioScreen extends StatefulWidget {
  const CalendarioScreen({super.key});

  @override
  State<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends State<CalendarioScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _format = CalendarFormat.month;

  Map<DateTime, List<_CalEvent>> _events = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dayKey(DateTime.now());
    _loadAll();
  }

  // ── Carga de datos ────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    try {
      final asistSvc = await getAsistenciaService();
      final proySvc = await getProyectoService();
      final comSvc = await getComunicadoService();

      final results = await Future.wait(
        [
          asistSvc.getHistorial(pagina: 1),
          asistSvc.getHistorial(pagina: 2),
          proySvc.getMisServicios(),
          comSvc.getComunicados(),
        ],
        eagerError: false,
      ).then((values) => values.map((v) => v is Exception ? [] : v).toList());

      if (!mounted) return;

      final registros = [
        ...(results.isNotEmpty ? results[0] as List<RegistroAsistencia> : []),
        ...(results.length > 1 ? results[1] as List<RegistroAsistencia> : []),
      ];
      final proyectos = results.length > 2
          ? results[2] as List<ProyectoServicio>
          : [];
      final comunicados = results.length > 3
          ? results[3] as List<Comunicado>
          : [];

      final Map<DateTime, List<_CalEvent>> events = {};

      // ── Asistencia ──────────────────────────────────────────────────
      final Map<DateTime, List<RegistroAsistencia>> byDay = {};
      for (final r in registros) {
        (byDay[_dayKey(r.timestamp)] ??= []).add(r);
      }

      for (final entry in byDay.entries) {
        final regs = entry.value;
        final aprobados = regs.where((r) => r.status == 'APROBADO');
        final tieneEntrada = aprobados.any((r) => r.tipo == 'ENTRADA');
        final tieneSalida = aprobados.any((r) => r.tipo == 'SALIDA');
        final rechazado = regs.any((r) => r.status == 'RECHAZADO');

        final Color dotColor;
        final String label;

        if (tieneEntrada && tieneSalida) {
          dotColor = const Color(0xFF8FD11B);
          label = 'Jornada completa';
        } else if (tieneEntrada) {
          dotColor = const Color(0xFFF59E0B);
          label = 'Solo entrada registrada';
        } else if (rechazado) {
          dotColor = Colors.red;
          label = 'Marcación rechazada';
        } else {
          dotColor = const Color(0xFFF59E0B);
          label = 'Asistencia parcial';
        }

        final tipos = aprobados.map((r) => _formatTipo(r.tipo)).join(' · ');

        (events[entry.key] ??= []).add(
          _CalEvent(
            type: _EventType.asistencia,
            title: label,
            subtitle: tipos.isNotEmpty ? tipos : null,
            color: dotColor,
          ),
        );
      }

      // ── Proyectos ────────────────────────────────────────────────────
      for (final p in proyectos) {
        final label = '${p.empresa} — ${p.tipoServicio}';
        if (p.fechaInicio != null) {
          final dt = DateTime.tryParse(p.fechaInicio!);
          if (dt != null) {
            (events[_dayKey(dt)] ??= []).add(
              _CalEvent(
                type: _EventType.proyecto,
                title: label,
                subtitle: 'Inicio del servicio',
                color: const Color(0xFFF59E0B),
              ),
            );
          }
        }
        if (p.fechaFin != null) {
          final dt = DateTime.tryParse(p.fechaFin!);
          if (dt != null) {
            (events[_dayKey(dt)] ??= []).add(
              _CalEvent(
                type: _EventType.proyecto,
                title: label,
                subtitle: 'Plazo del servicio',
                color: Colors.deepOrange,
              ),
            );
          }
        }
      }

      // ── Comunicados ──────────────────────────────────────────────────
      for (final c in comunicados) {
        if (c.fecha.isEmpty) continue;
        final dt = DateTime.tryParse(c.fecha);
        if (dt == null) continue;
        (events[_dayKey(dt)] ??= []).add(
          _CalEvent(
            type: _EventType.comunicado,
            title: c.titulo,
            subtitle: c.leido ? 'Leído' : 'Sin leer',
            color: Colors.blue.shade600,
          ),
        );
      }

      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _events = {};
        _isLoading = false;
      });
    }
  }

  static String _formatTipo(String tipo) => switch (tipo) {
    'ENTRADA' => 'Entrada',
    'SALIDA' => 'Salida',
    'ENTRADA_ALMUERZO' => 'Salida almuerzo',
    'SALIDA_ALMUERZO' => 'Regreso almuerzo',
    _ => tipo,
  };

  List<_CalEvent> _eventsFor(DateTime day) => _events[_dayKey(day)] ?? const [];

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8FD11B);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final selected = _selectedDay != null
        ? _eventsFor(_selectedDay!)
        : <_CalEvent>[];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text(
          'Calendario',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(green),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadAll,
              color: green,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Widget de calendario ────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: surface,
              boxShadow: isDark
                  ? [
                      BoxShadow(
                        color: green.withValues(alpha: 0.08),
                        blurRadius: 12,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
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
                  color: green,
                  borderRadius: BorderRadius.circular(12),
                ),
                formatButtonTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                leftChevronIcon: Icon(
                  Icons.chevron_left,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                todayDecoration: BoxDecoration(
                  color: green.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: green,
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: green,
                  fontWeight: FontWeight.bold,
                ),
                weekendTextStyle: TextStyle(
                  color: isDark ? Colors.white54 : Colors.grey.shade500,
                ),
                markersMaxCount: 3,
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (_, day, events) {
                  if (events.isEmpty) return null;
                  return Positioned(
                    bottom: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: events
                          .take(3)
                          .map(
                            (e) => Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: e.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
              onDaySelected: (selected, focused) => setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              }),
              onFormatChanged: (fmt) => setState(() => _format = fmt),
              onPageChanged: (focused) => setState(() => _focusedDay = focused),
            ),
          ),

          // ── Leyenda ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
            child: Row(
              children: [
                _Dot(color: green, label: 'Asistencia'),
                const SizedBox(width: 16),
                _Dot(color: const Color(0xFFF59E0B), label: 'Proyecto'),
                const SizedBox(width: 16),
                _Dot(color: Colors.blue.shade600, label: 'Comunicado'),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Lista de eventos ─────────────────────────────────────────
          Expanded(
            child: selected.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_note_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Sin eventos este día',
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                    itemCount: selected.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _EventCard(
                      event: selected[i],
                      isDark: isDark,
                      surface: surface,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets pequeños ─────────────────────────────────────────────────────────

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
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

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
    _EventType.proyecto => Icons.work_outline,
    _EventType.comunicado => Icons.campaign_outlined,
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
            ? [
                BoxShadow(
                  color: event.color.withValues(alpha: 0.08),
                  blurRadius: 8,
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
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
                Text(
                  event.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (event.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    event.subtitle!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
