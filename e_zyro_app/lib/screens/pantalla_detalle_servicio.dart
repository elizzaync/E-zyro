import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/app_constants.dart';
import '../models/proyecto_models.dart';
import '../models/comunicado_models.dart';
import '../models/recepcion_models.dart';
import '../services/proyecto_service.dart';
import '../utils/app_notifiers.dart';
import '../utils/app_session.dart';
import '../utils/fase_servicio.dart';
import '../services/comunicado_service.dart';
import '../services/chat_service.dart';
import 'pantalla_informes_servicio.dart';
import '../services/prestamo_service.dart';
import 'pantalla_prestamos_servicio.dart';
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
  List<ReqRecepcion> _reqsRecepcion = [];
  bool _isLoading = true;
  bool _puedeFinalizar = false;
  bool _cambiandoEstado = false;
  late TabController _tabController;
  DateTime? _lastDetailLoad;

  // ── Tiempo real: WS del servicio para borrador y recepción ─────────────────
  ChatService? _eventosWs;
  Timer? _eventDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _checkRol();
    _load();
    _conectarEventos();
    pendientesEvidenciaNotifier.addListener(_onEvidenciaSync);
    syncCompletedNotifier.addListener(_onSyncCompleted);
  }

  @override
  void dispose() {
    pendientesEvidenciaNotifier.removeListener(_onEvidenciaSync);
    syncCompletedNotifier.removeListener(_onSyncCompleted);
    _eventDebounce?.cancel();
    _eventosWs?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  /// Abre una conexión WS al room del servicio para recibir eventos en vivo
  /// ('borrador_actualizado', 'requerimiento_actualizado') y refrescar el
  /// borrador y la recepción sin que el técnico tenga que recargar. Cierra la
  /// brecha anti-duplicidad: todos ven el borrador del equipo en tiempo real.
  Future<void> _conectarEventos() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    if (token.isEmpty || !mounted) return;
    final ws = ChatService();
    ws.connect('servicio/${widget.servicioId}', token);
    ws.eventos.listen(_onEventoServidor);
    _eventosWs = ws;
  }

  void _onEventoServidor(String tipo) {
    // Coalescer ráfagas de eventos en una sola recarga.
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 700), () {
      if (mounted) _reloadBorrador();
    });
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
      widget.service.getRequerimientosServicio(widget.servicioId),
    ]);
    if (!mounted) return;
    setState(() {
      _detalle = results[0] as ServicioDetalle?;
      _borrador = results[1] as Borrador;
      _reqsRecepcion = results[2] as List<ReqRecepcion>;
      _isLoading = false;
    });
    // Refrescar el badge de acciones offline pendientes.
    pendientesAccionNotifier.value =
        await widget.service.contarAccionesPendientes();
  }

  Future<void> _reloadDetalle() async {
    final data = await widget.service.getDetalleServicio(widget.servicioId);
    if (!mounted || data == null) return;
    setState(() => _detalle = data);
  }

  Future<void> _reloadBorrador() async {
    final results = await Future.wait([
      widget.service.getBorrador(widget.servicioId),
      widget.service.getRequerimientosServicio(widget.servicioId),
    ]);
    if (!mounted) return;
    setState(() {
      _borrador = results[0] as Borrador;
      _reqsRecepcion = results[1] as List<ReqRecepcion>;
    });
  }

  /// Recarga lo que afecta al tab Materiales: detalle (asignados/solicitados),
  /// borrador y requerimientos de recepción.
  Future<void> _reloadMateriales() async {
    await _reloadDetalle();
    await _reloadBorrador();
  }

  // ── Checklist de Preparación (Fase 1) — mismo criterio que la web ───────────
  List<String> get _motivosInicio {
    final d = _detalle;
    if (d == null) return const [];
    final m = <String>[];
    if (d.equipo.isEmpty) m.add('asignar el equipo técnico');
    if (d.procedimientos.isEmpty) {
      m.add('repartir las tareas del servicio');
    } else if (d.procedimientos.any((p) => (p.responsableId ?? '').isEmpty)) {
      m.add('asignar un responsable a todas las tareas');
    }
    final totalMat =
        d.materialesAsignados.length + d.materialesSolicitados.length;
    if (totalMat == 0 && _borrador.items.isEmpty) {
      m.add('elegir los materiales y herramientas');
    }
    if (_borrador.items.isNotEmpty) {
      m.add('enviar el borrador de materiales a Logística');
    }
    return m;
  }

  bool get _puedeIniciar => _motivosInicio.isEmpty;

  // Sub-pasos de la Fase 1 (mismos criterios que la web).
  bool get _prepEquipoListo => (_detalle?.equipo.isNotEmpty ?? false);
  bool get _prepTareasListo {
    final p = _detalle?.procedimientos ?? const [];
    return p.isNotEmpty && p.every((t) => (t.responsableId ?? '').isNotEmpty);
  }

  bool get _prepMaterialesListo {
    final d = _detalle;
    if (d == null) return false;
    final total = d.materialesAsignados.length + d.materialesSolicitados.length;
    return total > 0 && _borrador.items.isEmpty;
  }

  double _calcProgreso(List<ProcedimientoDetalle> procs) {
    if (procs.isEmpty) return 0;
    final done = procs.where((p) => p.estado == 'completado').length;
    return (done / procs.length) * 100;
  }

  // ── Toggle de tarea optimista (refleja al instante, revierte si falla) ──────
  Future<void> _toggleOptimista(ProcedimientoDetalle proc) async {
    final d = _detalle;
    if (d == null) return;
    if (d.estado == 'Completado') {
      _snack('El servicio está cerrado (solo lectura).', _amber);
      return;
    }
    final original = proc.estado;
    final nuevo = original == 'completado' ? 'pendiente' : 'completado';
    setState(() {
      proc.estado = nuevo;
      d.progreso = _calcProgreso(d.procedimientos);
    });
    final res =
        await widget.service.toggleProcedimiento(proc.id, nuevo, servicioId: d.id);
    if (!mounted) return;
    if (!res.ok) {
      setState(() {
        proc.estado = original;
        d.progreso = _calcProgreso(d.procedimientos);
      });
      _snack(res.errorMessage.isEmpty ? 'No se pudo actualizar la tarea' : res.errorMessage,
          _danger);
    } else if (res.queued) {
      _snack('Tarea actualizada · se sincronizará al reconectar', _amber);
    }
  }

  // ── Cambiar estado del servicio ─────────────────────────────────────────────
  Future<void> _cambiarEstado(String estado) async {
    if (_detalle == null || _cambiandoEstado) return;
    setState(() => _cambiandoEstado = true);
    final res = await widget.service.cambiarEstadoServicio(_detalle!.id, estado);
    if (!mounted) return;
    setState(() => _cambiandoEstado = false);
    if (res.ok) {
      await _reloadDetalle();
      _snack('Estado actualizado a ${_estadoLabel(estado)}', _green);
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo cambiar el estado' : res.errorMessage, _danger);
    }
  }

  // ── Iniciar servicio (Pendiente → En_Proceso) con checklist ─────────────────
  Future<void> _iniciarServicio() async {
    final d = _detalle;
    if (d == null || d.estado != 'Pendiente') return;
    final motivos = _motivosInicio;
    if (motivos.isNotEmpty) {
      _snack('No puedes iniciar aún. Falta: ${motivos.join(' · ')}.', _amber);
      return;
    }
    await _cambiarEstado('En_Proceso');
  }

  // ── Cancelar / reabrir servicio (solo jefe / admin) ─────────────────────────
  Future<void> _cancelarServicio() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar servicio'),
        content: const Text(
            '¿Seguro que deseas cancelar este servicio? Esta acción cambia su estado a Cancelado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _danger),
              child: const Text('Sí, cancelar')),
        ],
      ),
    );
    if (confirmar == true) await _cambiarEstado('Cancelado');
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
    final res = await widget.service.cambiarEstadoServicio(d.id, 'Completado');
    if (!mounted) return;
    if (!res.ok) {
      _snack(res.errorMessage.isEmpty ? 'No se pudo finalizar el servicio' : res.errorMessage, _danger);
      return;
    }
    await _reloadDetalle();
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
          // Informes del servicio (pre-informe / informe final en PDF).
          if (d != null)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
              tooltip: 'Informes del servicio',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PantallaInformesServicio(
                    servicioId: widget.servicioId,
                    estado: d.estado,
                  ),
                ),
              ),
            ),
          // Iniciar: solo en Pendiente. Bloqueado (gris) hasta cumplir checklist.
          if (d != null && d.estado == 'Pendiente' && !_cambiandoEstado)
            IconButton(
              icon: Icon(_puedeIniciar ? Icons.play_circle_outline : Icons.lock_outline,
                  size: 20),
              tooltip: _puedeIniciar
                  ? 'Iniciar servicio'
                  : 'Falta: ${_motivosInicio.join(' · ')}',
              color: _puedeIniciar ? _green : null,
              onPressed: _iniciarServicio,
            ),
          if (d != null &&
              (AppSession.i.isJefeOperaciones || AppSession.i.isAdmin))
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Editar servicio',
              onPressed: _editarServicio,
            ),
          // Finalizar: solo jefe/admin, al 100%.
          if (d != null && _puedeFinalizar && d.estado == 'En_Proceso')
            IconButton(
              icon: const Icon(Icons.task_alt_outlined, size: 20),
              tooltip: d.progreso >= 100
                  ? 'Finalizar y generar informe'
                  : 'Completa las tareas para finalizar',
              color: d.progreso >= 100 ? _green : null,
              onPressed: _finalizarServicio,
            ),
          // Menú de líder: cancelar / reabrir (acciones terminales protegidas).
          if (d != null &&
              _puedeFinalizar &&
              !_cambiandoEstado &&
              d.estado != 'Cancelado')
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'Más acciones',
              onSelected: (v) {
                if (v == 'cancelar') _cancelarServicio();
                if (v == 'reabrir') _cambiarEstado('En_Proceso');
              },
              itemBuilder: (_) => [
                if (d.estado != 'Cancelado' && d.estado != 'Completado')
                  const PopupMenuItem(
                      value: 'cancelar', child: Text('Cancelar servicio')),
                if (d.estado == 'Completado')
                  const PopupMenuItem(
                      value: 'reabrir', child: Text('Reabrir servicio')),
              ],
            ),
          // Badge de acciones offline pendientes de sincronizar.
          ValueListenableBuilder<int>(
            valueListenable: pendientesAccionNotifier,
            builder: (_, n, _) {
              if (n == 0) return const SizedBox.shrink();
              return Center(
                child: Tooltip(
                  message: '$n acción(es) sin sincronizar',
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_upload_outlined,
                            size: 14, color: _amber),
                        const SizedBox(width: 3),
                        Text('$n',
                            style: const TextStyle(
                                color: _amber,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              );
            },
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
                    const SizedBox(height: 10),
                    _FasesStepper(estado: d.estado, progreso: d.progreso),
                    if (d.estado == 'Pendiente') ...[
                      const SizedBox(height: 8),
                      _ChecklistPreparacion(
                        equipoListo: _prepEquipoListo,
                        tareasListo: _prepTareasListo,
                        materialesListo: _prepMaterialesListo,
                        puedeIniciar: _puedeIniciar,
                        motivos: _motivosInicio,
                        iniciando: _cambiandoEstado,
                        onIniciar: _iniciarServicio,
                      ),
                    ],
                    const SizedBox(height: 10),
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
                            onToggle: _toggleOptimista,
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
                            reqsRecepcion: _reqsRecepcion,
                            service: widget.service,
                            onChanged: _reloadMateriales,
                          ),
                          _NotasTab(
                            servicioId: d.id,
                            notasIniciales: d.notas,
                            service: widget.service,
                          ),
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

// ─── Stepper de 4 fases (Preparación · En sitio · Ejecución · Cierre) ─────────

class _FasesStepper extends StatelessWidget {
  final String estado;
  final double progreso;
  const _FasesStepper({required this.estado, required this.progreso});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          for (final f in fasesServicio) ...[
            Builder(builder: (_) {
              final clase = faseClase(f.n, estado, progreso);
              final done = clase == 'done';
              final active = clase == 'active';
              final color = (done || active) ? _green : muted;
              return Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 3,
                            color: f.n == 1
                                ? Colors.transparent
                                : (faseClase(f.n - 1, estado, progreso) != 'muted'
                                    ? _green
                                    : muted.withValues(alpha: 0.3)),
                          ),
                        ),
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: done
                                ? _green
                                : (active ? _green.withValues(alpha: 0.15) : Colors.transparent),
                            shape: BoxShape.circle,
                            border: Border.all(color: color, width: 2),
                          ),
                          child: done
                              ? const Icon(Icons.check, size: 13, color: Colors.white)
                              : Center(
                                  child: Text('${f.n}',
                                      style: TextStyle(
                                          color: color,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ),
                        ),
                        Expanded(
                          child: Container(
                            height: 3,
                            color: f.n == fasesServicio.length
                                ? Colors.transparent
                                : (done ? _green : muted.withValues(alpha: 0.3)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(f.nombre,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 9.5,
                            height: 1.1,
                            color: (done || active) ? null : muted,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w500)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ─── Checklist de Preparación (Fase 1) ────────────────────────────────────────

class _ChecklistPreparacion extends StatelessWidget {
  final bool equipoListo;
  final bool tareasListo;
  final bool materialesListo;
  final bool puedeIniciar;
  final bool iniciando;
  final List<String> motivos;
  final VoidCallback onIniciar;

  const _ChecklistPreparacion({
    required this.equipoListo,
    required this.tareasListo,
    required this.materialesListo,
    required this.puedeIniciar,
    required this.iniciando,
    required this.motivos,
    required this.onIniciar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: puedeIniciar
                ? _green.withValues(alpha: 0.35)
                : _amber.withValues(alpha: isDark ? 0.30 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.fact_check_outlined, size: 16, color: _amber),
              SizedBox(width: 6),
              Text('Fase 1 · Preparación',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          _PrepStep(n: 1, ok: equipoListo, label: 'Asignar equipo técnico'),
          _PrepStep(n: 2, ok: tareasListo, label: 'Repartir tareas (con responsable)'),
          _PrepStep(n: 3, ok: materialesListo, label: 'Elegir materiales y herramientas'),
          const SizedBox(height: 8),
          if (!puedeIniciar)
            Text('Falta: ${motivos.join(' · ')}.',
                style: const TextStyle(
                    color: _amber, fontSize: 11.5, fontWeight: FontWeight.w500))
          else
            const Text('Todo listo. Ya puedes iniciar el servicio.',
                style: TextStyle(
                    color: _green, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (puedeIniciar && !iniciando) ? onIniciar : null,
              icon: iniciando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(puedeIniciar ? Icons.play_arrow_rounded : Icons.lock_outline,
                      size: 18),
              label: Text(puedeIniciar ? 'Iniciar servicio' : 'Iniciar (bloqueado)',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    Theme.of(context).disabledColor.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrepStep extends StatelessWidget {
  final int n;
  final bool ok;
  final String label;
  const _PrepStep({required this.n, required this.ok, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: ok ? _green : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: ok ? _green : Colors.grey, width: 1.5),
            ),
            child: ok
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Center(
                    child: Text('$n',
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.w700)),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: ok ? null : Colors.grey,
                    fontWeight: ok ? FontWeight.w500 : FontWeight.w400)),
          ),
          if (ok) const Icon(Icons.check_circle, size: 14, color: _green),
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
  final void Function(ProcedimientoDetalle) onToggle;

  const _ProcedimientosTab({
    required this.procedimientos,
    required this.service,
    required this.onChanged,
    required this.onToggle,
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
        onToggle: onToggle,
      ),
    );
  }
}

class _ProcedimientoCard extends StatelessWidget {
  final ProcedimientoDetalle proc;
  final ProyectoService service;
  final Future<void> Function() onChanged;
  final void Function(ProcedimientoDetalle) onToggle;

  const _ProcedimientoCard({
    required this.proc,
    required this.service,
    required this.onChanged,
    required this.onToggle,
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
                onTap: () => onToggle(proc),
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
  final List<ReqRecepcion> reqsRecepcion;
  final ProyectoService service;
  final Future<void> Function() onChanged;

  const _MaterialesTab({
    required this.servicioId,
    required this.asignados,
    required this.solicitados,
    required this.borrador,
    required this.reqsRecepcion,
    required this.service,
    required this.onChanged,
  });

  @override
  State<_MaterialesTab> createState() => _MaterialesTabState();
}

class _MaterialesTabState extends State<_MaterialesTab> {
  bool _enviando = false;
  bool _consenso = false;
  String? _firmandoReqId;

  // Préstamos del servicio (chip de aviso si hay devoluciones sin confirmar)
  int _avisosPrestamoCount = 0;
  PrestamoService? _prestamoService;

  @override
  void initState() {
    super.initState();
    _initPrestamos();
  }

  Future<void> _initPrestamos() async {
    _prestamoService = await getPrestamoService();
    await _refrescarAvisosPrestamo();
  }

  Future<void> _refrescarAvisosPrestamo() async {
    if (_prestamoService == null) return;
    final avisos =
        await _prestamoService!.getAvisosServicio(widget.servicioId);
    if (!mounted) return;
    setState(() => _avisosPrestamoCount = avisos.length);
  }

  Future<void> _abrirPrestamos() async {
    // El nombre del servicio no viene en _MaterialesTab; usamos uno genérico.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPrestamosServicio(
          servicioId: widget.servicioId,
          servicioNombre: 'Servicio',
        ),
      ),
    );
    if (mounted) await _refrescarAvisosPrestamo();
  }

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
    final res = await widget.service.enviarBorrador(widget.servicioId);
    if (!mounted) return;
    setState(() => _enviando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            res.ok
                ? 'Solicitud enviada a Logística'
                : (res.errorMessage.isEmpty ? 'Error al enviar' : res.errorMessage),
            style: const TextStyle(color: Colors.white)),
        backgroundColor: res.ok ? _green : _danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (res.ok) {
      _consenso = false;
      await widget.onChanged();
    }
  }

  Future<void> _quitar(BorradorItem item) async {
    final res = await widget.service.removerItemBorrador(item.id);
    if (!mounted) return;
    if (res.ok) {
      await widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              res.errorMessage.isEmpty ? 'No se pudo quitar el ítem' : res.errorMessage,
              style: const TextStyle(color: Colors.white)),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Firma de recepción de materiales (HU-16, modelo híbrido) ───────────────
  // Cinema-seat: bloqueamos el lock ANTES de abrir la sheet para que ningún
  // otro técnico del equipo pueda firmar a la vez (los demás verán el banner
  // "X está firmando" en tiempo real por WS). Liberamos el lock si cancela o
  // si la firma falla. Si todo va bien, el endpoint /firmar libera el lock
  // automáticamente al hacer commit del nuevo estado 'aprobado'.
  Future<void> _firmarRecepcion(ReqRecepcion req) async {
    // 1) Tomar el lock
    final lock = await widget.service.bloquearFirmaRequerimiento(req.id);
    if (!mounted) return;
    if (!lock.ok) {
      // El backend devuelve detail='firmando_por:Juan Pérez' cuando otro tiene el lock.
      final quien = (lock.error ?? '').startsWith('firmando_por:')
          ? lock.error!.substring('firmando_por:'.length)
          : null;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          quien != null
              ? '$quien está firmando ahora. Espera unos segundos…'
              : 'No se pudo iniciar la firma. Reintenta en unos segundos.',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _amber,
        behavior: SnackBarBehavior.floating,
      ));
      // Refrescar para que la UI pinte el banner "X está firmando"
      await widget.onChanged();
      return;
    }

    // 2) Abrir la sheet de firma (con el lock tomado)
    final firmaUrl = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FirmaRecepcionSheet(req: req),
    );

    // 3) Si canceló (no devolvió firma), liberar el lock y salir
    if (firmaUrl == null || firmaUrl.isEmpty) {
      await widget.service.liberarFirmaRequerimiento(req.id);
      return;
    }

    // 4) Enviar la firma — el backend libera el lock al hacer commit
    setState(() => _firmandoReqId = req.id);
    final res = await widget.service
        .firmarRequerimiento(req.id, firmaUrl, servicioId: widget.servicioId);
    if (!mounted) return;
    setState(() => _firmandoReqId = null);

    // 5) Si el POST online falló, liberamos el lock manualmente (offline
    // queda encolado: NO liberamos para no soltar el "asiento" durante la
    // ventana hasta el reintento).
    if (!res.ok && !res.queued) {
      await widget.service.liberarFirmaRequerimiento(req.id);
      if (!mounted) return;
    }

    final String msg;
    final Color color;
    if (res.queued) {
      msg = 'Firma guardada · se enviará a Logística al reconectar';
      color = _amber;
    } else if (res.ok) {
      msg = 'Recepción firmada · Logística fue notificada';
      color = _green;
    } else {
      msg = res.errorMessage.isEmpty ? 'No se pudo registrar la firma' : res.errorMessage;
      color = _danger;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Solo recargar si se confirmó online (offline el servidor aún no cambió).
    if (res.ok && !res.queued) await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final borrador = widget.borrador;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
          children: [
            // ── Equipos y herramientas (préstamos FASE 5) ─────────────────────
            _EquiposHerramientasCard(
              avisosCount: _avisosPrestamoCount,
              onTap: _abrirPrestamos,
            ),
            const SizedBox(height: 16),

            // ── Recepción de materiales (firma HU-16) ─────────────────────────
            if (widget.reqsRecepcion.isNotEmpty) ...[
              const _SectionTitle('Recepción de Materiales',
                  Icons.assignment_turned_in_outlined, _green),
              const SizedBox(height: 8),
              ...widget.reqsRecepcion.map((req) => _RecepcionCard(
                    req: req,
                    firmando: _firmandoReqId == req.id,
                    onFirmar: () => _firmarRecepcion(req),
                  )),
              const SizedBox(height: 20),
            ],

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
              const SizedBox(height: 10),
              // Aviso anti-duplicidad: solo un técnico debe consolidar y enviar.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _amber.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: _amber),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '¡Atención equipo! Solo un técnico debe consolidar y enviar '
                        'la solicitud para evitar pedidos duplicados. Verifiquen entre '
                        'todos antes de confirmar.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _consenso = !_consenso),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _consenso,
                        onChanged: (v) => setState(() => _consenso = v ?? false),
                        activeColor: _green,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      const Expanded(
                        child: Text(
                          'Confirmo que el equipo está de acuerdo con esta solicitud en lote',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_enviando || !_consenso) ? null : _enviarBorrador,
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
              ...widget.asignados.map((m) =>
                  _MaterialCard(item: m, onEdit: () => _editarMaterial(m))),
              const SizedBox(height: 16),
            ],
            if (widget.solicitados.isNotEmpty) ...[
              const _SectionTitle(
                  'Materiales Solicitados', Icons.pending_outlined, _amber),
              const SizedBox(height: 8),
              ...widget.solicitados.map((m) =>
                  _MaterialCard(item: m, onEdit: () => _editarMaterial(m))),
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

  // Editar cantidad de un material ya asignado/solicitado (si aún es editable).
  Future<void> _editarMaterial(ItemMaterial m) async {
    if (m.estadoReq == 'entregado' || m.estadoReq == 'aprobado') {
      _snack('Este ítem ya fue ${m.estadoReq} y no se puede editar.', _amber);
      return;
    }
    final cantCtrl = TextEditingController(text: '${m.cantidad}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m.nombre),
        content: TextField(
          controller: cantCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Cantidad'),
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
    final cant = int.tryParse(cantCtrl.text.trim()) ?? m.cantidad;
    final res = await widget.service
        .actualizarReqDetalle(m.id, cantidad: cant < 1 ? 1 : cant);
    if (!mounted) return;
    if (res.ok) {
      await widget.onChanged();
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo editar' : res.errorMessage, _danger);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
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
    final res = await widget.service.actualizarReqDetalle(
      item.id,
      cantidad: cant < 1 ? 1 : cant,
      nombre: item.esNuevo ? nombreCtrl.text.trim() : null,
      especificacion: item.esNuevo ? especCtrl.text.trim() : null,
    );
    if (!mounted) return;
    if (res.ok) {
      await widget.onChanged();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              res.errorMessage.isEmpty ? 'No se pudo editar el ítem' : res.errorMessage,
              style: const TextStyle(color: Colors.white)),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
  int _modo = 0; // 0 = catálogo · 1 = equipos/herramientas · 2 = compra externa
  bool _guardando = false;

  // Catálogo
  final _busquedaCtrl = TextEditingController();
  List<MaterialBusqueda> _resultados = [];
  MaterialBusqueda? _elegido;
  int _cantidad = 1;
  Timer? _debounce;

  // Equipos / Herramientas
  final _busquedaEqCtrl = TextEditingController();
  List<EquipoBusqueda> _resultadosEq = [];
  EquipoBusqueda? _equipoElegido;
  int _cantEquipo = 1;
  Timer? _debounceEq;

  // Compra externa
  final _nombreCtrl = TextEditingController();
  final _especCtrl = TextEditingController();
  String _unidad = 'Unidades';
  int _cantExterno = 1;

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceEq?.cancel();
    _busquedaCtrl.dispose();
    _busquedaEqCtrl.dispose();
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

  void _onSearchEq(String q) {
    _debounceEq?.cancel();
    _debounceEq = Timer(const Duration(milliseconds: 350), () async {
      final r = await widget.service.buscarEquipos(q);
      if (mounted) setState(() => _resultadosEq = r);
    });
  }

  Future<void> _agregarEquipo() async {
    final eq = _equipoElegido;
    if (eq == null) return;
    setState(() => _guardando = true);
    final etiqueta = eq.esHerramienta ? 'Herramienta' : 'Equipo';
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: null,
      nombre: eq.nombre,
      unidad: 'Unidades',
      cantidad: _cantEquipo,
      especificacion: '[$etiqueta] ${eq.nombre} del inventario',
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
  }

  void _snackError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: _danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _agregarCatalogo() async {
    if (_elegido == null) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: _elegido!.id,
      nombre: _elegido!.nombre,
      unidad: _elegido!.unidad,
      cantidad: _cantidad,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
    }
  }

  Future<void> _agregarExterno() async {
    final nombre = _nombreCtrl.text.trim();
    final espec = _especCtrl.text.trim();
    if (nombre.isEmpty || espec.isEmpty) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarItemBorrador(
      widget.servicioId,
      materialId: null,
      nombre: nombre,
      unidad: _unidad,
      cantidad: _cantExterno,
      especificacion: espec,
    );
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      await widget.onAgregado();
      if (mounted) Navigator.pop(context);
    } else {
      _snackError(res.errorMessage.isEmpty ? 'No se pudo agregar' : res.errorMessage);
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
          const Text('Solicitar al Requerimiento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // Toggle: catálogo / equipos-herramientas / compra externa
          Row(
            children: [
              _ToggleChip(
                label: 'Material',
                selected: _modo == 0,
                onTap: () => setState(() => _modo = 0),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Equipo/Herr.',
                selected: _modo == 1,
                onTap: () => setState(() => _modo = 1),
              ),
              const SizedBox(width: 6),
              _ToggleChip(
                label: 'Compra ext.',
                selected: _modo == 2,
                onTap: () => setState(() => _modo = 2),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_modo == 0)
            ..._buildCatalogo()
          else if (_modo == 1)
            ..._buildEquipos()
          else
            ..._buildExterno(),
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

  List<Widget> _buildEquipos() {
    return [
      TextField(
        controller: _busquedaEqCtrl,
        onChanged: _onSearchEq,
        decoration: InputDecoration(
          hintText: 'Buscar equipo o herramienta (mín. 2 letras)...',
          prefixIcon: const Icon(Icons.handyman_outlined),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      if (_equipoElegido == null && _resultadosEq.isNotEmpty)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: ListView(
            shrinkWrap: true,
            children: _resultadosEq
                .map((e) => ListTile(
                      dense: true,
                      title: Text(e.nombre),
                      subtitle: Text(
                          '${e.esHerramienta ? 'Herramienta' : 'Equipo'} · Disponibles: ${e.cantidad}'),
                      onTap: () => setState(() {
                        _equipoElegido = e;
                        _busquedaEqCtrl.text = e.nombre;
                        _resultadosEq = [];
                        _cantEquipo = 1;
                      }),
                    ))
                .toList(),
          ),
        ),
      if (_equipoElegido != null) ...[
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_equipoElegido!.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                        '${_equipoElegido!.esHerramienta ? 'Herramienta' : 'Equipo'} · Disp.: ${_equipoElegido!.cantidad}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              ),
              _QtyStepper(
                value: _cantEquipo,
                onChanged: (v) => setState(() => _cantEquipo = v),
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed:
              (_equipoElegido == null || _guardando) ? null : _agregarEquipo,
          style: ElevatedButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Añadir al Borrador',
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
  final VoidCallback? onEdit;
  const _MaterialCard({required this.item, this.onEdit});

  // No se edita lo ya entregado o aprobado por Logística.
  bool get _editable =>
      item.estadoReq != 'entregado' && item.estadoReq != 'aprobado';

  Color _estadoColor() => switch (item.estadoReq) {
        'entregado' => _green,
        'aprobado' => const Color(0xFF3B82F6),
        'rechazado' => _danger,
        _ => _amber,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final tappable = _editable && onEdit != null;

    return InkWell(
      onTap: tappable ? onEdit : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.nombre,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(item.estadoReq,
                      style: TextStyle(
                          color: _estadoColor(),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Text('${item.cantidad} ${item.unidad}',
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            if (tappable) ...[
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Recepción de materiales: tarjeta + firma (HU-16) ─────────────────────────

class _RecepcionCard extends StatelessWidget {
  final ReqRecepcion req;
  final bool firmando;
  final VoidCallback onFirmar;

  const _RecepcionCard({
    required this.req,
    required this.firmando,
    required this.onFirmar,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    // MODELO HÍBRIDO — flujo: comprando → listo → aprobado → entregado.
    //   'comprando'  ámbar  → sin stock, en proceso de compra
    //   'listo'      verde  → disponible, técnico puede firmar
    //   'aprobado'   azul   → técnico firmó, pendiente cierre administrativo
    //   'entregado'  verde  → logística cerró contablemente (final completo)
    const kBlueRecepcion = Color(0xFF3B82F6);
    final (String titulo, Color colorEstado, IconData iconoEstado) =
        req.cerrado
            ? ('Cerrado por logística', _green, Icons.verified_outlined)
            : req.recibido
                ? ('Recibido · pendiente cierre log', kBlueRecepcion,
                   Icons.assignment_turned_in_outlined)
                : req.enCompra
                    ? ('En compra · llegará pronto', _amber,
                       Icons.shopping_cart_outlined)
                    : ('Listo para recibir', _green,
                       Icons.inventory_2_outlined);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorEstado.withValues(alpha: isDark ? 0.30 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconoEstado, size: 16, color: colorEstado),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: colorEstado.withValues(alpha: isDark ? 1 : 0.9)),
                ),
              ),
              Text('REQ ${req.id.substring(0, req.id.length >= 6 ? 6 : req.id.length).toUpperCase()}',
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 10, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: req.itemsValidos
                .map((it) => Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${it.nombre} × ${it.cantidadEfectiva} ${it.unidad}'
                        '${it.esCompra ? ' (compra)' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
          Text('Solicitado por ${req.solicitanteNombre}${req.fecha != null ? ' · ${req.fecha}' : ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
          const SizedBox(height: 12),
          if (req.cerrado)
            Row(
              children: const [
                Icon(Icons.verified, size: 16, color: _green),
                SizedBox(width: 6),
                Text('Cerrado · doble firma archivada',
                    style: TextStyle(
                        color: _green, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            )
          else if (req.recibido)
            Row(
              children: const [
                Icon(Icons.check_circle, size: 16, color: kBlueRecepcion),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Firmado por el equipo · esperando cierre de logística',
                    style: TextStyle(
                        color: kBlueRecepcion,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          else if (req.enCompra)
            Row(
              children: const [
                Icon(Icons.schedule, size: 16, color: _amber),
                SizedBox(width: 6),
                Expanded(
                  child: Text('Sin stock · en proceso de compra',
                      style: TextStyle(
                          color: _amber,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            )
          else ...[
            // Banner "X está firmando ahora" — actualizado en tiempo real por WS.
            if (req.hayAlguienFirmando && !firmando) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _amber.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.draw_outlined, size: 14, color: _amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${req.firmandoPorNombre} está firmando ahora…',
                      style: const TextStyle(
                          fontSize: 11.5, color: _amber, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (firmando || req.hayAlguienFirmando) ? null : onFirmar,
                icon: firmando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.draw_outlined, size: 16),
                label: Text(
                    firmando
                        ? 'Firmando...'
                        : (req.hayAlguienFirmando
                            ? 'Otro técnico está firmando'
                            : 'Firmar recepción'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet de firma de recepción. Reutiliza el patrón de firma de
/// Trámites/Permisos: dibujar con el dedo, usar la firma guardada en la nube,
/// o subir una imagen. Devuelve la firma como URL (nube) o data-url base64.
class _FirmaRecepcionSheet extends StatefulWidget {
  final ReqRecepcion req;
  const _FirmaRecepcionSheet({required this.req});

  @override
  State<_FirmaRecepcionSheet> createState() => _FirmaRecepcionSheetState();
}

class _FirmaRecepcionSheetState extends State<_FirmaRecepcionSheet> {
  late final SignatureController _controller;
  String? _firmaGuardadaUrl;
  bool _usarGuardada = false;
  bool _cargandoGuardada = true;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3.0,
      exportBackgroundColor: Colors.white,
    );
    _cargarFirmaGuardada();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _cargarFirmaGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token') ?? '';
      final r = await http.get(
        Uri.parse('${AppConstants.baseUrl}/permisos/mi-firma'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final url = data['data']?['url_firma'] as String?;
        if (url != null && url.isNotEmpty && mounted) {
          setState(() {
            _firmaGuardadaUrl = url;
            _usarGuardada = true;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoGuardada = false);
    }
  }

  Future<void> _confirmar() async {
    // Usar la firma guardada en la nube → enviar esa URL.
    if (_usarGuardada && _firmaGuardadaUrl != null) {
      Navigator.pop(context, _firmaGuardadaUrl);
      return;
    }
    // Firma dibujada → exportar PNG como data-url base64.
    if (_controller.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dibuja tu firma o usa la guardada'),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final bytes = await _controller.toPngBytes();
    if (bytes == null || !mounted) return;
    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
    Navigator.pop(context, dataUrl);
  }

  Future<void> _subirGaleria() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    final Uint8List bytes = await image.readAsBytes();
    final dataUrl = 'data:image/png;base64,${base64Encode(bytes)}';
    if (mounted) Navigator.pop(context, dataUrl);
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    final usandoGuardada = _usarGuardada && _firmaGuardadaUrl != null;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
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
            Row(
              children: [
                const Icon(Icons.draw_outlined, color: _green, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Firmar recepción de materiales',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: muted, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('Recibe: los ${widget.req.itemsValidos.length} ítem(s) aprobados',
                style: TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 14),

            // Toggle: usar guardada / dibujar nueva (si hay guardada)
            if (_cargandoGuardada)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _green),
                ),
              )
            else if (_firmaGuardadaUrl != null) ...[
              Row(
                children: [
                  _firmaTab('Usar guardada', _usarGuardada,
                      () => setState(() => _usarGuardada = true)),
                  const SizedBox(width: 8),
                  _firmaTab('Dibujar nueva', !_usarGuardada,
                      () => setState(() => _usarGuardada = false)),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Lienzo o preview de firma guardada
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300, width: 2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: usandoGuardada
                    ? Image.network(_firmaGuardadaUrl!, fit: BoxFit.contain)
                    : Signature(
                        controller: _controller,
                        backgroundColor: Colors.white,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            if (!usandoGuardada)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Firma en el recuadro con tu dedo',
                      style: TextStyle(color: muted, fontSize: 12)),
                  TextButton.icon(
                    onPressed: () => _controller.clear(),
                    icon: Icon(Icons.refresh, size: 15, color: muted),
                    label: Text('Limpiar',
                        style: TextStyle(color: muted, fontSize: 13)),
                  ),
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _subirGaleria,
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Galería'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: muted,
                      side: BorderSide(color: Colors.grey.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _confirmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Confirmar firma y notificar',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _firmaTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _green : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? _green : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? Colors.white : Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ─── Tab: Notas (CRUD) ────────────────────────────────────────────────────────

class _NotasTab extends StatefulWidget {
  final String servicioId;
  final List<NotaSeguimiento> notasIniciales;
  final ProyectoService service;

  const _NotasTab({
    required this.servicioId,
    required this.notasIniciales,
    required this.service,
  });

  @override
  State<_NotasTab> createState() => _NotasTabState();
}

class _NotasTabState extends State<_NotasTab> {
  final _nuevaCtrl = TextEditingController();
  List<NotaServicio> _notas = [];
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Semilla inmediata desde el detalle (sin permisos), luego refresco real.
    _notas = widget.notasIniciales
        .map((n) => NotaServicio(
              id: n.id,
              descripcion: n.texto,
              autor: n.autor,
              fecha: n.fecha,
              puedeEditar: false,
            ))
        .toList();
    _cargar();
  }

  @override
  void dispose() {
    _nuevaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final data = await widget.service.getNotasServicio(widget.servicioId);
    if (!mounted) return;
    setState(() {
      _notas = data;
      _cargando = false;
    });
  }

  Future<void> _agregar() async {
    final texto = _nuevaCtrl.text.trim();
    if (texto.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    final res = await widget.service.agregarNota(widget.servicioId, texto);
    if (!mounted) return;
    setState(() => _guardando = false);
    if (res.ok) {
      _nuevaCtrl.clear();
      FocusScope.of(context).unfocus();
      if (res.queued) {
        _snack('Nota guardada · se enviará al reconectar', _amber);
      } else {
        await _cargar();
      }
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo agregar la nota' : res.errorMessage, _danger);
    }
  }

  Future<void> _editar(NotaServicio n) async {
    final ctrl = TextEditingController(text: n.descripcion);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar nota'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Texto de la nota…'),
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
    final texto = ctrl.text.trim();
    if (texto.isEmpty) return;
    final res = await widget.service.actualizarNota(n.id, texto);
    if (!mounted) return;
    if (res.ok) {
      if (res.queued) {
        _snack('Edición guardada · se enviará al reconectar', _amber);
      } else {
        await _cargar();
      }
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo actualizar la nota' : res.errorMessage, _danger);
    }
  }

  Future<void> _eliminar(NotaServicio n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar nota'),
        content: const Text('¿Seguro que deseas eliminar esta nota?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _danger),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await widget.service.eliminarNota(n.id);
    if (!mounted) return;
    if (res.ok) {
      if (res.queued) {
        setState(() => _notas.removeWhere((x) => x.id == n.id));
        _snack('Nota eliminada · se sincronizará al reconectar', _amber);
      } else {
        await _cargar();
      }
    } else {
      _snack(res.errorMessage.isEmpty ? 'No se pudo eliminar la nota' : res.errorMessage, _danger);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Column(
      children: [
        // Campo de nueva nota
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _nuevaCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Observación, mejora o recordatorio…',
                    filled: true,
                    fillColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _guardando ? null : _agregar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: _guardando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _cargando
              ? const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(_green)))
              : _notas.isEmpty
                  ? _EmptyTab(
                      icon: Icons.notes_outlined,
                      label: 'Sin notas de seguimiento')
                  : RefreshIndicator(
                      color: _green,
                      onRefresh: _cargar,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _notas.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, i) => _NotaCard(
                          nota: _notas[i],
                          surface: surface,
                          onEdit: () => _editar(_notas[i]),
                          onDelete: () => _eliminar(_notas[i]),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}

class _NotaCard extends StatelessWidget {
  final NotaServicio nota;
  final Color surface;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NotaCard({
    required this.nota,
    required this.surface,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                child: const Icon(Icons.person_outline, size: 14, color: _green),
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
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11)),
                  ],
                ),
              ),
              if (nota.puedeEditar) ...[
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined,
                        size: 18, color: Colors.grey),
                  ),
                ),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline, size: 18, color: _danger),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(nota.descripcion,
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
                              final navigator = Navigator.of(ctx);
                              final ok = await _service?.crearComunicado(
                                    proyectoId: widget.proyectoId,
                                    titulo: titulo,
                                    mensaje: mensaje,
                                  ) ??
                                  false;
                              if (!mounted) return;
                              navigator.pop();
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

// ─── Card de acceso a Equipos y Herramientas (FASE 5) ────────────────────────
// Reemplaza la antigua "Solicitar materiales" desde pantalla_logistica: ahora
// los préstamos viven vinculados al servicio.
class _EquiposHerramientasCard extends StatelessWidget {
  final int avisosCount;
  final VoidCallback onTap;
  const _EquiposHerramientasCard({
    required this.avisosCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final hayAvisos = avisosCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: hayAvisos
              ? Border.all(color: _amber.withValues(alpha: 0.5), width: 1.5)
              : (isDark
                  ? Border.all(color: Colors.white.withValues(alpha: 0.08))
                  : null),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2)),
                ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _green.withValues(alpha: isDark ? 0.15 : 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.handyman_outlined,
                color: _green, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Equipos y herramientas',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                SizedBox(height: 2),
                Text(
                    'Solicita y devuelve equipos para este servicio',
                    style: TextStyle(color: Colors.grey, fontSize: 11.5)),
              ],
            ),
          ),
          if (hayAvisos)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _amber.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, size: 12, color: _amber),
                const SizedBox(width: 4),
                Text('$avisosCount sin confirmar',
                    style: const TextStyle(
                        color: _amber,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ]),
      ),
    );
  }
}

