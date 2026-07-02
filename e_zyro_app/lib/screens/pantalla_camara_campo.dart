import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/proyecto_models.dart';
import '../services/proyecto_service.dart';
import '../utils/api_provider.dart';
import '../core/connectivity_service.dart';
import '../utils/app_notifiers.dart';

// ─── Colores de marca ─────────────────────────────────────────────────────────
const _kGreen = Color(0xFF8FD11B);

// ─── Datos de selección activa ────────────────────────────────────────────────

class SeleccionProcedimientoCampo {
  final String procId;
  final String procNombre;
  final String servicioId;
  final String servicioNombre;

  const SeleccionProcedimientoCampo({
    required this.procId,
    required this.procNombre,
    required this.servicioId,
    required this.servicioNombre,
  });
}

// ─── Pantalla principal ───────────────────────────────────────────────────────

class CamaraCampoScreen extends StatefulWidget {
  final SeleccionProcedimientoCampo? preseleccion;

  const CamaraCampoScreen({super.key, this.preseleccion});

  static Future<void> open(BuildContext context) => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => const CamaraCampoScreen(),
          fullscreenDialog: true,
        ),
      );

  /// Abre la cámara ya apuntando a un procedimiento específico (ej. desde
  /// el detalle de un equipo intervenido) sin pasar por el selector manual.
  static Future<void> openPara(
    BuildContext context, {
    required String procId,
    required String procNombre,
    required String servicioId,
    required String servicioNombre,
  }) =>
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CamaraCampoScreen(
            preseleccion: SeleccionProcedimientoCampo(
              procId: procId,
              procNombre: procNombre,
              servicioId: servicioId,
              servicioNombre: servicioNombre,
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

  // Selección activa
  SeleccionProcedimientoCampo? _sel;
  String _etapa = 'durante';

  // Servicio de datos
  ProyectoService? _svc;

  // Prefs keys para persistir la última selección
  static const _kProcId       = 'campo_last_proc_id';
  static const _kProcNombre   = 'campo_last_proc_nombre';
  static const _kServId       = 'campo_last_serv_id';
  static const _kServNombre   = 'campo_last_serv_nombre';
  static const _kEtapa        = 'campo_last_etapa';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inicializar();
  }

  Future<void> _inicializar() async {
    _svc = await getProyectoService();
    await _restaurarSeleccion();
    await _checkPermissionAndInit();
  }

  Future<void> _restaurarSeleccion() async {
    final pre = widget.preseleccion;
    if (pre != null) {
      // Vino con un procedimiento específico (ej. desde Equipos Intervenidos):
      // usarlo directo y guardarlo como "última selección" para la próxima vez.
      if (!mounted) return;
      setState(() => _sel = pre);
      await _guardarSeleccion(pre, _etapa);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final procId     = prefs.getString(_kProcId);
    final procNombre = prefs.getString(_kProcNombre);
    final servId     = prefs.getString(_kServId);
    final servNombre = prefs.getString(_kServNombre);
    final etapa      = prefs.getString(_kEtapa) ?? 'durante';
    if (!mounted) return;
    setState(() {
      _etapa = etapa;
      if (procId != null && procNombre != null &&
          servId != null && servNombre != null) {
        _sel = SeleccionProcedimientoCampo(
          procId: procId,
          procNombre: procNombre,
          servicioId: servId,
          servicioNombre: servNombre,
        );
      }
    });
  }

  Future<void> _guardarSeleccion(SeleccionProcedimientoCampo sel, String etapa) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProcId,     sel.procId);
    await prefs.setString(_kProcNombre, sel.procNombre);
    await prefs.setString(_kServId,     sel.servicioId);
    await prefs.setString(_kServNombre, sel.servicioNombre);
    await prefs.setString(_kEtapa,      etapa);
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
      if (!mounted) return;
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
      ctrl.dispose();
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  // ── Captura ────────────────────────────────────────────────────────────────

  Future<void> _capturar() async {
    if (_ctrl == null || !_ready || _capturing || _sel == null) return;
    setState(() => _capturing = true);
    try {
      final xFile = await _ctrl!.takePicture();
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

  Future<void> _confirmar() async {
    final raw = _previewPath;
    final sel = _sel;
    if (raw == null || sel == null || _svc == null) return;
    setState(() => _confirming = true);
    try {
      // Comprimir antes de encolar
      final dir      = await getTemporaryDirectory();
      final destPath =
          '${dir.path}/campo_${_etapa}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result   = await FlutterImageCompress.compressAndGetFile(
        raw, destPath,
        quality: 75, minWidth: 1280, minHeight: 720,
      );
      final finalPath = result?.path ?? raw;

      final resultado = await _svc!.encolarEvidencia(
        procedimientoId: sel.procId,
        servicioId: sel.servicioId,
        etapa: _etapa,
        fotoPath: finalPath,
      );

      if (!mounted) return;
      final rechazo = resultado.errorPermanente;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            Icon(
              rechazo != null
                  ? Icons.error_outline
                  : (resultado.enviada
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined),
              color: Colors.white, size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(rechazo ??
                  (resultado.enviada
                      ? 'Evidencia enviada'
                      : 'Guardada para sincronizar')),
            ),
          ]),
          backgroundColor: rechazo != null
              ? const Color(0xFFB3261E)
              : (resultado.enviada
                  ? const Color(0xFF2D7A00)
                  : const Color(0xFF795500)),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: rechazo != null ? 4 : 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

      // Vuelve a la cámara sin salir de la pantalla
      setState(() {
        _previewPath = null;
        _confirming  = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar evidencia: $e')),
      );
    }
  }

  void _retomar() => setState(() {
        _previewPath = null;
        _confirming  = false;
      });

  // ── Selector de procedimiento ──────────────────────────────────────────────

  Future<void> _abrirSelector() async {
    if (_svc == null) return;
    final resultado = await showModalBottomSheet<SeleccionProcedimientoCampo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SelectorSheet(service: _svc!),
    );
    if (resultado != null && mounted) {
      setState(() => _sel = resultado);
      await _guardarSeleccion(resultado, _etapa);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_previewPath != null) {
      return _VistaPreview(
        path: _previewPath!,
        etapa: _etapa,
        isConfirming: _confirming,
        onConfirm: _confirmar,
        onRetake: _retomar,
      );
    }

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
          else if (!_ready)
            const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_kGreen)),
            )
          else
            CameraPreview(_ctrl!),

          // ── Overlay superior + banner offline ─────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OverlaySuperior(
                  sel: _sel,
                  onTap: _abrirSelector,
                  onClose: () => Navigator.pop(context),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: isOnlineNotifier,
                  builder: (_, online, _) {
                    if (online) return const SizedBox.shrink();
                    return ValueListenableBuilder<int>(
                      valueListenable: pendientesEvidenciaNotifier,
                      builder: (_, pendientes, _) => Container(
                        margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xCC7A4A00),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_outlined,
                                color: Colors.amber, size: 15),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pendientes > 0
                                    ? 'Sin conexión · $pendientes foto${pendientes == 1 ? '' : 's'} en cola'
                                    : 'Sin conexión · las fotos se guardarán en cola',
                                style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // ── Overlay inferior: etapa + botón captura ────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _OverlayInferior(
                etapa: _etapa,
                capturing: _capturing,
                enabled: _ready && _sel != null,
                onEtapaChanged: (e) async {
                  setState(() => _etapa = e);
                  if (_sel != null) await _guardarSeleccion(_sel!, e);
                },
                onCaptura: _capturar,
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
  final SeleccionProcedimientoCampo? sel;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _OverlaySuperior({
    required this.sel,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.camera_alt_outlined, color: _kGreen, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: sel == null
                  ? const Text(
                      'Toca para seleccionar procedimiento',
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
                          sel!.servicioNombre,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          sel!.procNombre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Icon(
              sel == null ? Icons.arrow_drop_down : Icons.edit_outlined,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Overlay inferior ─────────────────────────────────────────────────────────

class _OverlayInferior extends StatelessWidget {
  final String etapa;
  final bool capturing;
  final bool enabled;
  final ValueChanged<String> onEtapaChanged;
  final VoidCallback onCaptura;

  const _OverlayInferior({
    required this.etapa,
    required this.capturing,
    required this.enabled,
    required this.onEtapaChanged,
    required this.onCaptura,
  });

  static const _etapas = [
    ('antes',    'Antes'),
    ('durante',  'Durante'),
    ('despues',  'Después'),
  ];

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
          // Chips de etapa
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _etapas.map((t) {
              final (value, label) = t;
              final selected = etapa == value;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => onEtapaChanged(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected
                          ? _kGreen
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? _kGreen
                            : Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          // Botón de captura
          Opacity(
            opacity: enabled ? 1.0 : 0.35,
            child: _BtnCaptura(
              onTap: enabled ? onCaptura : null,
              capturing: capturing,
            ),
          ),
        ],
      ),
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
    return GestureDetector(
      onTap: onTap,
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
    );
  }
}

// ─── Vista de preview (confirmar / re-tomar) ──────────────────────────────────

class _VistaPreview extends StatelessWidget {
  final String path;
  final String etapa;
  final bool isConfirming;
  final VoidCallback onConfirm;
  final VoidCallback onRetake;

  const _VistaPreview({
    required this.path,
    required this.etapa,
    required this.isConfirming,
    required this.onConfirm,
    required this.onRetake,
  });

  String get _etapaLabel => switch (etapa) {
        'antes'   => 'Antes',
        'despues' => 'Después',
        _         => 'Durante',
      };

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
                        _etapaLabel,
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
                        label: Text(isConfirming ? 'Guardando…' : 'Confirmar'),
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

// ─── Sheet selector de 3 niveles ──────────────────────────────────────────────

class _SelectorSheet extends StatefulWidget {
  final ProyectoService service;
  const _SelectorSheet({required this.service});

  @override
  State<_SelectorSheet> createState() => _SelectorSheetState();
}

class _SelectorSheetState extends State<_SelectorSheet> {
  // Nivel de navegación: 0=proyectos, 1=servicios, 2=procedimientos
  int _nivel = 0;

  ProyectoItem? _proyecto;
  ServicioItem? _servicio;

  List<ProyectoItem> _proyectos = [];
  List<ServicioItem> _servicios = [];
  List<ProcedimientoDetalle> _procs = [];

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
      final data = await widget.service.getProyectos();
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
      final lista = await widget.service.getServiciosProyecto(proyecto.id);
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

  Future<void> _cargarProcedimientos(ServicioItem servicio) async {
    setState(() { _cargando = true; _errorMsg = null; _servicio = servicio; _nivel = 2; });
    try {
      final detalle = await widget.service.getDetalleServicio(servicio.id);
      if (!mounted) return;
      setState(() {
        _procs = detalle?.procedimientos ?? [];
        _cargando = false;
        _busqueda = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cargando = false; _errorMsg = 'Error al cargar procedimientos'; });
    }
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
        _ => _servicio?.nombre ?? 'Procedimientos',
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

          // Búsqueda (solo para proyecto y servicio)
          if (_nivel < 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: _nivel == 0 ? 'Buscar proyecto…' : 'Buscar servicio…',
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
                    _cargarProcedimientos(_servicio!);
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
      _ => _listaProcedimientos(),
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
          onTap: () => _cargarProcedimientos(s),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
        );
      },
    );
  }

  Widget _listaProcedimientos() {
    if (_procs.isEmpty) {
      return const Center(
        child: Text('Sin procedimientos en este servicio',
            style: TextStyle(color: Colors.white38)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: _procs.length,
      itemBuilder: (_, i) {
        final proc = _procs[i];
        final completado = proc.estado == 'completado';
        return _ItemLista(
          titulo: proc.nombre,
          subtitulo: completado ? 'Completado' : proc.estado,
          leading: Icon(
            completado
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: completado ? _kGreen : Colors.white38,
            size: 20,
          ),
          onTap: () => Navigator.pop(
            context,
            SeleccionProcedimientoCampo(
              procId:         proc.id,
              procNombre:     proc.nombre,
              servicioId:     _servicio!.id,
              servicioNombre: _servicio!.nombre,
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
