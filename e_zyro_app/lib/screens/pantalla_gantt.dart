import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';

// ── Layout constants ──────────────────────────────────────────────────────────
const double _kLabelW = 150.0;
const double _kRowH = 46.0;
const double _kProcH = 36.0;
const double _kHeaderH = 44.0;
const double _kBarH = 14.0;
const double _kDayW = 28.0;

// ── Row data model ────────────────────────────────────────────────────────────
enum _RowType { project, service, procedure }

class _GRow {
  final _RowType type;
  final String id;
  final String name;
  final String estado;
  final String? subtitle;
  final DateTime? dateStart;
  final DateTime? dateEnd;

  const _GRow({
    required this.type,
    required this.id,
    required this.name,
    required this.estado,
    this.subtitle,
    this.dateStart,
    this.dateEnd,
  });

  double get h => type == _RowType.procedure ? _kProcH : _kRowH;
}

// ── Screen ────────────────────────────────────────────────────────────────────
class GanttScreen extends StatefulWidget {
  final ProyectoItem proyecto;
  final ProyectoService service;

  const GanttScreen({
    super.key,
    required this.proyecto,
    required this.service,
  });

  @override
  State<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends State<GanttScreen> {
  List<ServicioItem> _servicios = [];
  // Tareas del cronograma por servicio (los procedimientos son pasos fijos
  // sin fechas planificadas: no van en el Gantt).
  final Map<String, List<TareaDetalle>> _procs = {};
  final Set<String> _expanded = {};
  final Set<String> _loadingProcs = {};
  bool _isLoading = true;

  late ScrollController _hHeaderCtrl;
  late ScrollController _hBarsCtrl;
  bool _syncingH = false;

  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  int get _totalDays => _rangeEnd.difference(_rangeStart).inDays + 1;
  double get _totalW => _totalDays * _kDayW;
  double get _todayX =>
      DateTime.now().difference(_rangeStart).inDays * _kDayW;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _computeRange(const []);
    _hHeaderCtrl = ScrollController();
    _hBarsCtrl = ScrollController();
    _hBarsCtrl.addListener(_onBarsScroll);
    _load();
  }

  @override
  void dispose() {
    _hBarsCtrl.removeListener(_onBarsScroll);
    _hHeaderCtrl.dispose();
    _hBarsCtrl.dispose();
    super.dispose();
  }

