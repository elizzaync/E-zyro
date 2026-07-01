// Camara a pantalla completa (compartida por ambos flujos).
part of '../pantalla_asistencia.dart';

// ── Cámara a pantalla completa (compartida por ambos flujos) ──────────────────
class _FullScreenCameraPage extends StatefulWidget {
  /// Mensaje de error del intento anterior para mostrar como guía al usuario.
  final String? hintMessage;

  const _FullScreenCameraPage({this.hintMessage});

  @override
  State<_FullScreenCameraPage> createState() => _FullScreenCameraPageState();
}

class _FullScreenCameraPageState extends State<_FullScreenCameraPage> {
  CameraController? _ctrl;
  bool _ready = false;
  bool _confirming = false;
  XFile? _captured;
  String? _initError;
  bool _permDeniedForever = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    if (mounted)
      setState(() {
        _initError = null;
        _permDeniedForever = false;
      });
    final status = await Permission.camera.request();
    if (status.isPermanentlyDenied) {
      if (mounted) {
        setState(() {
          _initError =
              'Permiso de cámara bloqueado permanentemente.\nVe a Ajustes del dispositivo y habilítalo.';
          _permDeniedForever = true;
        });
      }
      return;
    }
    if (status.isDenied) {
      if (mounted) {
        setState(() {
          _initError = 'Se necesita permiso de cámara para continuar.';
        });
      }
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted)
          setState(
            () => _initError =
                'No se encontró ninguna cámara en este dispositivo.',
          );
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      try {
        await ctrl.setExposureMode(ExposureMode.auto);
        await ctrl.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() {
        _ctrl = ctrl;
        _ready = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _initError =
              'No se pudo iniciar la cámara.\nCierra otras apps que la estén usando e intenta de nuevo.';
        });
      }
    }
  }

  Future<void> _capture() async {
    if (_ctrl == null || !_ready) return;
    final photo = await _ctrl!.takePicture();
    await _ctrl!.pausePreview();
    if (mounted) setState(() => _captured = photo);
  }

  Future<void> _retake() async {
    await _ctrl?.resumePreview();
    if (mounted) setState(() => _captured = null);
  }

  /// Comprime, normaliza la selfie (aplica rotación EXIF) y aplica flip horizontal
  /// para que la foto quede igual a lo que el usuario vio en la vista previa de cámara frontal.
  Future<void> _confirm() async {
    final photo = _captured;
    if (photo == null || _confirming) return;
    setState(() => _confirming = true);
    try {
      final dir = await getTemporaryDirectory();
      final dest =
          '${dir.path}/selfie_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Primer paso: comprimir con corrección EXIF de rotación.
      final compressed = await FlutterImageCompress.compressAndGetFile(
        photo.path,
        dest,
        quality: 88,
        minWidth: 800,
        minHeight: 600,
      );
      final srcPath = compressed?.path ?? photo.path;

      // Segundo paso: flip horizontal para que coincida con la vista de espejo
      // que la cámara frontal muestra en la previsualización.
      final bytes = await File(srcPath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        final flipped = img.flipHorizontal(decoded);
        final jpegBytes = img.encodeJpg(flipped, quality: 88);
        await File(dest).writeAsBytes(jpegBytes);
        if (mounted) Navigator.pop(context, XFile(dest));
        return;
      }

      if (mounted) {
        Navigator.pop(
          context,
          compressed != null ? XFile(compressed.path) : photo,
        );
      }
    } catch (_) {
      if (mounted) Navigator.pop(context, photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF8FD11B);

    if (_initError != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  color: Colors.white38,
                  size: 80,
                ),
                const SizedBox(height: 24),
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                if (_permDeniedForever)
                  ElevatedButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    label: const Text('Abrir Ajustes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _initCamera,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Reintentar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_ready || _ctrl == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B)),
          ),
        ),
      );
    }

    if (_captured != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Transform para previsualizar con el mismo flip que aplicará _confirm()
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
              child: Image.file(File(_captured!.path), fit: BoxFit.cover),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _retake,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.refresh, color: Colors.white),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: green.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Foto tomada',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _retake,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retomar'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _confirming ? null : _confirm,
                          icon: _confirming
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check, size: 20),
                          label: Text(
                            _confirming ? 'Procesando...' : 'Usar foto',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _ctrl!.value.previewSize?.height ?? 100,
                height: _ctrl!.value.previewSize?.width ?? 100,
                child: CameraPreview(_ctrl!),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
          // Banner de error del intento anterior (orienta al usuario a corregir la foto)
          if (widget.hintMessage != null && _captured == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(62, 8, 12, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.hintMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            height: 1.35,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Center(
                  child: GestureDetector(
                    onTap: _capture,
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.white70, width: 4),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 16),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.black87,
                        size: 36,
                      ),
                    ),
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
