import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/intervencion_models.dart';
import '../models/proyecto_models.dart';
import '../services/intervencion_service.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';
import '../core/connectivity_service.dart';

// ─── Colores de marca ─────────────────────────────────────────────────────────
const _kGreen = Color(0xFF8FD11B);

// ─── Contexto de inspección activo en la cámara ───────────────────────────────
// La cámara de campo trabaja SIEMPRE sobre el checklist de inspección de un
// equipo intervenido (procedimientos por tipo de equipo). Los procedimientos
// por tipo de servicio ya no existen como concepto.

class InspeccionCamaraCtx {
  final String inspeccionId;
  final String servicioId;
  final String eiId;
  final String servicioNombre;
  final String equipoNombre;
  final List<PasoInspeccion> pasos;
  final bool soloLectura;

  const InspeccionCamaraCtx({
    required this.inspeccionId,
    required this.servicioId,
    required this.eiId,
    required this.servicioNombre,
    required this.equipoNombre,
    required this.pasos,
    this.soloLectura = false,
  });
}

// ─── Pantalla principal ───────────────────────────────────────────────────────

class CamaraCampoScreen extends StatefulWidget {
  /// Inspección ya cargada (modo "desde el checklist": sin selector).
  final InspeccionCamaraCtx? inspeccionInicial;
  final int pasoInicial;

  /// true = cámara de campo global: permite cambiar de proyecto/servicio/equipo.
  final bool conSelector;

  const CamaraCampoScreen({
    super.key,
    this.inspeccionInicial,
    this.pasoInicial = 0,
    this.conSelector = true,
  });

  /// Cámara de campo global (botón hero del inicio).
  static Future<void> open(BuildContext context) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => const CamaraCampoScreen(),
          fullscreenDialog: true,
        ),
      );

  /// Cámara sobre una inspección ya abierta (desde el checklist del equipo):
  /// solo flechas entre pasos + almacén de fotos, sin selector.
  /// Muta `insp.pasos` in place (foto_url) — el caller solo hace setState.
  static Future<void> paraInspeccion(
    BuildContext context, {
    required String servicioId,
    required String eiId,
    required String servicioNombre,
    required String equipoNombre,
    required InspeccionActiva insp,
    int pasoInicial = 0,
  }) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CamaraCampoScreen(
            conSelector: false,
            pasoInicial: pasoInicial,
            inspeccionInicial: InspeccionCamaraCtx(
              inspeccionId: insp.inspeccionId,
              servicioId: servicioId,
              eiId: eiId,
              servicioNombre: servicioNombre,
              equipoNombre: equipoNombre,
              pasos: insp.pasos,
              soloLectura: insp.estado == 'completado' ||
                  insp.equipo.estadoIntervencion == 'completado',
            ),
          ),
          fullscreenDialog: true,
        ),
      );

  @override
  State<CamaraCampoScreen> createState() => _CamaraCampoScreenState();
}

