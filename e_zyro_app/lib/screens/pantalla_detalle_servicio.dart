import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../core/app_constants.dart';
import '../models/intervencion_models.dart';
import '../models/proyecto_models.dart';
import '../models/comunicado_models.dart';
import '../models/recepcion_models.dart';
import '../services/intervencion_service.dart';
import '../services/proyecto_service.dart';
import '../utils/app_notifiers.dart';
import '../utils/app_session.dart';
import '../utils/fase_servicio.dart';
import '../utils/informe_general_config.dart';
import '../utils/ui_insets.dart';
import '../services/comunicado_service.dart';
import '../services/chat_service.dart';
import 'pantalla_informes_servicio.dart';
import '../services/prestamo_service.dart';
import '../widgets/firma_sheet.dart';
import 'pantalla_prestamos_servicio.dart';
import '../services/fcm_flutter_service.dart';
import '../utils/api_provider.dart';
import '../pdf/pdf_service.dart';
import '../pdf/pdf_preview_screen.dart';
import 'pantalla_chat.dart';
import 'pantalla_asignacion_servicio.dart';
import 'pantalla_crear_servicio.dart';
import 'pantalla_intervencion_equipo.dart';

part 'detalle_servicio/tab_procedimientos.dart';
part 'detalle_servicio/header.dart';
part 'detalle_servicio/tab_tareas.dart';
part 'detalle_servicio/tab_equipo.dart';
part 'detalle_servicio/tab_materiales.dart';
part 'detalle_servicio/materiales_solicitar.dart';
part 'detalle_servicio/materiales_recepcion.dart';
part 'detalle_servicio/tab_notas.dart';
part 'detalle_servicio/tab_comunicados.dart';
part 'detalle_servicio/tab_equipos_intervenidos.dart';
part 'detalle_servicio/shared.dart';

const _green = Color(0xFF8FD11B);
const _amber = Color(0xFFF59E0B);
const _danger = Color(0xFFEF4444);

/// Vista de SOLO LECTURA para usuarios NO designados en el servicio: muestra la
/// cabecera básica (nombre, estado, fechas, tareas y equipo designado) sin
/// cargar los datos de trabajo (materiales/procedimientos/evidencias).
/// Se usa cuando el backend responde con `acceso_completo=false`.
class _VistaServicioBasica extends StatelessWidget {
  final ServicioDetalle detalle;
  const _VistaServicioBasica({required this.detalle});

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

  Color _tareaColor(String estado) => switch (estado) {
        'completado' => _green,
        'en_proceso' => const Color(0xFF3B82F6),
        'bloqueado' => _danger,
        _ => _amber,
      };

