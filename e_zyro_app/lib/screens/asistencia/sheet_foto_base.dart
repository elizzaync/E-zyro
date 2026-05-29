// Sheet: subir foto biometrica base (camara live).
part of '../pantalla_asistencia.dart';

// ── Sheet: Subir foto biométrica base (cámara live) ──────────────────────────
class _SubirFotoBaseSheet extends StatefulWidget {
  final AsistenciaService service;
  final void Function() onConfigured;

  const _SubirFotoBaseSheet({required this.service, required this.onConfigured});

  @override
  State<_SubirFotoBaseSheet> createState() => _SubirFotoBaseSheetState();
}

class _SubirFotoBaseSheetState extends State<_SubirFotoBaseSheet> {
  XFile?  _captured;
  bool    _isSaving = false;
  String? _errorMsg;

  Future<void> _openCamera() async {
    final photo = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(builder: (_) => const _FullScreenCameraPage()),
    );
    if (photo != null && mounted) {
      setState(() { _captured = photo; _errorMsg = null; });
    }
  }

  void _retake() => setState(() { _captured = null; _errorMsg = null; });

  Future<void> _save() async {
    if (_captured == null) {
      setState(() => _errorMsg = 'Primero captura tu foto de referencia');
      return;
    }
    setState(() { _isSaving = true; _errorMsg = null; });
    try {
      await widget.service.subirFotoBase(File(_captured!.path));
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onConfigured();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMsg = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    const green   = Color(0xFF8FD11B);

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.face_retouching_natural, color: Colors.orange, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Foto Biométrica', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('Centra tu cara · buena iluminación · mira directo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Área de foto
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _captured == null
                  ? GestureDetector(
                      onTap: _openCamera,
                      child: Container(
                        width: double.infinity, height: 220,
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.45), width: 2),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_outlined, size: 52, color: Colors.orange),
                            SizedBox(height: 12),
                            Text('Tomar foto biométrica', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 15)),
                            SizedBox(height: 4),
                            Text('Toca para abrir la cámara', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(File(_captured!.path), width: double.infinity, height: 280, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 12, left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: green.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(20)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, color: Colors.white, size: 13),
                                SizedBox(width: 4),
                                Text('Foto capturada', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                        if (_isSaving)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(16)),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B))),
                                  SizedBox(height: 12),
                                  Text('Subiendo al servidor...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  SizedBox(height: 4),
                                  Text('Procesando foto biométrica', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),

            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 12))),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 18),

            // Botones
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _isSaving
                  ? SizedBox(
                      width: double.infinity, height: 54,
                      child: ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          disabledBackgroundColor: Colors.orange.withValues(alpha: 0.55),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                            SizedBox(width: 12),
                            Text('Subiendo foto...', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    )
                  : _captured != null
                      ? Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _retake,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Retomar'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  side: const BorderSide(color: Colors.orange),
                                  foregroundColor: Colors.orange,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _save,
                                icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                                label: const Text('Guardar foto', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ),
                          ],
                        )
                      : SizedBox(
                          width: double.infinity, height: 54,
                          child: ElevatedButton.icon(
                            onPressed: _openCamera,
                            icon: const Icon(Icons.camera_alt, size: 20),
                            label: const Text('Abrir cámara', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

