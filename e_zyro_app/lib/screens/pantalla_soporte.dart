import 'package:flutter/material.dart';
import '../models/soporte_models.dart';
import '../services/soporte_service.dart';
import '../utils/api_provider.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';

const _kIndigo = Color(0xFF6366F1);
const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFEF4444);
const _kAmber = Color(0xFFF59E0B);
const _kBlue = Color(0xFF3B82F6);
const _kGray = Color(0xFF6B7280);

/// Soporte TI — el colaborador reporta problemáticas (errores de la app, del
/// sistema, accesos, datos) y hace seguimiento. El equipo de TI (admin) ve
/// todos los tickets y los gestiona.
class PantallaSoporte extends StatefulWidget {
  const PantallaSoporte({super.key});

  @override
  State<PantallaSoporte> createState() => _PantallaSoporteState();
}

class _PantallaSoporteState extends State<PantallaSoporte> {
  SoporteService? _service;
  List<TicketSoporte> _tickets = [];
  bool _loading = true;
  bool _esTi = false;
  String _alcance = 'mios'; // mios | todos

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await AppSession.load();
    _esTi = AppSession.i.isAdmin;
    _service = await getSoporteService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() => _loading = true);
    final data = await _service!.getTickets(alcance: _alcance);
    if (!mounted) return;
    setState(() {
      _tickets = data;
      _loading = false;
    });
  }

  void _msg(String t, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(t, style: const TextStyle(color: Colors.white)),
      backgroundColor: c,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _nuevoTicket() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NuevoTicketSheet(service: _service!),
    );
    if (ok == true) {
      _msg('Reporte enviado al equipo de TI', _kGreen);
      await _load();
    }
  }

  Future<void> _abrirDetalle(TicketSoporte t) async {
    final cambio = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetalleTicketSheet(
        ticket: t,
        esTi: _esTi,
        service: _service!,
      ),
    );
    if (cambio == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: const BackButton(),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _kIndigo.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_rounded,
                  size: 18, color: _kIndigo),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Soporte TI',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Reporta un problema',
                    style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _service == null ? null : _nuevoTicket,
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Reportar problema',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: TopoBackground(
        c1: isDark ? const Color(0xFF1E1B4B) : const Color(0xFF3730A3),
        c2: isDark ? const Color(0xFF3730A3) : const Color(0xFF6366F1),
        base: isDark ? const Color(0xFF0B0B14) : const Color(0xFFF5F5FF),
        count: 14,
        amp: 8,
        stroke: 0.35,
        speed: 0.4,
        child: Column(
          children: [
            // Selector de alcance (solo TI)
            if (_esTi)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _alcanceChip('Mis reportes', 'mios'),
                    const SizedBox(width: 8),
                    _alcanceChip('Todos (TI)', 'todos'),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _kIndigo))
                  : _tickets.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _kIndigo,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                            itemCount: _tickets.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _TicketCard(
                              ticket: _tickets[i],
                              mostrarReportante: _esTi && _alcance == 'todos',
                              onTap: () => _abrirDetalle(_tickets[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alcanceChip(String label, String value) {
    final sel = _alcance == value;
    return GestureDetector(
      onTap: () {
        setState(() => _alcance = value);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? _kIndigo : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? _kIndigo : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface)),
      ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _kIndigo.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent_rounded,
                  size: 40, color: _kIndigo),
            ),
            const SizedBox(height: 16),
            const Text('Sin reportes',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              '¿Algo no funciona? Toca "Reportar problema"\ny el equipo de TI lo revisará.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
}

// ── Helpers de presentación ─────────────────────────────────────────────────

({Color color, String label}) _estadoCfg(String e) => switch (e) {
      'abierto' => (color: _kAmber, label: 'Abierto'),
      'en_proceso' => (color: _kBlue, label: 'En proceso'),
      'resuelto' => (color: _kGreen, label: 'Resuelto'),
      'cerrado' => (color: _kGray, label: 'Cerrado'),
      _ => (color: _kGray, label: e),
    };

({Color color, String label}) _prioridadCfg(String p) => switch (p) {
      'urgente' => (color: _kRed, label: 'Urgente'),
      'alta' => (color: _kAmber, label: 'Alta'),
      'media' => (color: _kBlue, label: 'Media'),
      'baja' => (color: _kGray, label: 'Baja'),
      _ => (color: _kGray, label: p),
    };

String _fechaCorta(String iso) {
  if (iso.isEmpty) return '';
  final d = DateTime.tryParse(iso);
  if (d == null) return '';
  final l = d.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.day)}/${dos(l.month)}/${l.year % 100} ${dos(l.hour)}:${dos(l.minute)}';
}

// ── Card de ticket ──────────────────────────────────────────────────────────

class _TicketCard extends StatelessWidget {
  final TicketSoporte ticket;
  final bool mostrarReportante;
  final VoidCallback onTap;