class _CamaraCampoScreenState extends State<CamaraCampoScreen>
    with WidgetsBindingObserver {
  // Cámara
  CameraController? _ctrl;
  bool _ready = false;
  bool _capturing = false;
  String? _error;

  // Preview tras captura
  String? _previewPath;
  bool _confirming = false;

  // Inspección activa + paso actual
  InspeccionCamaraCtx? _insp;
  int _idx = 0;
  bool _cargandoInsp = false;

  IntervencionService? _intSvc;
  ProyectoService? _proySvc;

  // Prefs: último equipo usado (solo modo global).
  static const _kServId = 'campo_last_serv_id';
  static const _kServNombre = 'campo_last_serv_nombre';
  static const _kEiId = 'campo_last_ei_id';
  static const _kEiNombre = 'campo_last_ei_nombre';

  PasoInspeccion? get _paso {
    final i = _insp;
    if (i == null || i.pasos.isEmpty) return null;
    return i.pasos[_idx.clamp(0, i.pasos.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _insp = widget.inspeccionInicial;
    if (_insp != null && _insp!.pasos.isNotEmpty) {
      _idx = widget.pasoInicial.clamp(0, _insp!.pasos.length - 1);
    }
    _inicializar();
  }

  Future<void> _inicializar() async {
    _intSvc = await getIntervencionService();
    _proySvc = await getProyectoService();
    if (_insp == null && widget.conSelector) await _restaurarUltimoEquipo();
    await _checkPermissionAndInit();
  }

  Future<void> _restaurarUltimoEquipo() async {
    final prefs = await SharedPreferences.getInstance();
    final servId = prefs.getString(_kServId);
    final servNombre = prefs.getString(_kServNombre);
    final eiId = prefs.getString(_kEiId);
    final eiNombre = prefs.getString(_kEiNombre);
    if (servId == null || eiId == null) return;
    await _cargarInspeccion(
      servicioId: servId,
      servicioNombre: servNombre ?? '',
      eiId: eiId,
      equipoNombre: eiNombre ?? '',
      silencioso: true,
    );
  }

  /// Abre (o retoma) la sesión de inspección del equipo y la deja activa.
  Future<void> _cargarInspeccion({
    required String servicioId,
    required String servicioNombre,
    required String eiId,
    required String equipoNombre,
    bool silencioso = false,
  }) async {
    if (_intSvc == null) return;
    setState(() => _cargandoInsp = true);
    final res = await _intSvc!.getInspeccionActiva(servicioId, eiId);
    if (!mounted) return;
    if (res.ok && res.data != null) {
      final d = res.data!;
      setState(() {
        _insp = InspeccionCamaraCtx(
          inspeccionId: d.inspeccionId,
          servicioId: servicioId,
          eiId: eiId,
          servicioNombre: servicioNombre,
          equipoNombre: equipoNombre.isEmpty ? d.equipo.nombre : equipoNombre,
          pasos: d.pasos,
          soloLectura: d.estado == 'completado' ||
              d.equipo.estadoIntervencion == 'completado',
        );
        // Arrancar en el primer paso sin foto (lo que sigue en el trabajo).
        final pend = d.pasos.indexWhere((p) => (p.fotoUrl ?? '').isEmpty);
        _idx = pend < 0 ? 0 : pend;
        _cargandoInsp = false;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kServId, servicioId);
      await prefs.setString(_kServNombre, servicioNombre);
      await prefs.setString(_kEiId, eiId);
      await prefs.setString(_kEiNombre, _insp!.equipoNombre);
    } else {
      setState(() => _cargandoInsp = false);
      if (!silencioso) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res.errorMessage.isEmpty
                ? 'No se pudo abrir la inspección del equipo.'
                : res.errorMessage)));
      }
    }
  }

  void _cambiarPaso(int delta) {
    final i = _insp;
    if (i == null) return;
    final j = _idx + delta;
    if (j < 0 || j >= i.pasos.length) return;
    setState(() => _idx = j);
  }

  // ── Cámara ─────────────────────────────────────────────────────────────────

  Future<void> _checkPermissionAndInit() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _initCamera();
    } else {
      if (!mounted) return;
      setState(() => _error = 'Se requiere permiso de cámara.');
      if (status.isPermanentlyDenied) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Permiso requerido'),
              content: const Text(
                  'Habilita el permiso de cámara en Ajustes del dispositivo.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await openAppSettings();
                    },
                    child: const Text('Ir a Ajustes')),
              ],
            ),
          );
        });
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No se encontró cámara.');
        return;
      }
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl =
          CameraController(cam, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        // La pantalla se cerró mientras inicializaba: liberar sin tocar estado.
        await ctrl.dispose();
        return;
      }
      setState(() {
        _ctrl = ctrl;
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error al inicializar cámara: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      // Soltar la cámara ANTES de perder el foco (evita crashes nativos en
      // equipos de gama baja al volver o al abrir otra app de cámara).
      _ctrl = null;
      _ready = false;
      ctrl.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final ctrl = _ctrl;
    _ctrl = null;
    ctrl?.dispose();
    super.dispose();
  }

  // ── Captura ────────────────────────────────────────────────────────────────

  bool get _puedeCapturar =>
      _ready &&
      _insp != null &&
      !_insp!.soloLectura &&
      _paso != null &&
      !_capturing;

  Future<void> _capturar() async {
    final ctrl = _ctrl;
    if (ctrl == null || !_puedeCapturar) return;
    setState(() => _capturing = true);
    try {
      final xFile = await ctrl.takePicture();
      if (!mounted) return;
      setState(() {
        _previewPath = xFile.path;
        _capturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al capturar: $e')),
      );
    }
  }

  /// Comprime y sube la foto al paso indicado. Devuelve true si quedó subida.
  Future<bool> _subirFotoAPaso(String rawPath, PasoInspeccion paso) async {
    final insp = _insp;
    if (insp == null || _intSvc == null) return false;
    final dir = await getTemporaryDirectory();
    final destPath =
        '${dir.path}/insp_${paso.orden}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final result = await FlutterImageCompress.compressAndGetFile(
      rawPath, destPath,
      quality: 75, minWidth: 1280, minHeight: 720,
    );
    final res = await _intSvc!.subirFotoInspeccion(
        insp.inspeccionId, paso.orden, result?.path ?? rawPath);
    if (res.ok && res.data != null) {
      paso.fotoUrl = res.data!.url;
      paso.fotoPublicId = res.data!.publicId;
      return true;
    }
    return false;
  }

  Future<void> _confirmar() async {
    final raw = _previewPath;
    final paso = _paso;
    if (raw == null || paso == null) return;
    setState(() => _confirming = true);
    try {
      final ok = await _subirFotoAPaso(raw, paso);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Icon(ok ? Icons.cloud_done_outlined : Icons.error_outline,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ok
                  ? 'Foto guardada en el paso ${paso.orden}'
                  : (isOnlineNotifier.value
                      ? 'No se pudo subir la foto.'
                      : 'Sin conexión: no se pudo subir la foto.')),
            ),
          ]),
          backgroundColor:
              ok ? const Color(0xFF1E9462) : const Color(0xFFD6584F),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      setState(() {
        _previewPath = null;
        _confirming = false;
        // Avanzar solo al confirmar con éxito: el técnico dispara y sigue.
        if (ok && _idx < (_insp?.pasos.length ?? 1) - 1) _idx++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar la foto: $e')),
      );
    }
  }

  void _retomar() => setState(() {
        _previewPath = null;
        _confirming = false;
      });

  // ── Almacén: subir fotos ya tomadas con el teléfono ────────────────────────

  Future<void> _abrirAlmacen() async {
    final insp = _insp;
    if (insp == null || insp.soloLectura) return;
    final fotos = await ImagePicker().pickMultiImage(imageQuality: 85);
    if (fotos.isEmpty || !mounted) return;
    final subidas = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlmacenSheet(
        fotos: fotos,
        pasos: insp.pasos,
        pasoSugerido: _idx,
        subir: _subirFotoAPaso,
      ),
    );
    if (subidas != null && subidas > 0 && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '$subidas foto${subidas == 1 ? '' : 's'} asignada${subidas == 1 ? '' : 's'} a procedimientos'),
        backgroundColor: const Color(0xFF1E9462),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ── Selector de equipo (proyecto → servicio → equipo intervenido) ──────────

  Future<void> _abrirSelector() async {
    if (_proySvc == null || _intSvc == null) return;
    final resultado = await showModalBottomSheet<_SeleccionEquipo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _SelectorSheet(proySvc: _proySvc!, intSvc: _intSvc!),
    );
    if (resultado != null && mounted) {
      await _cargarInspeccion(
        servicioId: resultado.servicioId,
        servicioNombre: resultado.servicioNombre,
        eiId: resultado.eiId,
        equipoNombre: resultado.equipoNombre,
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_previewPath != null) {
      return _VistaPreview(
        path: _previewPath!,
        pasoLabel: 'Paso ${_paso?.orden ?? ''}',
        isConfirming: _confirming,
        onConfirm: _confirmar,
        onRetake: _retomar,
      );
    }

    final insp = _insp;
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Preview de cámara ─────────────────────────────────────────────
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center),
              ),
            )
          else if (!_ready || ctrl == null)
            const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_kGreen)),
            )
          else
            CameraPreview(ctrl),

          // ── Overlay superior + banner offline ─────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OverlaySuperior(
                  insp: insp,
                  paso: _paso,
                  cargando: _cargandoInsp,
                  conSelector: widget.conSelector,
                  onTap: widget.conSelector ? _abrirSelector : null,
                  onClose: () => Navigator.pop(context),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: isOnlineNotifier,
                  builder: (_, online, _) {
                    if (online) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xCC7A4A00),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.cloud_off_outlined,
                              color: Colors.amber, size: 15),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sin conexión: las fotos de inspección necesitan internet',
                              style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (insp != null && insp.soloLectura)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline, color: Colors.white70, size: 15),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Inspección completada: solo lectura',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Overlay inferior: flechas + captura + almacén ──────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _OverlayInferior(
                capturing: _capturing,
                enabled: _puedeCapturar,
                onCaptura: _capturar,
                pasoIndice: insp == null ? -1 : _idx,
                pasoTotal: insp?.pasos.length ?? 0,
                pasoConFoto: (_paso?.fotoUrl ?? '').isNotEmpty,
                onAnterior: (insp != null && _idx > 0)
                    ? () => _cambiarPaso(-1)
                    : null,
                onSiguiente:
                    (insp != null && _idx < insp.pasos.length - 1)
                        ? () => _cambiarPaso(1)
                        : null,
                onAlmacen: (insp != null && !insp.soloLectura)
                    ? _abrirAlmacen
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Overlay superior ─────────────────────────────────────────────────────────

