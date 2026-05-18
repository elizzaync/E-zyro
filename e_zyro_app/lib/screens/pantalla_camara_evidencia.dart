import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/mantenimiento_models.dart';

class CameraEvidenciaScreen extends StatefulWidget {
  final String pasoNombre;
  final FotoTipo tipo;

  /// Paths already captured in this session (used to show progress overlay).
  final Map<FotoTipo, String?> capturedPaths;

  const CameraEvidenciaScreen({
    super.key,
    required this.pasoNombre,
    required this.tipo,
    required this.capturedPaths,
  });

  /// Returns [CaptureResult] with path + geolocation, or null if cancelled.
  static Future<CaptureResult?> open(
    BuildContext context, {
    required String pasoNombre,
    required FotoTipo tipo,
    required Map<FotoTipo, String?> capturedPaths,
  }) =>
      Navigator.push<CaptureResult>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraEvidenciaScreen(
            pasoNombre: pasoNombre,
            tipo: tipo,
            capturedPaths: capturedPaths,
          ),
          fullscreenDialog: true,
        ),
      );

  @override
  State<CameraEvidenciaScreen> createState() => _CameraEvidenciaScreenState();
}

class _CameraEvidenciaScreenState extends State<CameraEvidenciaScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  bool _ready = false;
  bool _capturing = false;
  String? _error;

  // Preview state
  String? _rawPath;
  double? _lat;
  double? _lng;
  double? _accuracy;
  bool _confirming = false;

  static const _green = Color(0xFF8FD11B);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndInit();
  }

  Future<void> _checkPermissionAndInit() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _initCamera();
    } else if (status.isPermanentlyDenied) {
      setState(() =>
          _error = 'Permiso de cámara denegado permanentemente.');
      _showPermissionDialog(
        title: 'Permiso de cámara requerido',
        message:
            'Esta función necesita acceso a la cámara para capturar evidencias del mantenimiento. Habilita el permiso en Ajustes del dispositivo.',
      );
    } else {
      setState(() =>
          _error = 'Se requiere permiso de cámara para capturar evidencias.');
    }
  }

  void _showPermissionDialog({required String title, required String message}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await openAppSettings();
              },
              child: const Text('Ir a Ajustes'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No se encontró cámara disponible');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final ctrl =
          CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _ctrl = ctrl;
        _ready = true;
      });
    } catch (e) {
      setState(() => _error = 'Error al inicializar cámara: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
      setState(() => _ready = false);
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

  Future<void> _capture() async {
    if (_ctrl == null || !_ready || _capturing) return;
    setState(() => _capturing = true);
    try {
      final xFile = await _ctrl!.takePicture();

      // Request location alongside capture — fail silently if denied
      double? lat, lng, accuracy;
      try {
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.whileInUse ||
            perm == LocationPermission.always) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.medium),
          ).timeout(const Duration(seconds: 5));
          lat = pos.latitude;
          lng = pos.longitude;
          accuracy = pos.accuracy;
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _rawPath = xFile.path;
        _lat = lat;
        _lng = lng;
        _accuracy = accuracy;
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

  Future<void> _confirm() async {
    final raw = _rawPath;
    if (raw == null) return;
    setState(() => _confirming = true);
    try {
      final dir = await getTemporaryDirectory();
      final destPath =
          '${dir.path}/ev_${widget.tipo.apiValue}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final result = await FlutterImageCompress.compressAndGetFile(
        raw,
        destPath,
        quality: 75,
        minWidth: 1280,
        minHeight: 720,
      );

      final finalPath = result?.path ?? raw;
      if (mounted) {
        Navigator.pop(
          context,
          CaptureResult(
            path: finalPath,
            lat: _lat,
            lng: _lng,
            accuracy: _accuracy,
          ),
        );
      }
    } catch (e) {
      setState(() => _confirming = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar imagen: $e')),
        );
      }
    }
  }

  void _retake() => setState(() {
        _rawPath = null;
        _lat = null;
        _lng = null;
        _accuracy = null;
      });

  @override
  Widget build(BuildContext context) {
    // Show preview after capture
    if (_rawPath != null) {
      return _PreviewPage(
        path: _rawPath!,
        tipo: widget.tipo,
        isConfirming: _confirming,
        onConfirm: _confirm,
        onRetake: _retake,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ─────────────────────────────────────────────
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
                  valueColor: AlwaysStoppedAnimation(_green)),
            )
          else
            CameraPreview(_ctrl!),

          // ── Top bar ────────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  pasoNombre: widget.pasoNombre,
                  tipo: widget.tipo,
                  capturedPaths: widget.capturedPaths,
                  onClose: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // ── Bottom capture button ──────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: _CaptureButton(
                    onTap: _ready && !_capturing ? _capture : null,
                    isCapturing: _capturing,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Preview page (Re-tomar / Confirmar) ──────────────────────────────────────

class _PreviewPage extends StatelessWidget {
  final String path;
  final FotoTipo tipo;
  final bool isConfirming;
  final VoidCallback onConfirm;
  final VoidCallback onRetake;

  const _PreviewPage({
    required this.path,
    required this.tipo,
    required this.isConfirming,
    required this.onConfirm,
    required this.onRetake,
  });

  static const _green = Color(0xFF8FD11B);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen image preview
          Image.file(File(path), fit: BoxFit.contain),

          // Top label
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                        color: _green.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _green),
                      ),
                      child: Text(
                        tipo.label,
                        style: const TextStyle(
                          color: _green,
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

          // Bottom action buttons
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
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Icon(Icons.check),
                        label:
                            Text(isConfirming ? 'Procesando…' : 'Confirmar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
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

// ─── Top overlay bar ──────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String pasoNombre;
  final FotoTipo tipo;
  final Map<FotoTipo, String?> capturedPaths;
  final VoidCallback onClose;

  const _TopBar({
    required this.pasoNombre,
    required this.tipo,
    required this.capturedPaths,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pasoNombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child:
                    const Icon(Icons.close, color: Colors.white, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: FotoTipo.values.map((t) {
              final isDone = capturedPaths[t] != null;
              final isCurrent = t == tipo;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _TipoChip(
                    tipo: t, isDone: isDone, isCurrent: isCurrent),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final FotoTipo tipo;
  final bool isDone;
  final bool isCurrent;

  const _TipoChip(
      {required this.tipo, required this.isDone, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8FD11B);
    final color = isDone
        ? green
        : isCurrent
            ? Colors.white
            : Colors.white.withValues(alpha: 0.35);

    return Row(
      children: [
        Icon(
          isDone ? Icons.check_circle : Icons.radio_button_unchecked,
          color: color,
          size: 14,
        ),
        const SizedBox(width: 4),
        Text(
          tipo.label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        if (tipo != FotoTipo.despues)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4), size: 14),
          ),
      ],
    );
  }
}

// ─── Capture button ───────────────────────────────────────────────────────────

class _CaptureButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isCapturing;

  const _CaptureButton({this.onTap, required this.isCapturing});

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
            width: isCapturing ? 52 : 58,
            height: isCapturing ? 52 : 58,
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