  const _TicketCard({
    required this.ticket,
    required this.mostrarReportante,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final est = _estadoCfg(ticket.estado);
    final pri = _prioridadCfg(ticket.prioridad);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: est.color, width: 4)),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(ticket.codigo,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _kIndigo)),
                const SizedBox(width: 8),
                _pill(est.label, est.color),
                const SizedBox(width: 6),
                _pill(pri.label, pri.color),
                const Spacer(),
                Text(_fechaCorta(ticket.creadoEn),
                    style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Text(ticket.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(ticket.descripcion,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.4)),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.label_outline, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(kCategoriasSoporte[ticket.categoria] ?? ticket.categoria,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                if (mostrarReportante) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.person_outline, size: 13, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(ticket.reportanteNombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ),
                ],
                const Spacer(),
                if (ticket.respuestaTi != null && ticket.respuestaTi!.isNotEmpty)
                  const Icon(Icons.mark_chat_read_outlined,
                      size: 15, color: _kGreen),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// Sheet: Nuevo ticket
// ════════════════════════════════════════════════════════════════════════════

class _NuevoTicketSheet extends StatefulWidget {
  final SoporteService service;
  const _NuevoTicketSheet({required this.service});

  @override
  State<_NuevoTicketSheet> createState() => _NuevoTicketSheetState();
}

class _NuevoTicketSheetState extends State<_NuevoTicketSheet> {
  final _titulo = TextEditingController();
  final _descripcion = TextEditingController();
  String _categoria = 'app_movil';
  String _prioridad = 'media';
  bool _enviando = false;

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_titulo.text.trim().isEmpty || _descripcion.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Completa el título y la descripción'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _enviando = true);
    final res = await widget.service.crearTicket(
      titulo: _titulo.text.trim(),
      descripcion: _descripcion.text.trim(),
      categoria: _categoria,
      prioridad: _prioridad,
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (res.ok) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.errorMessage),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: _kIndigo.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bug_report_outlined,
                        color: _kIndigo, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reportar un problema',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('El equipo de TI lo revisará',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                children: [
                  _label('¿Qué tipo de problema es?'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kCategoriasSoporte.entries
                        .map((e) => _chip(
                              label: e.value,
                              selected: _categoria == e.key,
                              onTap: () => setState(() => _categoria = e.key),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  _label('Prioridad'),
                  const SizedBox(height: 8),
                  Row(
                    children: kPrioridadesSoporte.entries.map((e) {
                      final cfg = _prioridadCfg(e.key);
                      final sel = _prioridad == e.key;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _prioridad = e.key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: sel
                                    ? cfg.color.withValues(alpha: 0.15)
                                    : fill.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: sel ? cfg.color : Colors.transparent),
                              ),
                              child: Text(e.value,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: sel ? cfg.color : Colors.grey)),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  _label('Título'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titulo,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Ej: No puedo registrar mi asistencia',
                      filled: true,
                      fillColor: fill,
                      counterText: '',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label('Describe el problema'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descripcion,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText:
                          '¿Qué pasó? ¿Qué esperabas que pasara? ¿En qué pantalla ocurrió?',
                      filled: true,
                      fillColor: fill,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _enviando ? null : _enviar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kIndigo,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _enviando
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Enviar reporte',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
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

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey));

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kIndigo : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _kIndigo : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface)),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Sheet: Detalle del ticket (+ gestión por TI)
// ════════════════════════════════════════════════════════════════════════════

class _DetalleTicketSheet extends StatefulWidget {
  final TicketSoporte ticket;
  final bool esTi;
  final SoporteService service;

  const _DetalleTicketSheet({
    required this.ticket,
    required this.esTi,
    required this.service,
  });

  @override
  State<_DetalleTicketSheet> createState() => _DetalleTicketSheetState();
}

class _DetalleTicketSheetState extends State<_DetalleTicketSheet> {
  late String _estado;
  late final TextEditingController _respuesta;
  bool _guardando = false;
  bool _cambio = false;

  @override
  void initState() {
    super.initState();
    _estado = widget.ticket.estado;
    _respuesta = TextEditingController(text: widget.ticket.respuestaTi ?? '');
  }

  @override
  void dispose() {
    _respuesta.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final res = await widget.service.gestionar(
      widget.ticket.id,
      estado: _estado,
      respuestaTi: _respuesta.text.trim().isEmpty ? null : _respuesta.text.trim(),
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      _cambio = true;
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.errorMessage),
        backgroundColor: _kRed,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final surface = Theme.of(context).colorScheme.surface;
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    final est = _estadoCfg(_estado);
    final pri = _prioridadCfg(t.prioridad);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                children: [
                  Row(
                    children: [
                      Text(t.codigo,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _kIndigo)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, _cambio),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _pill(est.label, est.color),
                      _pill(pri.label, pri.color),
                      _pill(kCategoriasSoporte[t.categoria] ?? t.categoria, _kGray),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(t.titulo,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(t.descripcion,
                      style: const TextStyle(fontSize: 13.5, height: 1.5)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(t.reportanteNombre,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(width: 12),
                      Icon(Icons.schedule, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Text(_fechaCorta(t.creadoEn),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),

                  // Respuesta de TI (visible para todos si existe)
                  if (!widget.esTi &&
                      t.respuestaTi != null &&
                      t.respuestaTi!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.support_agent_rounded,
                                  size: 15, color: _kGreen),
                              SizedBox(width: 6),
                              Text('Respuesta del equipo de TI',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _kGreen)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(t.respuestaTi!,
                              style: const TextStyle(fontSize: 13, height: 1.4)),
                        ],
                      ),
                    ),
                  ],

                  // Gestión (solo TI)
                  if (widget.esTi) ...[
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text('Gestión TI',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _kIndigo)),
                    const SizedBox(height: 10),
                    const Text('Estado',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kEstadosSoporte.entries.map((e) {
                        final cfg = _estadoCfg(e.key);
                        final sel = _estado == e.key;
                        return GestureDetector(
                          onTap: () => setState(() => _estado = e.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel
                                  ? cfg.color.withValues(alpha: 0.15)
                                  : fill.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel ? cfg.color : Colors.transparent),
                            ),
                            child: Text(e.value,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: sel ? cfg.color : Colors.grey)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    const Text('Respuesta al reportante',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _respuesta,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Escribe una respuesta o el estado de la solución…',
                        filled: true,
                        fillColor: fill,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _guardando ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kIndigo,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Guardar cambios',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}
