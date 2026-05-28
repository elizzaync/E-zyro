import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/proyecto_models.dart';
import '../models/comunicado_models.dart';
import '../services/proyecto_service.dart';
import '../utils/app_notifiers.dart';
import '../utils/app_session.dart';
import '../services/comunicado_service.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
import '../templates/informe_servicio_pdf.dart';
import 'pantalla_chat.dart';
import 'pantalla_asignacion_servicio.dart';
import 'pantalla_crear_servicio.dart';

const _green = Color(0xFF8FD11B);
const _amber = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);

class DetalleServicioScreen extends StatefulWidget {
  final String servicioId;
  final String proyectoId;
  final String nombreServicio;
  final ProyectoService service;

  const DetalleServicioScreen({
    super.key,
    required this.servicioId,
    required this.proyectoId,
    required this.nombreServicio,
    required this.service,
  });

  @override
  State<DetalleServicioScreen> createState() => _DetalleServicioScreenState();
}

class _DetalleServicioScreenState extends State<DetalleServicioScreen>
    with SingleTickerProviderStateMixin {
  ServicioDetalle? _detalle;
  Borrador _borrador = const Borrador(items: []);
  bool _isLoading = true;
  bool _puedeFinalizar = false;
  bool _cambiandoEstado = false;
  late TabController _tabController;
  DateTime? _lastDetailLoad;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _checkRol();
    _load();
    pendientesEvidenciaNotifier.addListener(_onEvidenciaSync);
    syncCompletedNotifier.addListener(_onSyncCompleted);
  }

  @override
  void dispose() {
    pendientesEvidenciaNotifier.removeListener(_onEvidenciaSync);
    syncCompletedNotifier.removeListener(_onSyncCompleted);
    _tabController.dispose();
    super.dispose();
  }

  /// Cuando las evidencias pendientes cambian (o el sync completa), recargar
  /// el detalle del servicio para reflejar los procedimientos actualizados.
  void _onEvidenciaSync() => _throttledDetailLoad();
  void _onSyncCompleted() => _throttledDetailLoad();

  void _throttledDetailLoad() {
    if (!mounted) return;
    final ahora = DateTime.now();
    if (_lastDetailLoad != null &&
        ahora.difference(_lastDetailLoad!) < const Duration(seconds: 15)) {
      return;
    }
    _lastDetailLoad = ahora;
    _reloadDetalle();
  }

  Future<void> _checkRol() async {
    await AppSession.load();
    if (mounted) {
      setState(() => _puedeFinalizar = AppSession.i.canFinalizarServicio);
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      widget.service.getDetalleServicio(widget.servicioId),
      widget.service.getBorrador(widget.servicioId),
    ]);
    if (!mounted) return;
    setState(() {
      _detalle = results[0] as ServicioDetalle?;
      _borrador = results[1] as Borrador;
      _isLoading = false;
    });
  }

  Future<void> _reloadDetalle() async {
    final data = await widget.service.getDetalleServicio(widget.servicioId);
    if (!mounted || data == null) return;
    setState(() => _detalle = data);
  }

  Future<void> _reloadBorrador() async {
    final b = await widget.service.getBorrador(widget.servicioId);
    if (!mounted) return;
    setState(() => _borrador = b);
  }

  // ── Cambiar estado del servicio ─────────────────────────────────────────────
  Future<void> _cambiarEstado(String estado) async {
    if (_detalle == null || _cambiandoEstado) return;
    setState(() => _cambiandoEstado = true);
    final ok = await widget.service.cambiarEstadoServicio(_detalle!.id, estado);
    if (!mounted) return;
    setState(() => _cambiandoEstado = false);
    if (ok) {
      await _reloadDetalle();
      _snack('Estado actualizado a ${_estadoLabel(estado)}', _green);
    } else {
      _snack('No se pudo cambiar el estado', _danger);
    }
  }

  // ── Finalizar servicio (solo jefe / admin) ──────────────────────────────────
  Future<void> _finalizarServicio() async {
    final d = _detalle;
    if (d == null) return;
    if (!_puedeFinalizar) {
      _snack('Solo el Jefe de Operaciones puede finalizar el servicio', _danger);
      return;
    }
    if (d.progreso < 100) {
      _snack('Completa todos los procedimientos antes de finalizar', _amber);
      return;
    }
    // Cerrar el servicio y abrir el pre-informe PDF
    final ok = await widget.service.cambiarEstadoServicio(d.id, 'Completado');
    if (!mounted) return;
    if (ok) await _reloadDetalle();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InformeServicioPreviewScreen(detalle: _detalle ?? d),
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static String _estadoLabel(String e) => switch (e) {
        'En_Proceso' => 'En Proceso',
        _ => e,
      };

  Future<void> _editarServicio() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaCrearServicio(
          service: widget.service,
          proyectoId: widget.proyectoId,
          mode: 'editar',
          servicioId: widget.servicioId,
        ),
      ),
    );
    if (ok == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _detalle;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.nombreServicio,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        actions: [
          if (d != null && !_cambiandoEstado)
            PopupMenuButton<String>(
              icon: const Icon(Icons.flag_outlined, size: 20),
              tooltip: 'Cambiar estado',
              onSelected: _cambiarEstado,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'Pendiente', child: Text('Pendiente')),
                PopupMenuItem(value: 'En_Proceso', child: Text('En Proceso')),
                PopupMenuItem(value: 'Completado', child: Text('Completado')),
                PopupMenuItem(value: 'Cancelado', child: Text('Cancelado')),
              ],
            ),
          if (d != null &&
              (AppSession.i.isJefeOperaciones || AppSession.i.isAdmin))
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Editar servicio',
              onPressed: _editarServicio,
            ),
          if (d != null && _puedeFinalizar && d.estado != 'Completado')
            IconButton(
              icon: const Icon(Icons.task_alt_outlined, size: 20),
              tooltip: 'Finalizar y generar informe',
              color: d.progreso >= 100 ? _green : null,
              onPressed: _finalizarServicio,
            ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_green),
              ),
            )
          : d == null
              ? _ErrorView(onRetry: _load)
              : Column(
                  children: [
                    _Header(detalle: d),
                    const SizedBox(height: 12),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: _green,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: _green,
                      labelPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12),
                      tabs: [
                        Tab(
                            height: 46,
                            icon: const Icon(Icons.checklist_rounded, size: 18),
                            text: 'Pasos · ${d.procedimientos.length}'),
                        Tab(
                            height: 46,
                            icon: const Icon(Icons.groups_outlined, size: 18),
                            text: 'Equipo · ${d.equipo.length}'),
                        Tab(
                          height: 46,
                          icon: const Icon(Icons.inventory_2_outlined, size: 18),
                          text:
                              'Material · ${d.materialesAsignados.length + d.materialesSolicitados.length}',
                        ),
                        Tab(
                            height: 46,
                            icon: const Icon(Icons.sticky_note_2_outlined,
                                size: 18),
                            text: 'Notas · ${d.notas.length}'),
                        const Tab(
                            height: 46,
                            icon: Icon(Icons.chat_bubble_outline, size: 18),
                            text: 'Chat'),
                        const Tab(
                            height: 46,
                            icon: Icon(Icons.campaign_outlined, size: 18),
                            text: 'Avisos'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _ProcedimientosTab(
                            procedimientos: d.procedimientos,
                            service: widget.service,
                            onChanged: _reloadDetalle,
                          ),
                          _EquipoTab(
                            equipo: d.equipo,
                            servicioId: d.id,
                            proyectoId: d.proyectoId,
                            service: widget.service,
                            onChanged: _reloadDetalle,
                          ),
                          _MaterialesTab(
                            servicioId: d.id,
                            asignados: d.materialesAsignados,
                            solicitados: d.materialesSolicitados,
                            borrador: _borrador,
                            service: widget.service,
                            onChanged: _reloadBorrador,
                          ),
                          _NotasTab(notas: d.notas),
                          ChatTab(
                            room: 'servicio/${widget.servicioId}',
                            fotosPorId: {
                              for (final m in d.equipo)
                                if (m.fotoUrl.isNotEmpty) m.id: m.fotoUrl,
                            },
                          ),
                          _ComunicadosTab(proyectoId: widget.proyectoId),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ─── Header con datos + progreso ──────────────────────────────────────────────

class _Header extends StatelessWidget {
  final ServicioDetalle detalle;
  const _Header({required this.detalle});

  Color get _statusColor => switch (detalle.estado) {
        'Completado' => _green,
        'En_Proceso' => const Color(0xFF3B82F6),
        'Cancelado' => _danger,
        _ => _amber,
      };

  String get _estadoLabel => switch (detalle.estado) {
        'En_Proceso' => 'En Proceso',
        _ => detalle.estado,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.30)) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detalle.cliente,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                    const SizedBox(height: 2),
                    Text(detalle.tipoServicio,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: isDark ? 0.15 : 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_estadoLabel,
                    style: TextStyle(
                        color: _statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(Icons.location_on_outlined, detalle.ubicacion),
          _InfoRow(Icons.calendar_today_outlined, detalle.fechaStr),
          _InfoRow(Icons.access_time_outlined, detalle.horaStr),
          if (detalle.descripcion.isNotEmpty)
            _InfoRow(Icons.notes_outlined, detalle.descripcion),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Progreso',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
              const Spacer(),
              Text('${detalle.progreso.round()}%',
                  style: TextStyle(
                      color: detalle.progreso >= 100 ? _green : _amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: detalle.progreso / 100,
              backgroundColor:
                  isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(
                  detalle.progreso >= 100 ? _green : _amber),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Fila de info ─────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Procedimientos (interactivo) ────────────────────────────────────────

class _ProcedimientosTab extends StatelessWidget {
  final List<ProcedimientoDetalle> procedimientos;
  final ProyectoService service;
  final Future<void> Function() onChanged;

  const _ProcedimientosTab({
    required this.procedimientos,
    required this.service,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (procedimientos.isEmpty) {
      return _EmptyTab(
        icon: Icons.checklist_outlined,
        label: 'Sin procedimientos registrados',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: procedimientos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ProcedimientoCard(
        proc: procedimientos[i],
        service: service,
        onChanged: onChanged,
      ),
    );
  }
}

class _ProcedimientoCard extends StatelessWidget {
  final ProcedimientoDetalle proc;
  final ProyectoService service;
  final Future<void> Function() onChanged;

  const _ProcedimientoCard({
    required this.proc,
    required this.service,
    required this.onChanged,
  });

  Color get _color => switch (proc.estado) {
        'completado' => _green,
        'en_proceso' => const Color(0xFF3B82F6),
        'bloqueado' => _danger,
        _ => _amber,
      };

  IconData get _icon => switch (proc.estado) {
        'completado' => Icons.check_circle,
        'en_proceso' => Icons.play_circle_outline,
        'bloqueado' => Icons.block,
        _ => Icons.radio_button_unchecked,
      };

  Future<void> _toggle() async {
    final nuevo = proc.estado == 'completado' ? 'pendiente' : 'completado';
    await service.toggleProcedimiento(proc.id, nuevo);
    await onChanged();
  }

  void _abrirEvidencia(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EvidenciaSheet(
        proc: proc,
        service: service,
        onUploaded: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _color.withValues(alpha: isDark ? 0.30 : 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _toggle,
                child: Icon(_icon, color: _color, size: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${proc.orden}. ${proc.nombre}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: () => _abrirEvidencia(context),
                icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                label: const Text('Evidencia',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: _green,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ],
          ),
          if (proc.descripcion.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(proc.descripcion,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
          if (proc.evidencias.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    proc.evidencias.map((e) => _EvidenciaThumb(ev: e)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Sheet de subida de evidencia por etapa ───────────────────────────────────

class _EvidenciaSheet extends StatefulWidget {
  final ProcedimientoDetalle proc;
  final ProyectoService service;
  final Future<void> Function() onUploaded;

  const _EvidenciaSheet({
    required this.proc,
    required this.service,
    required this.onUploaded,
  });

  @override
  State<_EvidenciaSheet> createState() => _EvidenciaSheetState();
}

class _EvidenciaSheetState extends State<_EvidenciaSheet> {
  static const _etapas = ['antes', 'durante', 'despues'];
  static const _labels = {
    'antes': 'Antes',
    'durante': 'Durante',
    'despues': 'Después',
  };
  String? _subiendo; // etapa en curso
  final Set<String> _encoladas = {}; // etapas guardadas offline (pendientes)

  bool _tieneEtapa(String etapa) =>
      widget.proc.evidencias.any((e) => e.etapaLower == etapa) ||
      _encoladas.contains(etapa);

  Future<void> _capturar(String etapa) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: _green),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _green),
              title: const Text('Elegir de galería'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked =
        await ImagePicker().pickImage(source: source, imageQuality: 70);
    if (picked == null) return;

    setState(() => _subiendo = etapa);
    final subida = await widget.service.encolarEvidencia(
      procedimientoId: widget.proc.id,
      etapa: etapa,
      fotoPath: picked.path,
    );
    if (!mounted) return;
    setState(() {
      _subiendo = null;
      if (!subida) _encoladas.add(etapa);
    });
    if (subida) {
      // Subida directa (con conexión).
      await widget.onUploaded();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Evidencia "${_labels[etapa]}" subida', style: const TextStyle(color: Colors.white)),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } else {
      // Sin conexión: guardada en cola, se enviará al reconectar.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Evidencia "${_labels[etapa]}" guardada · se subirá al reconectar',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.amber.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Evidencia: ${widget.proc.nombre}',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Registra una foto por cada etapa del procedimiento',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 16),
          ..._etapas.map((etapa) {
            final hecho = _tieneEtapa(etapa);
            final cargando = _subiendo == etapa;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(
                    hecho ? Icons.check_circle : Icons.circle_outlined,
                    color: hecho ? _green : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_labels[etapa]!,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                  ElevatedButton(
                    onPressed: cargando ? null : () => _capturar(etapa),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hecho ? Colors.grey.shade300 : _green,
                      foregroundColor: hecho ? Colors.black54 : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: cargando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(hecho ? 'Reemplazar' : 'Capturar',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _EvidenciaThumb extends StatelessWidget {
  final EvidenciaDetalle ev;
  const _EvidenciaThumb({required this.ev});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: ev.urlCloudinary,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorWidget: (_, _, _) => Container(
            width: 64,
            height: 64,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            CachedNetworkImage(imageUrl: ev.urlCloudinary, fit: BoxFit.contain),
            if (ev.descripcion.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(ev.descripcion,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Tab: Equipo ──────────────────────────────────────────────────────────────

class _EquipoTab extends StatefulWidget {
  final List<MiembroEquipo> equipo;
  final String servicioId;
  final String proyectoId;
  final ProyectoService service;
  final Future<void> Function() onChanged;

  const _EquipoTab({
    required this.equipo,
    required this.servicioId,
    required this.proyectoId,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_EquipoTab> createState() => _EquipoTabState();
}

class _EquipoTabState extends State<_EquipoTab> {
  bool get _puedeAsignar =>
      AppSession.i.isJefeOperaciones || AppSession.i.isAdmin;

  // ── Abre la pantalla de configuración (equipo + cronograma) ─────────────────
  Future<void> _abrirAsignacion() async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaAsignacionServicio(
          servicioId: widget.servicioId,
          service: widget.service,
          mode: 'editar',
        ),
      ),
    );
    if (guardado == true) {
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Asignación actualizada'),
        backgroundColor: _green,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tieneEquipo = widget.equipo.isNotEmpty;
    return Stack(
      children: [
        widget.equipo.isEmpty
            ? const _EmptyTab(
                icon: Icons.group_outlined,
                label: 'Sin equipo asignado')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                itemCount: widget.equipo.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _MiembroCard(
                  miembro: widget.equipo[i],
                ),
              ),
        // FAB de configuración solo para Jefe de Operaciones / Admin
        if (_puedeAsignar)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'fab_equipo',
              onPressed: _abrirAsignacion,
              backgroundColor: _green,
              foregroundColor: Colors.white,
              icon: Icon(tieneEquipo
                  ? Icons.edit_calendar_outlined
                  : Icons.group_add_outlined),
              label: Text(
                  tieneEquipo ? 'Editar asignación' : 'Configurar asignación',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}

class _MiembroCard extends StatelessWidget {
  final MiembroEquipo miembro;
  const _MiembroCard({required this.miembro});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.25)) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage:
                miembro.fotoUrl.isNotEmpty ? CachedNetworkImageProvider(miembro.fotoUrl) : null,
            backgroundColor:
                isDark ? _green.withValues(alpha: 0.20) : const Color(0xFFEFFAE0),
            child: miembro.fotoUrl.isEmpty
                ? Text(
                    miembro.nombre.isNotEmpty
                        ? miembro.nombre[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                        color: _green, fontWeight: FontWeight.bold))
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(miembro.nombreCompleto,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(miembro.cargo,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? _green.withValues(alpha: 0.15)
                  : const Color(0xFFEFFAE0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(miembro.rolProyecto,
                style: const TextStyle(
                    color: _green,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Materiales (con borrador interactivo) ───────────────────────────────

class _MaterialesTab extends StatefulWidget {
  final String servicioId;
  final List<ItemMaterial> asignados;
  final List<ItemMaterial> solicitados;
  final Borrador borrador;
  final ProyectoService service;
  final Future<void> Function() onChanged;

  const _MaterialesTab({
    required this.servicioId,
    required this.asignados,
    required this.solicitados,
    required this.borrador,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_MaterialesTab> createState() => _MaterialesTabState();
}

class _MaterialesTabState extends State<_MaterialesTab> {
  bool _enviando = false;

  Future<void> _abrirSolicitar() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SolicitarMaterialSheet(
        servicioId: widget.servicioId,
        service: widget.service,
        onAgregado: widget.onChanged,
      ),
    );
  }

  Future<void> _enviarBorrador() async {
    if (widget.borrador.items.isEmpty) return;
    setState(() => _enviando = true);
    final ok = await widget.service.enviarBorrador(widget.servicioId);
    if (!mounted) return;
    setState(() => _enviando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Solicitud enviada a Logística' : 'Error al enviar',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: ok ? _green : _danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (ok) await widget.onChanged();
  }

  Future<void> _quitar(BorradorItem item) async {
    final ok = await widget.service.removerItemBorrador(item.id);
    if (ok) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final borrador = widget.borrador;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            // ── Borrador en construcción ─────────────────────────────────────
            if (borrador.items.isNotEmpty) ...[
              Row(
                children: [
                  const _SectionTitle(
                      'Borrador de Solicitud', Icons.edit_note, _amber),
                  const Spacer(),
                  Text('${borrador.items.length} ítem(s)',
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 8),
              ...borrador.items.map((it) => _BorradorCard(
                    item: it,
                    onRemove: () => _quitar(it),
                    onEdit: () => _editar(it),
                  )),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _enviando ? null : _enviarBorrador,
                  icon: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined, size: 16),
                  label: Text(_enviando ? 'Enviando...' : 'Enviar a Logística',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _amber,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (widget.asignados.isEmpty &&
                widget.solicitados.isEmpty &&
                borrador.items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: _EmptyTab(
                  icon: Icons.inventory_2_outlined,
                  label: 'Sin materiales registrados',
                ),
              ),

            if (widget.asignados.isNotEmpty) ...[
              const _SectionTitle(
                  'Materiales Asignados', Icons.check_circle_outline, _green),
              const SizedBox(height: 8),
              ...widget.asignados.map((m) => _MaterialCard(item: m)),
              const SizedBox(height: 16),
            ],
            if (widget.solicitados.isNotEmpty) ...[
              const _SectionTitle(
                  'Materiales Solicitados', Icons.pending_outlined, _amber),
              const SizedBox(height: 8),
              ...widget.solicitados.map((m) => _MaterialCard(item: m)),
            ],
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_solicitar_${widget.servicioId}',
            onPressed: _abrirSolicitar,
            backgroundColor: _green,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Solicitar',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Future<void> _editar(BorradorItem item) async {
    final cantCtrl = TextEditingController(text: '${item.cantidad}');
    final nombreCtrl = TextEditingController(text: item.nombre);
    final especCtrl = TextEditingController(text: item.especificacion ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar ítem'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.esNuevo) ...[
              TextField(
                controller: nombreCtrl,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              TextField(
                controller: especCtrl,
                decoration: const InputDecoration(labelText: 'Especificación'),
              ),
            ],
            TextField(
              controller: cantCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final cant = int.tryParse(cantCtrl.text.trim()) ?? item.cantidad;
    await widget.service.actualizarReqDetalle(
      item.id,
      cantidad: cant < 1 ? 1 : cant,
      nombre: item.esNuevo ? nombreCtrl.text.trim() : null,
      especificacion: item.esNuevo ? especCtrl.text.trim() : null,
    );
    await widget.onChanged();
  }
}

class _BorradorCard extends StatelessWidget {
  final BorradorItem item;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _BorradorCard({
    required this.item,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _amber.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(item.esNuevo ? Icons.shopping_bag_outlined : Icons.inventory_2_outlined,
              size: 16, color: _amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Text('${item.cantidad} ${item.unidad}${item.esNuevo ? ' · Compra externa' : ''}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.grey),
            onPressed: onEdit,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: _danger),
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ─── Sheet: Solicitar material (catálogo + compra externa) ────────────────────

class _SolicitarMaterialSheet extends StatefulWidget {
  final String servicioId;
  final ProyectoService service;
  final Future<void> Function() onAgregado;

  const _SolicitarMaterialSheet({
    required this.servicioId,
    required this.service,
    required this.onAgregado,
  });

  @override
  State<_SolicitarMaterialSheet> createState() =>
      _SolicitarMaterialSheetState();
}

class _SolicitarMaterialSheetState extends State<_SolicitarMaterialSheet> {
  bool _externo = false;
  bool _guardando = false;

  // Catálogo
  final _busquedaCtrl = TextEditingController();
  List<MaterialBusqueda> _resultados = [];
  MaterialBusqueda? _elegido;
  int _cantidad = 1;
  Timer? _debounce;

  // Compra externa
  final _nombreCtrl = TextEditingController();
  final _especCtrl = TextEditingController();
  String _unidad = 'Unidades';
  int _cantExterno = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaCtrl.dispose();
    _nombreCtrl.dispose();
    _especCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await widget.service.buscarMateriales(q);
      if (mounted) setState(() => _resultados = r);
    });
  }

  Future<void> _agregarCatalogo() async {
    if (_elegido == null) return;
    setState(() => _guardando = true);
    final id = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: _elegido!.id,
      nombre: _elegido!.nombre,
      unidad: _elegido!.unidad,
      cantidad: _cantidad,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (id != null) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _agregarExterno() async {
    final nombre = _nombreCtrl.text.trim();
    final espec = _especCtrl.text.trim();
    if (nombre.isEmpty || espec.isEmpty) return;
    setState(() => _guardando = true);
    final id = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: null,
      nombre: nombre,
      unidad: _unidad,
      cantidad: _cantExterno,
      especificacion: espec,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (id != null) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text('Solicitar Material',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Toggle catálogo / externo
          Row(
            children: [
              _ToggleChip(
                label: 'Del Catálogo',
                selected: !_externo,
                onTap: () => setState(() => _externo = false),
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: 'Compra Externa',
                selected: _externo,
                onTap: () => setState(() => _externo = true),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_externo) ..._buildCatalogo() else ..._buildExterno(),
        ],
      ),
    );
  }

  List<Widget> _buildCatalogo() {
    return [
      TextField(
        controller: _busquedaCtrl,
        onChanged: _onSearch,
        decoration: InputDecoration(
          hintText: 'Buscar material (mín. 2 letras)...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      if (_elegido == null && _resultados.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: _resultados
                .map((m) => ListTile(
                      dense: true,
                      title: Text(m.nombre),
                      subtitle: Text('Stock: ${m.stock} ${m.unidad}'),
                      onTap: () => setState(() {
                        _elegido = m;
                        _busquedaCtrl.text = m.nombre;
                        _resultados = [];
                      }),
                    ))
                .toList(),
          ),
        ),
      if (_elegido != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _green.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(_elegido!.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              _QtyStepper(
                value: _cantidad,
                onChanged: (v) => setState(() => _cantidad = v),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_elegido == null || _guardando) ? null : _agregarCatalogo,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Agregar al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }

  List<Widget> _buildExterno() {
    return [
      TextField(
        controller: _nombreCtrl,
        decoration: InputDecoration(
          labelText: 'Nombre del material',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _especCtrl,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Especificación (obligatoria)',
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _unidad,
              decoration: InputDecoration(
                labelText: 'Unidad',
                filled: true,
                fillColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              items: const ['Unidades', 'Metros', 'Kilogramos', 'Litros', 'Cajas']
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: (v) => setState(() => _unidad = v ?? 'Unidades'),
            ),
          ),
          const SizedBox(width: 12),
          _QtyStepper(
            value: _cantExterno,
            onChanged: (v) => setState(() => _cantExterno = v),
          ),
        ],
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _guardando ? null : _agregarExterno,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Agregar al Borrador',
                  style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ];
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _green : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? _green : Colors.grey.shade300),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _QtyStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: _green),
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          visualDensity: VisualDensity.compact,
        ),
        Text('$value',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: _green),
          onPressed: () => onChanged(value + 1),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _MaterialCard extends StatelessWidget {
  final ItemMaterial item;
  const _MaterialCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark
                ? Colors.grey.withValues(alpha: 0.20)
                : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.nombre,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Text('${item.cantidad} ${item.unidad}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Tab: Notas ───────────────────────────────────────────────────────────────

class _NotasTab extends StatelessWidget {
  final List<NotaSeguimiento> notas;
  const _NotasTab({required this.notas});

  @override
  Widget build(BuildContext context) {
    if (notas.isEmpty) {
      return _EmptyTab(
          icon: Icons.notes_outlined, label: 'Sin notas de seguimiento');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: notas.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _NotaCard(nota: notas[i]),
    );
  }
}

class _NotaCard extends StatelessWidget {
  final NotaSeguimiento nota;
  const _NotaCard({required this.nota});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: isDark ? Border.all(color: _green.withValues(alpha: 0.20)) : null,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? _green.withValues(alpha: 0.15)
                      : const Color(0xFFEFFAE0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_outline,
                    size: 14, color: _green),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nota.autor,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    Text(nota.fecha,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(nota.texto,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
    );
  }
}

// ─── Estado vacío genérico ────────────────────────────────────────────────────

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

// ─── Tab: Comunicados del Proyecto (HU-13) ────────────────────────────────────

class _ComunicadosTab extends StatefulWidget {
  final String proyectoId;
  const _ComunicadosTab({required this.proyectoId});

  @override
  State<_ComunicadosTab> createState() => _ComunicadosTabState();
}

class _ComunicadosTabState extends State<_ComunicadosTab>
    with AutomaticKeepAliveClientMixin {
  ComunicadoService? _service;
  List<ComunicadoProyecto> _comunicados = [];
  bool _loading = true;
  bool _puedeEnviar = false;
  bool _sessionExpired = false;
  StreamSubscription<RemoteMessage>? _fcmSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
    _fcmSub = FcmFlutterService.messageStream.listen((msg) {
      if ((msg.data['tipo'] as String?) == 'comunicado_proyecto' &&
          (msg.data['proyecto_id'] as String?) == widget.proyectoId) {
        _load();
      }
    });
    _checkPermiso();
  }

  Future<void> _checkPermiso() async {
    await AppSession.load();
    if (mounted) setState(() => _puedeEnviar = AppSession.i.canEnviarComunicado);
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _service = await getComunicadoService();
    await _load();
  }

  Future<void> _load() async {
    if (_service == null) return;
    setState(() {
      _loading = true;
      _sessionExpired = false;
    });
    try {
      final data = await _service!.getComunicadosProyecto(widget.proyectoId);
      if (!mounted) return;
      setState(() {
        _comunicados = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final expired =
          e.toString().contains('expirada') || e.toString().contains('Sesión');
      setState(() {
        _loading = false;
        _sessionExpired = expired;
      });
    }
  }

  Future<void> _marcarLeido(ComunicadoProyecto c) async {
    if (c.leido) return;
    await _service?.marcarLeidoProyecto(c.id);
    if (!mounted) return;
    setState(() {
      final idx = _comunicados.indexWhere((e) => e.id == c.id);
      if (idx != -1) _comunicados[idx] = _comunicados[idx].markRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_green)),
      );
    }

    if (_sessionExpired) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_clock_outlined, size: 44, color: Colors.orange),
            const SizedBox(height: 10),
            const Text('Sesión expirada',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            const Text('Cierra sesión e inicia nuevamente.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false),
              child: const Text('Ir al Login',
                  style:
                      TextStyle(color: _green, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
    }

    if (_comunicados.isEmpty) {
      return _EmptyTab(
          icon: Icons.campaign_outlined, label: 'Sin comunicados del proyecto');
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          color: _green,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(16, 16, 16, _puedeEnviar ? 90 : 16),
            itemCount: _comunicados.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _ComunicadoCard(
              comunicado: _comunicados[i],
              onTap: () => _marcarLeido(_comunicados[i]),
            ),
          ),
        ),
        if (_puedeEnviar)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'fab_comunicado_${widget.proyectoId}',
              onPressed: _openNuevoComunicado,
              backgroundColor: _green,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('Nuevo',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }

  void _openNuevoComunicado() {
    final tituloCtrl = TextEditingController();
    final mensajeCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          bool sending = false;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 32,
            ),
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
                const SizedBox(height: 20),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.campaign_outlined,
                        color: _amber, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nuevo Comunicado',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Enviar al proyecto',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ]),
                const SizedBox(height: 20),
                const Text('Título',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: tituloCtrl,
                  maxLength: 200,
                  decoration: InputDecoration(
                    hintText: 'Título del comunicado...',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Mensaje',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: mensajeCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Escribe el comunicado...',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 24),
                StatefulBuilder(
                  builder: (_, setSend) => SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: sending
                          ? null
                          : () async {
                              final titulo = tituloCtrl.text.trim();
                              final mensaje = mensajeCtrl.text.trim();
                              if (titulo.isEmpty || mensaje.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Completa el título y el mensaje'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }
                              setSend(() => sending = true);
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await _service?.crearComunicado(
                                    proyectoId: widget.proyectoId,
                                    titulo: titulo,
                                    mensaje: mensaje,
                                  ) ??
                                  false;
                              if (!mounted) return;
                              Navigator.pop(ctx);
                              if (ok) {
                                _load();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: const Text('Comunicado enviado'),
                                    backgroundColor: _green,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                );
                              } else {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Error al enviar. Intenta nuevamente.'),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Enviar Comunicado',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ComunicadoCard extends StatelessWidget {
  final ComunicadoProyecto comunicado;
  final VoidCallback onTap;

  const _ComunicadoCard({required this.comunicado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final isUnread = !comunicado.leido;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? _amber.withValues(alpha: isDark ? 0.08 : 0.05)
              : surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnread
                ? _amber.withValues(alpha: 0.35)
                : isDark
                    ? _green.withValues(alpha: 0.15)
                    : Colors.grey.shade200,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isDark
                        ? _amber.withValues(alpha: 0.15)
                        : const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.campaign_outlined,
                      color: _amber, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comunicado.titulo,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 11, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(comunicado.autor,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                          const SizedBox(width: 8),
                          const Icon(Icons.access_time_outlined,
                              size: 11, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(comunicado.fecha,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: const BoxDecoration(
                        color: _amber, shape: BoxShape.circle),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(comunicado.mensaje,
                style: const TextStyle(
                    fontSize: 12, color: Colors.grey, height: 1.5),
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
            if (comunicado.adjuntoUrl != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.attach_file_outlined,
                      size: 13, color: _green.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  const Text('Archivo adjunto disponible',
                      style: TextStyle(
                          fontSize: 11,
                          color: _green,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No se pudo cargar el servicio',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _green),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Reintentar', style: TextStyle(color: _green)),
          ),
        ],
      ),
    );
  }
}
