import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/soporte_models.dart';
import '../services/soporte_service.dart';
import '../utils/api_provider.dart';
import '../utils/ui_insets.dart';
import '../utils/app_session.dart';
import '../widgets/topo_background.dart';

const _kIndigo = Color(0xFF6366F1);
const _kGreen = Color(0xFF8FD11B);
const _kRed = Color(0xFFD6584F);
const _kAmber = Color(0xFFD98A16);
const _kBlue = Color(0xFF3E80C0);
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

    return TopoBackground(
      c1: isDark ? const Color(0xFF1E1B4B) : const Color(0xFF3730A3),
      c2: isDark ? const Color(0xFF3730A3) : const Color(0xFF6366F1),
      base: isDark ? const Color(0xFF0B0B14) : const Color(0xFFF5F5FF),
      count: 14,
      amp: 8,
      stroke: 0.35,
      speed: 0.4,
      child: Scaffold(
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
      body: Column(
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
                            padding: bottomSafePadding(context, extra: 90),
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
  final _picker = ImagePicker();
  late TicketSoporte _t;

  List<TicketActividad> _actividades = [];
  bool _loadingAct = true;
  bool _cambio = false;

  // Composer
  final _texto = TextEditingController();
  String _tipo = 'comentario'; // comentario | avance | solucion
  String? _adjuntoB64;
  bool _enviando = false;
  bool _tomando = false;

  @override
  void initState() {
    super.initState();
    _t = widget.ticket;
    _loadActividades();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _loadActividades() async {
    final data = await widget.service.getActividades(_t.id);
    if (!mounted) return;
    setState(() {
      _actividades = data;
      _loadingAct = false;
    });
  }

  void _err(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: _kRed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _tomar() async {
    setState(() => _tomando = true);
    final res = await widget.service.tomar(_t.id);
    if (!mounted) return;
    setState(() => _tomando = false);
    if (res.ok) {
      setState(() {
        _t = res.data!;
        _cambio = true;
      });
      await _loadActividades();
    } else {
      _err(res.errorMessage);
    }
  }

  Future<void> _cambiarEstado(String estado) async {
    if (estado == _t.estado) return;
    final res = await widget.service.gestionar(_t.id, estado: estado);
    if (!mounted) return;
    if (res.ok) {
      setState(() {
        _t = res.data!;
        _cambio = true;
      });
      await _loadActividades();
    } else {
      _err(res.errorMessage);
    }
  }

  Future<void> _adjuntar() async {
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1920);
    if (x == null) return;
    final b64 = base64Encode(await x.readAsBytes());
    if (!mounted) return;
    setState(() => _adjuntoB64 = b64);
  }

  Future<void> _enviarActividad() async {
    if (_texto.text.trim().isEmpty && _adjuntoB64 == null) {
      _err('Escribe un texto o adjunta una imagen');
      return;
    }
    setState(() => _enviando = true);
    final res = await widget.service.crearActividad(
      _t.id,
      tipo: _tipo,
      texto: _texto.text.trim().isEmpty ? null : _texto.text.trim(),
      esSolucion: _tipo == 'solucion',
      adjuntoBase64: _adjuntoB64,
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (res.ok) {
      _texto.clear();
      setState(() {
        _adjuntoB64 = null;
        _tipo = 'comentario';
        _cambio = true;
      });
      // Una solución puede haber cambiado el estado del ticket → recargar ambos.
      final t = await widget.service.getTickets(alcance: widget.esTi ? 'todos' : 'mios');
      final actualizado = t.where((x) => x.id == _t.id);
      if (actualizado.isNotEmpty && mounted) setState(() => _t = actualizado.first);
      await _loadActividades();
    } else {
      _err(res.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final surface = Theme.of(context).colorScheme.surface;
    final est = _estadoCfg(t.estado);
    final pri = _prioridadCfg(t.prioridad);

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
                  if (t.adjuntoUrl != null && t.adjuntoUrl!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _thumb(t.adjuntoUrl!),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _metaItem(Icons.person_outline, t.reportanteNombre),
                      _metaItem(Icons.schedule, _fechaCorta(t.creadoEn)),
                      if (t.atendidoPorNombre != null)
                        _metaItem(Icons.support_agent_rounded,
                            'Atiende: ${t.atendidoPorNombre}',
                            color: _kIndigo),
                    ],
                  ),

                  // ── Acciones de TI: tomar + estado ──────────────────────────
                  if (widget.esTi) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _tomando ? null : _tomar,
                        icon: _tomando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _kIndigo))
                            : const Icon(Icons.pan_tool_alt_outlined, size: 18),
                        label: Text(t.atendidoPor == null
                            ? 'Tomar este ticket'
                            : 'Reasignármelo'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kIndigo,
                          side: const BorderSide(color: _kIndigo),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('Estado',
                        style: TextStyle(fontSize: 12.5, color: Colors.grey)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kEstadosSoporte.entries.map((e) {
                        final cfg = _estadoCfg(e.key);
                        final sel = t.estado == e.key;
                        return GestureDetector(
                          onTap: () => _cambiarEstado(e.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel
                                  ? cfg.color.withValues(alpha: 0.15)
                                  : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.4),
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
                  ],

                  // ── Timeline de seguimiento ─────────────────────────────────
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.timeline, size: 16, color: _kIndigo),
                      const SizedBox(width: 6),
                      const Text('Seguimiento',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _kIndigo)),
                      const Spacer(),
                      if (!_loadingAct)
                        Text('${_actividades.length}',
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loadingAct)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                          child: CircularProgressIndicator(color: _kIndigo)),
                    )
                  else if (_actividades.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text('Sin movimientos todavía.',
                          style: TextStyle(
                              fontSize: 12.5, color: Colors.grey.shade500)),
                    )
                  else
                    ..._actividades.map(_buildActividad),

                  // ── Composer ────────────────────────────────────────────────
                  const SizedBox(height: 16),
                  _buildComposer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String text, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color ?? Colors.grey.shade500),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 12, color: color ?? Colors.grey.shade600)),
        ],
      );

  Widget _thumb(String url) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          url,
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            height: 60,
            color: Colors.grey.withValues(alpha: 0.15),
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      );

  ({IconData icon, Color color}) _tipoCfg(TicketActividad a) {
    if (a.esSolucion) return (icon: Icons.verified_rounded, color: _kGreen);
    return switch (a.tipo) {
      'avance' => (icon: Icons.trending_up_rounded, color: _kAmber),
      'cambio_estado' => (icon: Icons.swap_horiz_rounded, color: _kBlue),
      'tomado' => (icon: Icons.pan_tool_alt_outlined, color: _kIndigo),
      _ => (icon: Icons.chat_bubble_outline_rounded, color: _kGray),
    };
  }

  Widget _buildActividad(TicketActividad a) {
    final cfg = _tipoCfg(a);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: cfg.color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(cfg.icon, size: 16, color: cfg.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(a.autorNombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    if (a.esSolucion) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _kGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Solución v${a.versionSolucion ?? 1}',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _kGreen)),
                      ),
                    ],
                    const Spacer(),
                    Text(_fechaCorta(a.creadoEn),
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
                if (a.texto != null && a.texto!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(a.texto!,
                      style: const TextStyle(fontSize: 12.5, height: 1.4)),
                ],
                if (a.adjuntoUrl != null && a.adjuntoUrl!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _thumb(a.adjuntoUrl!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
    // El reportante solo comenta; el equipo de TI puede registrar avances y soluciones.
    final tipos = widget.esTi
        ? const {'comentario': 'Comentario', 'avance': 'Avance', 'solucion': 'Solución'}
        : const {'comentario': 'Comentario'};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fill.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tipos.length > 1)
            Wrap(
              spacing: 8,
              children: tipos.entries.map((e) {
                final sel = _tipo == e.key;
                final c = e.key == 'solucion'
                    ? _kGreen
                    : (e.key == 'avance' ? _kAmber : _kGray);
                return GestureDetector(
                  onTap: () => setState(() => _tipo = e.key),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? c.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: sel ? c : Colors.grey.shade300),
                    ),
                    child: Text(e.value,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: sel ? c : Colors.grey)),
                  ),
                );
              }).toList(),
            ),
          if (tipos.length > 1) const SizedBox(height: 10),
          TextField(
            controller: _texto,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              hintText: _tipo == 'solucion'
                  ? 'Describe la solución aplicada…'
                  : (_tipo == 'avance'
                      ? '¿Qué avance hubo? ¿Algún error encontrado?'
                      : 'Escribe un comentario…'),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          if (_adjuntoB64 != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.image_outlined, size: 16, color: _kIndigo),
                const SizedBox(width: 6),
                const Text('Imagen adjunta',
                    style: TextStyle(fontSize: 12, color: _kIndigo)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _adjuntoB64 = null),
                  child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: _enviando ? null : _adjuntar,
                icon: const Icon(Icons.attach_file_rounded),
                color: _kIndigo,
                tooltip: 'Adjuntar imagen',
              ),
              const Spacer(),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _enviando ? null : _enviarActividad,
                  icon: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Enviar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kIndigo,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
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