class _OverlaySuperior extends StatelessWidget {
  final InspeccionCamaraCtx? insp;
  final PasoInspeccion? paso;
  final bool cargando;
  final bool conSelector;
  final VoidCallback? onTap;
  final VoidCallback onClose;

  const _OverlaySuperior({
    required this.insp,
    required this.paso,
    required this.cargando,
    required this.conSelector,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.camera_alt_outlined, color: _kGreen, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: cargando
                  ? const Text('Abriendo inspección…',
                      style: TextStyle(color: Colors.white70, fontSize: 13))
                  : insp == null
                      ? const Text(
                          'Toca para elegir el equipo a inspeccionar',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (insp!.servicioNombre.isNotEmpty)
                                  insp!.servicioNombre,
                                insp!.equipoNombre,
                              ].join(' · '),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              paso == null
                                  ? 'Sin procedimientos definidos para este tipo de equipo'
                                  : '${paso!.orden}. ${paso!.nombre}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
            ),
            const SizedBox(width: 8),
            if (conSelector)
              Icon(
                insp == null ? Icons.arrow_drop_down : Icons.edit_outlined,
                color: Colors.white54,
                size: 18,
              ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: onClose,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ],
        ),
        ),
        ),
      ),
    );
  }
}

// ─── Overlay inferior ─────────────────────────────────────────────────────────

