import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Escáner reutilizable de código de barras / QR (cámara).
///
/// Devuelve por `Navigator.pop` el texto decodificado del primer código leído,
/// o `null` si el usuario cancela. Incluye linterna y entrada manual de
/// respaldo (útil con pistolas físicas o cuando la cámara no enfoca).
///
/// Uso:
/// ```dart
/// final codigo = await ScannerCodigo.abrir(context);
/// if (codigo != null) { ... }
/// ```
class ScannerCodigo extends StatefulWidget {
  final String titulo;
  const ScannerCodigo({super.key, this.titulo = 'Escanear código'});

  static Future<String?> abrir(BuildContext context,
      {String titulo = 'Escanear código'}) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ScannerCodigo(titulo: titulo)),
    );
  }

  @override
  State<ScannerCodigo> createState() => _ScannerCodigoState();
}

class _ScannerCodigoState extends State<ScannerCodigo> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _handled = false; // evita múltiples pops por ráfaga de detecciones

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _devolver(String value) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context).pop(value.trim());
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _devolver(raw);
        return;
      }
    }
  }

  Future<void> _ingresoManual() async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ingresar código manualmente'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Código / N° de serie',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Usar')),
        ],
      ),
    );
    if (res != null && res.trim().isNotEmpty) _devolver(res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Cámara',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Marco guía central
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: Column(
              children: [
                const Text(
                  'Apunta la cámara al código QR / barras',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _ingresoManual,
                  icon: const Icon(Icons.keyboard, color: Colors.white),
                  label: const Text('Ingresar código manualmente',
                      style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