  void _onBarsScroll() {
    if (_syncingH) return;
    _syncingH = true;
    if (_hHeaderCtrl.hasClients) {
      final max = _hHeaderCtrl.position.maxScrollExtent;
      _hHeaderCtrl.jumpTo(_hBarsCtrl.offset.clamp(0.0, max));
    }
    _syncingH = false;
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final svcs = await widget.service.getServiciosProyecto(widget.proyecto.id);
    if (!mounted) return;
    _computeRange(svcs);
    setState(() {
      _servicios = svcs;
      _isLoading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  void _computeRange(List<ServicioItem> svcs) {
    final today = DateTime.now();
    DateTime? mn = _parseDate(widget.proyecto.fechaInicio);
    DateTime? mx = _parseDate(widget.proyecto.fechaFinEstimada);

    for (final s in svcs) {
      final sd = _parseDate(s.fechaInicio ?? s.fechaProgramada);
      final ed = _parseDate(s.fechaFin ?? s.fechaProgramada);
      if (sd != null && (mn == null || sd.isBefore(mn))) mn = sd;
      if (ed != null && (mx == null || ed.isAfter(mx))) mx = ed;
    }

    _rangeStart =
        (mn ?? today.subtract(const Duration(days: 14)))
            .subtract(const Duration(days: 7));
    _rangeEnd =
        (mx ?? today.add(const Duration(days: 76)))
            .add(const Duration(days: 14));

    if (_rangeEnd.difference(_rangeStart).inDays < 90) {
      _rangeEnd = _rangeStart.add(const Duration(days: 90));
    }
  }

  void _scrollToToday() {
    if (!_hBarsCtrl.hasClients) return;
    final target =
        (_todayX - 80).clamp(0.0, _hBarsCtrl.position.maxScrollExtent);
    _hBarsCtrl.jumpTo(target);
  }

  Future<void> _toggleService(String id) async {
    if (_expanded.contains(id)) {
      setState(() => _expanded.remove(id));
      return;
    }
    if (!_procs.containsKey(id)) {
      setState(() => _loadingProcs.add(id));
      final detail = await widget.service.getDetalleServicio(id);
      if (!mounted) return;
      _procs[id] = detail?.tareas ?? [];
      _loadingProcs.remove(id);
    }
    setState(() => _expanded.add(id));
  }

  // ── Row list ────────────────────────────────────────────────────────────────

  List<_GRow> get _rows {
    final p = widget.proyecto;
    final list = <_GRow>[
      _GRow(
        type: _RowType.project,
        id: p.id,
        name: p.nombreProyecto,
        estado: p.estado,
        subtitle: '${p.cliente} · ${p.ordenTrabajo}',
        dateStart: _parseDate(p.fechaInicio),
        dateEnd: _parseDate(p.fechaFinEstimada),
      ),
    ];

    for (final s in _servicios) {
      final sd = _parseDate(s.fechaInicio ?? s.fechaProgramada);
      final ed = _parseDate(s.fechaFin ?? s.fechaProgramada);
      list.add(_GRow(
        type: _RowType.service,
        id: s.id,
        name: s.nombre,
        estado: s.estado,
        dateStart: sd,
        dateEnd: ed != null && sd != null && !ed.isBefore(sd)
            ? ed
            : sd?.add(const Duration(days: 1)),
      ));
      if (_expanded.contains(s.id)) {
        for (final proc in (_procs[s.id] ?? [])) {
          // Usa las fechas reales de la tarea (asignación). Si falta el inicio,
          // cae al del servicio para no perder su lugar en la línea de tiempo.
          final pStart = _parseDate(proc.fechaInicioTarea) ?? sd;
          final pEnd = _parseDate(proc.fechaLimite);
          list.add(_GRow(
            type: _RowType.procedure,
            id: proc.id,
            name: proc.nombre,
            estado: proc.estado,
            dateStart: pStart,
            dateEnd: pEnd,
          ));
        }
      }
    }
    return list;
  }

  // ── Bar helpers ─────────────────────────────────────────────────────────────

  double _barLeft(DateTime? start) {
    if (start == null) return 0;
    return start.difference(_rangeStart).inDays.clamp(0, _totalDays) * _kDayW;
  }

  double _barWidth(DateTime? start, DateTime? end, _RowType type) {
    final s = start ?? _rangeStart;
    final e = end ?? s.add(const Duration(days: 1));
    final days = e.difference(s).inDays.clamp(1, _totalDays);
    final minW = type == _RowType.procedure ? 8.0 : 20.0;
    return (days * _kDayW).clamp(minW, _totalW);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0F1A08) : const Color(0xFFF3F8EE),
      appBar: _buildAppBar(context),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
              ),
            )
          : Column(
              children: [
                _buildStats(context, isDark),
                const SizedBox(height: 8),
                Expanded(child: _buildGanttTable(context, isDark)),
                _buildLegend(context, isDark),
              ],
            ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      toolbarHeight: 68,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF8FD11B).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              '◆  DIAGRAMA DE GANTT',
              style: TextStyle(
                fontSize: 9,
                letterSpacing: 1.0,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8FD11B),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            widget.proyecto.nombreProyecto,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${widget.proyecto.cliente} · ${widget.proyecto.ordenTrabajo}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Exportar Gantt (PDF)',
          icon: const Icon(Icons.picture_as_pdf_outlined),
          onPressed: _servicios.isEmpty ? null : _exportarGanttPdf,
        ),
      ],
    );
  }

  Future<void> _exportarGanttPdf() async {
    final bytes = await PdfService.gantt(widget.proyecto, _servicios);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: 'gantt_${widget.proyecto.ordenTrabajo}.pdf',
      titulo: 'Cronograma Gantt',
    );
  }

  Widget _buildStats(BuildContext context, bool isDark) {
    final p = widget.proyecto;
    final surface = Theme.of(context).colorScheme.surface;
    final pct = (p.progreso * 100).round();
    final pctColor =
        pct >= 100 ? const Color(0xFF8FD11B) : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark
            ? Border.all(
                color:
                    const Color(0xFF8FD11B).withValues(alpha: 0.22))
            : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8)
              ],
      ),
      child: Row(
        children: [
          _StatPill(label: 'SERVICIOS', value: '${p.totalServicios}'),
          _vDivider(),
          _StatPill(
              label: 'COMPLETADOS',
              value: '${p.serviciosCompletados}'),
          _vDivider(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$pct%',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: pctColor),
                ),
                const Text('PROGRESO',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey,
                        letterSpacing: 0.6)),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: p.progreso,
                    minHeight: 4,
                    backgroundColor: isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade200,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(pctColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        height: 36,
        width: 1,
        color: Colors.grey.withValues(alpha: 0.25),
        margin: const EdgeInsets.symmetric(horizontal: 14),
      );

  Widget _buildGanttTable(BuildContext context, bool isDark) {
    final surface = Theme.of(context).colorScheme.surface;
    final border = isDark
        ? Colors.grey.withValues(alpha: 0.18)
        : Colors.grey.withValues(alpha: 0.22);
    final rows = _rows;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10)
              ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          // ── Column headers ───────────────────────────────────────────────
          SizedBox(
            height: _kHeaderH,
            child: Row(
              children: [
                // Activity label header
                SizedBox(
                  width: _kLabelW,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.grey.withValues(alpha: 0.04),
                      border: Border(
                        right: BorderSide(color: border),
                        bottom: BorderSide(color: border),
                      ),
                    ),
                    child: const Text(
                      'ACTIVIDADES',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                ),
                // Timeline month headers
                Expanded(
                  child: SingleChildScrollView(
                    controller: _hHeaderCtrl,
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: SizedBox(
                      width: _totalW,
                      height: _kHeaderH,
                      child: _buildMonthHeaders(isDark, border),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Scrollable body ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: activity names (fixed width)
                  SizedBox(
                    width: _kLabelW,
                    child: _buildLabelColumn(rows, isDark, border),
                  ),
                  // Right: timeline bars (scrolls horizontally)
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _hBarsCtrl,
                      scrollDirection: Axis.horizontal,
                      child: _buildBarsArea(rows, isDark, border),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Month headers ──────────────────────────────────────────────────────────

  Widget _buildMonthHeaders(bool isDark, Color border) {
    final segments = <(DateTime, int)>[];
    var cur = DateTime(_rangeStart.year, _rangeStart.month, 1);

    while (cur.isBefore(_rangeEnd)) {
      final next = DateTime(cur.year, cur.month + 1, 1);
      final segStart = cur.isBefore(_rangeStart) ? _rangeStart : cur;
      final segEnd = next.isAfter(_rangeEnd) ? _rangeEnd : next;
      final days = segEnd.difference(segStart).inDays;
      if (days > 0) segments.add((segStart, days));
      cur = next;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: segments.map((seg) {
        final (dt, days) = seg;
        final label =
            DateFormat('MMM. yy', 'es_ES').format(dt).toUpperCase();
        return Container(
          width: days * _kDayW,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.grey.withValues(alpha: 0.04),
            border: Border(
              right: BorderSide(color: border),
              bottom: BorderSide(color: border),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color:
                  isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Label column ──────────────────────────────────────────────────────────

  Widget _buildLabelColumn(
      List<_GRow> rows, bool isDark, Color border) {
    return Column(
      children: rows.map((r) => _buildLabelRow(r, isDark, border)).toList(),
    );
  }

  Widget _buildLabelRow(_GRow row, bool isDark, Color border) {
    final isService = row.type == _RowType.service;
    final isLoading = _loadingProcs.contains(row.id);
    final isExpanded = _expanded.contains(row.id);
    final barColor = _colorForEstado(row.estado);

    double indent = switch (row.type) {
      _RowType.project => 8.0,
      _RowType.service => 14.0,
      _RowType.procedure => 22.0,
    };

    return GestureDetector(
      onTap: isService ? () => _toggleService(row.id) : null,
      child: Container(
        height: row.h,
        decoration: BoxDecoration(
          color: row.type == _RowType.project
              ? const Color(0xFF8FD11B).withValues(alpha: isDark ? 0.10 : 0.06)
              : Colors.transparent,
          border: Border(
            right: BorderSide(color: border),
            bottom: BorderSide(color: border),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: indent, right: 6),
          child: Row(
            children: [
              // Icon / indicator
              SizedBox(
                width: 18,
                child: switch (row.type) {
                  _RowType.project => Icon(
                      Icons.folder_outlined,
                      size: 13,
                      color: const Color(0xFF8FD11B),
                    ),
                  _RowType.service => isLoading
                      ? SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(barColor),
                          ),
                        )
                      : Icon(
                          isExpanded
                              ? Icons.expand_less
                              : Icons.chevron_right,
                          size: 14,
                          color: barColor,
                        ),
                  _RowType.procedure => Icon(
                      row.estado.toLowerCase().contains('complet')
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 12,
                      color: barColor,
                    ),
                },
              ),
              const SizedBox(width: 2),
              // Name
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.name,
                      style: TextStyle(
                        fontSize:
                            row.type == _RowType.project ? 12 : 11,
                        height: 1.1,
                        fontWeight: row.type == _RowType.project
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                      maxLines: row.subtitle != null ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (row.subtitle != null)
                      Text(
                        row.subtitle!,
                        style: const TextStyle(
                            fontSize: 9, height: 1.1, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bars area ──────────────────────────────────────────────────────────────

  Widget _buildBarsArea(
      List<_GRow> rows, bool isDark, Color border) {
    final totalH = rows.fold(0.0, (s, r) => s + r.h);
    final tx = _todayX;
    final showToday = tx >= 0 && tx <= _totalW;

    return SizedBox(
      width: _totalW,
      height: totalH,
      child: Stack(
        children: [
          // Monthly grid
          CustomPaint(
            size: Size(_totalW, totalH),
            painter: _GridPainter(
              rangeStart: _rangeStart,
              rangeEnd: _rangeEnd,
              dayWidth: _kDayW,
              color: border,
            ),
          ),

          // Bar rows
          Column(
            children:
                rows.map((r) => _buildBarRow(r, isDark, border)).toList(),
          ),

          // Today line
          if (showToday) ...[
            Positioned(
              left: tx,
              top: 0,
              width: 1.5,
              height: totalH,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.75),
                ),
              ),
            ),
            Positioned(
              left: (tx - 16).clamp(0.0, _totalW - 32),
              top: 2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'Hoy',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBarRow(_GRow row, bool isDark, Color border) {
    final barColor = _colorForEstado(row.estado);
    final isProc = row.type == _RowType.procedure;

    return Container(
      height: row.h,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
        color: row.type == _RowType.project
            ? const Color(0xFF8FD11B).withValues(alpha: isDark ? 0.06 : 0.04)
            : Colors.transparent,
      ),
      child: row.dateStart == null
          // No date: dot at start
          ? Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: barColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            )
          // Has date: positioned bar
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: _barLeft(row.dateStart),
                  top: (row.h - (isProc ? 8 : _kBarH)) / 2,
                  child: Container(
                    width: _barWidth(
                        row.dateStart, row.dateEnd, row.type),
                    height: isProc ? 8 : _kBarH,
                    decoration: BoxDecoration(
                      color: barColor.withValues(
                          alpha: isProc
                              ? 0.45
                              : (isDark ? 0.60 : 0.50)),
                      borderRadius: BorderRadius.circular(isProc ? 4 : 5),
                      border: Border.all(
                        color: barColor.withValues(
                            alpha: isDark ? 0.85 : 0.70),
                        width: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ── Legend ─────────────────────────────────────────────────────────────────

  Widget _buildLegend(BuildContext context, bool isDark) {
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: isDark
            ? Border.all(
                color: const Color(0xFF8FD11B).withValues(alpha: 0.15))
            : null,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _LegendItem(
                color: Color(0xFF8FD11B), label: 'Proyecto / Completado'),
            SizedBox(width: 14),
            _LegendItem(color: Color(0xFFF59E0B), label: 'Pendiente'),
            SizedBox(width: 14),
            _LegendItem(color: Color(0xFF3B82F6), label: 'En Proceso'),
            SizedBox(width: 14),
            _LegendItem(color: Colors.red, label: 'Hoy', isLine: true),
          ],
        ),
      ),
    );
  }
}

// ── Grid painter ──────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final double dayWidth;
  final Color color;

  const _GridPainter({
    required this.rangeStart,
    required this.rangeEnd,
    required this.dayWidth,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    var cur = DateTime(rangeStart.year, rangeStart.month + 1, 1);
    while (cur.isBefore(rangeEnd)) {
      final x = cur.difference(rangeStart).inDays * dayWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      cur = DateTime(cur.year, cur.month + 1, 1);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.rangeStart != rangeStart || old.rangeEnd != rangeEnd;
}

// ── Stat pill ─────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: const TextStyle(
                fontSize: 9, color: Colors.grey, letterSpacing: 0.6),
          ),
        ],
      );
}

// ── Legend item ───────────────────────────────────────────────────────────────

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool isLine;

  const _LegendItem({
    required this.color,
    required this.label,
    this.isLine = false,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLine)
            Container(
                width: 14,
                height: 2,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1),
                ))
          else
            Container(
              width: 14,
              height: 10,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                    color: color.withValues(alpha: 0.85), width: 0.5),
              ),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _colorForEstado(String estado) => switch (estado.toLowerCase()) {
      'completado' || 'completed' => const Color(0xFF8FD11B),
      'en_proceso' || 'en proceso' => const Color(0xFF3B82F6),
      'cancelado' || 'canceled' => Colors.red,
      _ => const Color(0xFFF59E0B),
    };

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  // ISO (yyyy-MM-dd)
  try {
    return DateTime.parse(s);
  } catch (_) {}
  // dd/MM/yyyy
  try {
    final parts = s.split('/');
    if (parts.length == 3) {
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
      );
    }
  } catch (_) {}
  // "dd Mon yyyy" (ej. "15 Nov 2025" / "15 nov. 2025") — formato legible ES/EN
  try {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.length == 3) {
      final day = int.parse(parts[0]);
      final mon = _monthFromName(parts[1]);
      final year = int.parse(parts[2]);
      if (mon != null) return DateTime(year, mon, day);
    }
  } catch (_) {}
  return null;
}

int? _monthFromName(String name) {
  final n = name.toLowerCase().replaceAll('.', '');
  if (n.length < 3) return null;
  const months = {
    'jan': 1, 'ene': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4, 'abr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8, 'ago': 8,
    'sep': 9, 'set': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12, 'dic': 12,
  };
  return months[n.substring(0, 3)];
}