class _OverlayInferior extends StatelessWidget {
  final bool capturing;
  final bool enabled;
  final VoidCallback onCaptura;
  final int pasoIndice; // -1 si no hay inspección
  final int pasoTotal;
  final bool pasoConFoto;
  final VoidCallback? onAnterior;
  final VoidCallback? onSiguiente;
  final VoidCallback? onAlmacen;

  const _OverlayInferior({
    required this.capturing,
    required this.enabled,
    required this.onCaptura,
    required this.pasoIndice,
    required this.pasoTotal,
    required this.pasoConFoto,
    this.onAnterior,
    this.onSiguiente,
    this.onAlmacen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.80),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pasoIndice >= 0 && pasoTotal > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Procedimiento ${pasoIndice + 1} de $pasoTotal',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500),
                ),
                if (pasoConFoto) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_circle, color: _kGreen, size: 14),
                  const Text(' con foto',
                      style: TextStyle(color: _kGreen, fontSize: 11)),
                ],
              ],
            ),
          const SizedBox(height: 12),
          // Flechas para recorrer el checklist sin soltar la cámara + almacén.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BotonAccion(
                icon: Icons.photo_library_outlined,
                label: 'Almacén',
                onTap: onAlmacen,
              ),
              const SizedBox(width: 18),
              _BotonAccion(
                icon: Icons.chevron_left,
                label: 'Anterior',
                onTap: onAnterior,
              ),
              const SizedBox(width: 18),
              Opacity(
                opacity: enabled ? 1.0 : 0.35,
                child: _BtnCaptura(
                  onTap: enabled ? onCaptura : null,
                  capturing: capturing,
                ),
              ),
              const SizedBox(width: 18),
              _BotonAccion(
                icon: Icons.chevron_right,
                label: 'Siguiente',
                onTap: onSiguiente,
              ),
              // Hueco simétrico al botón de almacén para centrar la captura.
              const SizedBox(width: 18 + 46),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Botón circular de acción (flechas / almacén) ─────────────────────────────

class _BotonAccion extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BotonAccion({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final habilitado = onTap != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: habilitado ? 1.0 : 0.3,
          child: IconButton(
            tooltip: label,
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              fixedSize: const Size(46, 46),
              shape: CircleBorder(
                side: BorderSide(
                    color: _kGreen.withValues(alpha: habilitado ? 0.9 : 0.4),
                    width: 1.5),
              ),
            ),
            icon: Icon(icon, color: _kGreen, size: 26),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 10)),
      ],
    );
  }
}