  @override
  Widget build(BuildContext context) {
    final d = detalle;
    final scheme = Theme.of(context).colorScheme;
    final lider = d.equipo
        .where((m) => m.rolProyecto == 'Líder del Servicio')
        .cast<MiembroEquipo?>()
        .firstWhere((_) => true, orElse: () => null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _amber.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _amber.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 20, color: _amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No estás designado en este servicio. Solo puedes ver su '
                  'información básica.',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          d.tipoServicio,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(_estadoLabel, _statusColor),
            if (d.inspeccionEquiposActiva)
              _chip('Mantenimiento vinculado', const Color(0xFF3B82F6)),
          ],
        ),
        const SizedBox(height: 16),
        _card(
          scheme,
          children: [
            _fila(Icons.event_outlined, 'Fecha inicio',
                d.fechaInicio ?? d.fechaStr),
            _fila(Icons.place_outlined, 'Lugar',
                d.ubicacion.isEmpty ? '—' : d.ubicacion),
            _fila(Icons.apartment_outlined, 'Cliente', d.cliente),
            if (lider != null)
              _fila(Icons.badge_outlined, 'Líder del servicio',
                  '${lider.nombre} ${lider.apellido}'.trim()),
          ],
        ),
        const SizedBox(height: 16),
        _seccionTitulo('Tareas', Icons.assignment_outlined),
        const SizedBox(height: 8),
        d.tareas.isEmpty
            ? _vacio('Sin tareas visibles para ti en este servicio.')
            : _card(
                scheme,
                children: d.tareas
                    .map((t) => _filaTarea(t, scheme))
                    .toList(),
              ),
        const SizedBox(height: 16),
        _seccionTitulo('Equipo designado', Icons.groups_outlined),
        const SizedBox(height: 8),
        d.equipo.isEmpty
            ? _vacio('Aún no hay personal designado en este servicio.')
            : _card(
                scheme,
                children: d.equipo
                    .map((m) => _filaMiembro(m, scheme))
                    .toList(),
              ),
      ],
    );
  }

  Widget _seccionTitulo(String texto, IconData icono) => Row(
        children: [
          Icon(icono, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          Text(texto,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
        ],
      );

  Widget _card(ColorScheme scheme, {required List<Widget> children}) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(children: children),
      );

  Widget _vacio(String texto) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(texto, style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
      );

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
      );

  Widget _fila(IconData icono, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 17, color: Colors.grey),
            const SizedBox(width: 10),
            SizedBox(
              width: 108,
              child: Text(label,
                  style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
            ),
            Expanded(
              child: Text(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  Widget _filaTarea(TareaDetalle t, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(Icons.circle, size: 9, color: _tareaColor(t.estado)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(t.nombre,
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            _chip(t.estado.replaceAll('_', ' '), _tareaColor(t.estado)),
          ],
        ),
      );

  Widget _filaMiembro(MiembroEquipo m, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: scheme.surfaceContainerHighest,
              backgroundImage: m.fotoUrl.isNotEmpty ? CachedNetworkImageProvider(m.fotoUrl) : null,
              child: m.fotoUrl.isEmpty
                  ? Text(
                      m.nombre.isNotEmpty ? m.nombre[0].toUpperCase() : '?',
                      style: TextStyle(fontWeight: FontWeight.bold, color: scheme.onSurfaceVariant),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${m.nombre} ${m.apellido}'.trim(),
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  Text(m.cargo.isEmpty ? 'Sin cargo' : m.cargo,
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                ],
              ),
            ),
            _chip(m.rolProyecto, _green),
          ],
        ),
      );
}

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
    final detalle = await widget.service.getDetalleServicio(widget.servicioId);
    var borrador = const Borrador(items: []);
    var reqs = <ReqRecepcion>[];
    // Sin designación (vista básica): no se piden borrador/requerimientos —
    // dependen de endpoints de Logística a los que Técnico/Jefe de Operaciones
    // sin designación no tienen acceso, y no aplican a una vista de solo lectura.
    if (detalle?.accesoCompleto ?? true) {
      final results = await Future.wait([
        widget.service.getBorrador(widget.servicioId),
        widget.service.getRequerimientosServicio(widget.servicioId),
      ]);
      borrador = results[0] as Borrador;
      reqs = results[1] as List<ReqRecepcion>;
    }
    if (!mounted) return;
    setState(() {
      _detalle = detalle;
      _borrador = borrador;
      _reqsRecepcion = reqs;
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
    if (!(_detalle?.accesoCompleto ?? true)) return;
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
    if (d.tareas.isEmpty) {
      m.add('repartir las tareas del servicio');
    } else if (d.tareas.any((t) => (t.responsableId ?? '').isEmpty)) {
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
    final t = _detalle?.tareas ?? const [];
    return t.isNotEmpty && t.every((x) => (x.responsableId ?? '').isNotEmpty);
  }

  bool get _prepMaterialesListo {
    final d = _detalle;
    if (d == null) return false;
    final total = d.materialesAsignados.length + d.materialesSolicitados.length;
    return total > 0 && _borrador.items.isEmpty;
  }

  // ── Fases operativas (En sitio / Ejecución / Cierre) basadas en TAREAS ──────
  // El flujo lo controla el cronograma de tareas, no los procedimientos.
  double get _progresoTareas {
    final t = _detalle?.tareas ?? const [];
    if (t.isEmpty) return 0;
    final done = t.where((x) => x.estado == 'completado').length;
    return done / t.length * 100;
  }

  bool get _todasTareasCompletas {
    // Avance por tareas: el servicio puede cerrarse cuando no quedan tareas
    // pendientes. Un servicio sin cronograma (sin tareas) también puede cerrarse.
    final t = _detalle?.tareas ?? const [];
    return t.every((x) => x.estado == 'completado');
  }

  bool _activandoInspeccion = false;

  /// Solo el Jefe de Operaciones (o Admin) controla las transiciones de fase.
  bool get _esJefeOperaciones =>
      AppSession.i.isJefeOperaciones || AppSession.i.isAdmin;

  // ── Marcar EN SITIO (Pendiente → En_Proceso), solo jefe de operaciones ──────
  Future<void> _marcarEnSitio() async {
    final d = _detalle;
    if (d == null || d.estado != 'Pendiente') return;
    if (!_esJefeOperaciones) {
      _snack('Solo el Jefe de Operaciones puede marcar EN SITIO.', _amber);
      return;
    }
    final motivos = _motivosInicio;
    if (motivos.isNotEmpty) {
      _snack('No puedes iniciar aún. Falta: ${motivos.join(' · ')}.', _amber);
      return;
    }
    await _cambiarEstado('En_Proceso');
  }

  // ── Activar inspección de equipos en un servicio que aún no la tiene ─────────
  // Permite habilitar "Equipos Intervenidos" desde el detalle (p.ej. servicios
  // creados por carga masiva con el flag en false) sin entrar al formulario de
  // edición. El backend bloquea editar a Técnico y da 409 en servicios cerrados,
  // por eso el botón solo se muestra a Jefe de Operaciones en servicios abiertos.
  Future<void> _activarInspeccionEquipos() async {
    final d = _detalle;
    if (d == null || d.inspeccionEquiposActiva || d.esCerrado) return;
    if (!_esJefeOperaciones) {
      _snack('Solo el Jefe de Operaciones puede activar la inspección de equipos.', _amber);
      return;
    }
    setState(() => _activandoInspeccion = true);
    final ok = await widget.service
        .actualizarServicio(d.id, {'tiene_equipos_intervenidos': true});
    if (!mounted) return;
    setState(() => _activandoInspeccion = false);
    if (ok) {
      await _load(); // recarga → aparece el botón de Equipos Intervenidos
    } else {
      _snack('No se pudo activar. Si el servicio no es tuyo, edítalo con justificación.', _danger);
    }
  }

  // ── Cerrar servicio (En_Proceso → Completado) cuando todas las tareas listas ─
  Future<void> _cerrarServicio() async {
    final d = _detalle;
    if (d == null || d.estado != 'En_Proceso') return;
    if (!_esJefeOperaciones) {
      _snack('Solo el Jefe de Operaciones puede cerrar el servicio.', _danger);
      return;
    }
    if (!_todasTareasCompletas) {
      _snack('Marca todas las tareas antes de cerrar el servicio.', _amber);
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar servicio'),
        content: const Text(
            '¿Confirmas el cierre del servicio? Se generará el pre-informe de conformidad y el servicio quedará en solo lectura.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: _green),
              child: const Text('Sí, cerrar',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmar != true) return;
    await _finalizarServicio();
  }

  // ── Toggle de tarea (cronograma) — no afecta el avance del servicio ─────────
  Future<void> _toggleTareaOptimista(TareaDetalle tarea) async {
    final d = _detalle;
    if (d == null) return;
    if (d.esCerrado) {
      _snack(
          d.esTerminado
              ? 'Servicio terminado — solo lectura'
              : 'El servicio está cancelado (solo lectura).',
          _amber);
      return;
    }
    final original = tarea.estado;
    final nuevo = original == 'completado' ? 'pendiente' : 'completado';
    setState(() => tarea.estado = nuevo);
    final res = await widget.service.toggleTarea(tarea.id, nuevo);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => tarea.estado = original);
      _snack(
          res.errorMessage.isEmpty
              ? 'No se pudo actualizar la tarea'
              : res.errorMessage,
          _danger);
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
    if (!_todasTareasCompletas) {
      _snack('Marca todas las tareas antes de cerrar el servicio', _amber);
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
    final detalle = _detalle ?? d;
    final bytes = await PdfService.preInformeServicio(detalle);
    if (!mounted) return;
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo:
          'pre-informe-${detalle.cliente.replaceAll(' ', '-')}-${DateTime.now().millisecondsSinceEpoch}.pdf',
      titulo: 'Pre-Informe de Conformidad',
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
    // Sin acceso completo (no designado) → cabecera de solo lectura, sin acciones.
    final completo = d?.accesoCompleto ?? true;
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
          if (d != null && completo)
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
          // EN SITIO: solo en Pendiente, solo jefe de operaciones, tras checklist.
          if (d != null &&
              completo &&
              d.estado == 'Pendiente' &&
              !_cambiandoEstado &&
              _esJefeOperaciones)
            IconButton(
              icon: Icon(_puedeIniciar ? Icons.location_on_outlined : Icons.lock_outline,
                  size: 20),
              tooltip: _puedeIniciar
                  ? 'Marcar EN SITIO'
                  : 'Falta: ${_motivosInicio.join(' · ')}',
              color: _puedeIniciar ? _green : null,
              onPressed: _marcarEnSitio,
            ),
          // Editar: oculto cuando el servicio está cerrado (solo lectura).
          if (d != null &&
              completo &&
              !d.esCerrado &&
              (AppSession.i.isJefeOperaciones || AppSession.i.isAdmin))
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Editar servicio',
              onPressed: _editarServicio,
            ),
          // Cerrar: solo jefe/admin, con todas las tareas completas.
          if (d != null && completo && _puedeFinalizar && d.estado == 'En_Proceso')
            IconButton(
              icon: const Icon(Icons.task_alt_outlined, size: 20),
              tooltip: _todasTareasCompletas
                  ? 'Cerrar servicio y generar informe'
                  : 'Marca todas las tareas para cerrar',
              color: _todasTareasCompletas ? _green : null,
              onPressed: _cerrarServicio,
            ),
          // Menú de líder: cancelar / reabrir (acciones terminales protegidas).
          if (d != null &&
              completo &&
              _puedeFinalizar &&
              !_cambiandoEstado &&
              !d.esCancelado)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              tooltip: 'Más acciones',
              onSelected: (v) {
                if (v == 'cancelar') _cancelarServicio();
                if (v == 'reabrir') _cambiarEstado('En_Proceso');
              },
              itemBuilder: (_) => [
                if (!d.esCerrado)
                  const PopupMenuItem(
                      value: 'cancelar', child: Text('Cancelar servicio')),
                if (d.esTerminado)
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
              : !completo
                  ? _VistaServicioBasica(detalle: d)
                  : Column(
                  children: [
                    _Header(detalle: d, progresoMostrado: _progresoTareas),
                    const SizedBox(height: 10),
                    _FasesStepper(estado: d.estado, progreso: _progresoTareas),
                    // ── Botón Equipos Intervenidos (solo si está activo) ──
                    if (d.inspeccionEquiposActiva) ...[
                      const SizedBox(height: 8),
                      _EquiposIntervenidosButton(
                        servicioId: d.id,
                        ubicacionId: d.ubicacionId,
                        zonaId: d.zonaId,
                        isClosed: d.esCerrado,
                      ),
                    ] else if (!d.esCerrado && _esJefeOperaciones) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: OutlinedButton.icon(
                          onPressed: _activandoInspeccion
                              ? null
                              : _activarInspeccionEquipos,
                          icon: _activandoInspeccion
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.electrical_services_outlined,
                                  size: 18),
                          label: Text(_activandoInspeccion
                              ? 'Activando…'
                              : 'Activar inspección de equipos'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                    ],
                    if (d.esCerrado) ...[
                      const SizedBox(height: 4),
                      _ClosedBanner(estado: d.estado),
                    ],
                    if (d.estado == 'Pendiente') ...[
                      const SizedBox(height: 8),
                      _ChecklistPreparacion(
                        equipoListo: _prepEquipoListo,
                        tareasListo: _prepTareasListo,
                        materialesListo: _prepMaterialesListo,
                        puedeIniciar: _puedeIniciar,
                        esJefe: _esJefeOperaciones,
                        motivos: _motivosInicio,
                        iniciando: _cambiandoEstado,
                        onIniciar: _marcarEnSitio,
                      ),
                    ],
                    // ── Fase Ejecución / Cierre (servicio En Proceso) ──────
                    if (d.estado == 'En_Proceso') ...[
                      const SizedBox(height: 8),
                      _FaseEjecucionCard(
                        totalTareas: d.tareas.length,
                        tareasCompletas:
                            d.tareas.where((t) => t.estado == 'completado').length,
                        todasCompletas: _todasTareasCompletas,
                        esJefe: _esJefeOperaciones,
                        cerrando: _cambiandoEstado,
                        onCerrar: _cerrarServicio,
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
                            icon: const Icon(Icons.assignment_outlined, size: 18),
                            text: 'Tareas · ${d.tareas.length}'),
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
                            icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
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
                          _TareasTab(
                            tareas: d.tareas,
                            equipo: d.equipo,
                            onToggle: _toggleTareaOptimista,
                          ),
                          _EquipoTab(
                            equipo: d.equipo,
                            servicioId: d.id,
                            proyectoId: d.proyectoId,
                            service: widget.service,
                            onChanged: _reloadDetalle,
                            isClosed: d.esCerrado,
                          ),
                          _MaterialesTab(
                            servicioId: d.id,
                            asignados: d.materialesAsignados,
                            solicitados: d.materialesSolicitados,
                            borrador: _borrador,
                            reqsRecepcion: _reqsRecepcion,
                            service: widget.service,
                            onChanged: _reloadMateriales,
                            isClosed: d.esCerrado,
                          ),
                          _NotasTab(
                            servicioId: d.id,
                            notasIniciales: d.notas,
                            service: widget.service,
                            isClosed: d.esCerrado,
                          ),
                          ChatTab(
                            room: 'servicio/${widget.servicioId}',
                            isClosed: d.esCerrado,
                            fotosPorId: {
                              for (final m in d.equipo)
                                if (m.fotoUrl.isNotEmpty) m.id: m.fotoUrl,
                            },
                          ),
                          _ComunicadosTab(
                            proyectoId: widget.proyectoId,
                            isClosed: d.esCerrado,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