// ─── Botón de captura ─────────────────────────────────────────────────────────

class _BtnCaptura extends StatelessWidget {
  final VoidCallback? onTap;
  final bool capturing;

  const _BtnCaptura({this.onTap, required this.capturing});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: capturing ? 52 : 58,
              height: capturing ? 52 : 58,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Vista de preview (confirmar / re-tomar) ──────────────────────────────────

class _VistaPreview extends StatelessWidget {
  final String path;
  final String pasoLabel;
  final bool isConfirming;
  final VoidCallback onConfirm;
  final VoidCallback onRetake;

  const _VistaPreview({
    required this.path,
    required this.pasoLabel,
    required this.isConfirming,
    required this.onConfirm,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(path), fit: BoxFit.contain),

          // Etiqueta superior
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _kGreen),
                      ),
                      child: Text(
                        pasoLabel,
                        style: const TextStyle(
                          color: _kGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Confirmar foto',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botones
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.80),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isConfirming ? null : onRetake,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Re-tomar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isConfirming ? null : onConfirm,
                        icon: isConfirming
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.check),
                        label: Text(isConfirming ? 'Subiendo…' : 'Confirmar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Almacén: asignar fotos del teléfono a procedimientos ─────────────────────
// Para quien trabajó sin el app: toma las fotos con su celular y aquí las
// asigna una por una al procedimiento que corresponde.

class _AlmacenSheet extends StatefulWidget {
  final List<XFile> fotos;
  final List<PasoInspeccion> pasos;
  final int pasoSugerido;
  final Future<bool> Function(String path, PasoInspeccion paso) subir;

  const _AlmacenSheet({
    required this.fotos,
    required this.pasos,
    required this.pasoSugerido,
    required this.subir,
  });

  @override
  State<_AlmacenSheet> createState() => _AlmacenSheetState();
}

class _AlmacenSheetState extends State<_AlmacenSheet> {
  // Índice de paso asignado por foto (null = sin asignar, no se sube).
  late final List<int?> _asignacion;
  // Estado de subida por foto: null = pendiente, true = ok, false = error.
  late final List<bool?> _resultado;
  bool _subiendo = false;

  @override
  void initState() {
    super.initState();
    _asignacion = List<int?>.filled(widget.fotos.length, null);
    _resultado = List<bool?>.filled(widget.fotos.length, null);
    if (widget.fotos.length == 1 && widget.pasos.isNotEmpty) {
      _asignacion[0] = widget.pasoSugerido.clamp(0, widget.pasos.length - 1);
    }
  }

  int get _asignadas => _asignacion.where((a) => a != null).length;

  Future<void> _subirTodas() async {
    setState(() => _subiendo = true);
    var ok = 0;
    for (var i = 0; i < widget.fotos.length; i++) {
      final a = _asignacion[i];
      if (a == null || _resultado[i] == true) continue;
      final r = await widget.subir(widget.fotos[i].path, widget.pasos[a]);
      if (!mounted) return;
      setState(() => _resultado[i] = r);
      if (r) ok++;
    }
    if (!mounted) return;
    setState(() => _subiendo = false);
    if (_resultado.every((r) => r != false)) {
      Navigator.pop(context, ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.80,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Asignar fotos a procedimientos',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: _subiendo
                      ? null
                      : () => Navigator.pop(
                          context, _resultado.where((r) => r == true).length),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Elige a qué procedimiento pertenece cada foto. '
                'Si un paso ya tenía foto, se reemplaza.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.fotos.length,
              itemBuilder: (_, i) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(widget.fotos[i].path),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _asignacion[i],
                        isExpanded: true,
                        dropdownColor: const Color(0xFF262626),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5),
                        decoration: InputDecoration(
                          labelText: 'Procedimiento',
                          labelStyle: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                          isDense: true,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Colors.white24),
                          ),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        items: [
                          const DropdownMenuItem<int>(
                            value: null,
                            child: Text('— No subir —',
                                style: TextStyle(color: Colors.white38)),
                          ),
                          for (var p = 0; p < widget.pasos.length; p++)
                            DropdownMenuItem<int>(
                              value: p,
                              child: Text(
                                '${widget.pasos[p].orden}. ${widget.pasos[p].nombre}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (_subiendo || _resultado[i] == true)
                            ? null
                            : (v) => setState(() => _asignacion[i] = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_resultado[i] == true)
                      const Icon(Icons.cloud_done_outlined,
                          color: _kGreen, size: 20)
                    else if (_resultado[i] == false)
                      const Icon(Icons.error_outline,
                          color: Colors.redAccent, size: 20),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed:
                      (_subiendo || _asignadas == 0) ? null : _subirTodas,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _subiendo
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_subiendo
                      ? 'Subiendo…'
                      : 'Subir $_asignadas foto${_asignadas == 1 ? '' : 's'}'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Selector: proyecto → servicio → equipo intervenido ───────────────────────

class _SeleccionEquipo {
  final String servicioId;
  final String servicioNombre;
  final String eiId;
  final String equipoNombre;

  const _SeleccionEquipo({
    required this.servicioId,
    required this.servicioNombre,
    required this.eiId,
    required this.equipoNombre,
  });
}

class _SelectorSheet extends StatefulWidget {
  final ProyectoService proySvc;
  final IntervencionService intSvc;
  const _SelectorSheet({required this.proySvc, required this.intSvc});

  @override
  State<_SelectorSheet> createState() => _SelectorSheetState();
}

class _SelectorSheetState extends State<_SelectorSheet> {
  // Nivel de navegación: 0=proyectos, 1=servicios, 2=equipos intervenidos
  int _nivel = 0;

  ProyectoItem? _proyecto;
  ServicioItem? _servicio;

  List<ProyectoItem> _proyectos = [];
  List<ServicioItem> _servicios = [];
  List<EquipoIntervenidoServicio> _equipos = [];

  bool _cargando = false;
  String? _errorMsg;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargarProyectos();
  }

  Future<void> _cargarProyectos() async {
    setState(() { _cargando = true; _errorMsg = null; });
    try {
      final data = await widget.proySvc.getProyectos();
      if (!mounted) return;
      setState(() {
        _proyectos = (data?.proyectos ?? [])
            .where((p) => p.estado != 'Completado' && p.estado != 'Cancelado')
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _errorMsg = 'Error al cargar proyectos'; });
    }
  }

  Future<void> _cargarServicios(ProyectoItem proyecto) async {
    setState(() { _cargando = true; _errorMsg = null; _proyecto = proyecto; _nivel = 1; });
    try {
      final lista = await widget.proySvc.getServiciosProyecto(proyecto.id);
      if (!mounted) return;
      setState(() {
        _servicios = lista
            .where((s) => s.estado != 'Completado' && s.estado != 'Cancelado')
            .toList();
        _cargando = false;
        _busqueda = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _errorMsg = 'Error al cargar servicios'; });
    }
  }

  Future<void> _cargarEquipos(ServicioItem servicio) async {
    setState(() { _cargando = true; _errorMsg = null; _servicio = servicio; _nivel = 2; });
    final res = await widget.intSvc.getEquiposIntervenidos(servicio.id);
    if (!mounted) return;
    setState(() {
      if (res.ok) {
        _equipos = res.data ?? [];
      } else {
        _errorMsg = 'Error al cargar los equipos del servicio';
      }
      _cargando = false;
      _busqueda = '';
    });
  }

  void _retroceder() {
    setState(() {
      _busqueda = '';
      if (_nivel == 2) { _nivel = 1; }
      else if (_nivel == 1) { _nivel = 0; _proyecto = null; }
    });
  }

  String get _titulo => switch (_nivel) {
        0 => 'Seleccionar proyecto',
        1 => _proyecto?.nombreProyecto ?? 'Servicios',
        _ => _servicio?.nombre ?? 'Equipos intervenidos',
      };

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Container(
      height: mq.size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                if (_nivel > 0)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: _retroceder,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                if (_nivel > 0) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: switch (_nivel) {
                  0 => 'Buscar proyecto…',
                  1 => 'Buscar servicio…',
                  _ => 'Buscar equipo…',
                },
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _busqueda = v.toLowerCase()),
            ),
          ),

          const SizedBox(height: 8),

          // Contenido
          Expanded(child: _buildContenido()),
        ],
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kGreen)),
      );
    }
    if (_errorMsg != null) {
      final offline = !isOnlineNotifier.value;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                offline ? Icons.cloud_off_outlined : Icons.error_outline,
                color: offline ? Colors.amber : Colors.redAccent,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                offline
                    ? 'Sin conexión\nAbre la app con internet primero para cargar tus proyectos en caché'
                    : _errorMsg!,
                style: TextStyle(
                    color: offline ? Colors.amber : Colors.redAccent,
                    fontSize: 13,
                    height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  if (_nivel == 0) {
                    _cargarProyectos();
                  } else if (_nivel == 1 && _proyecto != null) {
                    _cargarServicios(_proyecto!);
                  } else if (_nivel == 2 && _servicio != null) {
                    _cargarEquipos(_servicio!);
                  }
                },
                icon: const Icon(Icons.refresh, color: _kGreen),
                label: const Text('Reintentar', style: TextStyle(color: _kGreen)),
              ),
            ],
          ),
        ),
      );
    }

    return switch (_nivel) {
      0 => _listaProyectos(),
      1 => _listaServicios(),
      _ => _listaEquipos(),
    };
  }

  Widget _listaProyectos() {
    final filtrados = _proyectos
        .where((p) => p.nombreProyecto.toLowerCase().contains(_busqueda) ||
                      p.ordenTrabajo.toLowerCase().contains(_busqueda))
        .toList();
    if (filtrados.isEmpty) {
      final offline = !isOnlineNotifier.value;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(offline ? Icons.cloud_off_outlined : Icons.folder_open_outlined,
                color: Colors.white38, size: 36),
            const SizedBox(height: 10),
            Text(
              offline
                  ? 'Sin conexión\nNo hay proyectos en caché.\nConéctate a internet y vuelve a intentarlo.'
                  : 'Sin proyectos activos',
              style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: filtrados.length,
      itemBuilder: (_, i) {
        final p = filtrados[i];
        return _ItemLista(
          titulo: p.nombreProyecto,
          subtitulo: 'OT ${p.ordenTrabajo} · ${p.totalServicios} servicios',
          onTap: () => _cargarServicios(p),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        );
      },
    );
  }

  Widget _listaServicios() {
    final filtrados = _servicios
        .where((s) => s.nombre.toLowerCase().contains(_busqueda))
        .toList();
    if (filtrados.isEmpty) {
      return const Center(
        child: Text('Sin servicios activos en este proyecto',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: filtrados.length,
      itemBuilder: (_, i) {
        final s = filtrados[i];
        return _ItemLista(
          titulo: s.nombre,
          subtitulo: s.estado,
          onTap: () => _cargarEquipos(s),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        );
      },
    );
  }

  Widget _listaEquipos() {
    // Solo los equipos de ESTE servicio (del_servicio_actual): los otros de la
    // sede son de otro servicio y no se intervienen aquí.
    final filtrados = _equipos
        .where((e) => e.delServicioActual)
        .where((e) =>
            e.nombre.toLowerCase().contains(_busqueda) ||
            (e.tipoNombre?.toLowerCase().contains(_busqueda) ?? false) ||
            (e.codigo?.toLowerCase().contains(_busqueda) ?? false))
        .toList();
    if (filtrados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Este servicio no tiene equipos para intervenir.\n'
            'Regístralos desde el detalle del servicio (en ejecución).',
            style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: filtrados.length,
      itemBuilder: (_, i) {
        final e = filtrados[i];
        final completado = e.estadoIntervencion == 'completado';
        final enProceso = e.estadoIntervencion == 'en_proceso';
        return _ItemLista(
          titulo: e.nombre,
          subtitulo: [
            if ((e.tipoNombre ?? '').isNotEmpty) e.tipoNombre!,
            completado
                ? 'Completado'
                : (enProceso ? 'En proceso' : 'Sin inspección'),
          ].join(' · '),
          leading: Icon(
            completado
                ? Icons.check_circle
                : (enProceso
                    ? Icons.timelapse
                    : Icons.radio_button_unchecked),
            color: completado
                ? _kGreen
                : (enProceso ? Colors.amber : Colors.white38),
            size: 20,
          ),
          onTap: () => Navigator.pop(
            context,
            _SeleccionEquipo(
              servicioId: _servicio!.id,
              servicioNombre: _servicio!.nombre,
              eiId: e.id,
              equipoNombre: e.nombre,
            ),
          ),
        );
      },
    );
  }
}

// ─── Ítem de lista del selector ───────────────────────────────────────────────

class _ItemLista extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;

  const _ItemLista({
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  if (subtitulo.isNotEmpty)
                    Text(subtitulo,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}
