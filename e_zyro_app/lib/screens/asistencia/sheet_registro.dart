// Sheet: registrar asistencia (entrada/salida).
part of '../pantalla_asistencia.dart';

// ── Sheet: Registrar asistencia ───────────────────────────────────────────────
class _RegistroSheet extends StatefulWidget {
  final String tipo;
  final Position? position;
  final String? addressLine1;
  final String? addressLine2;
  final AsistenciaService service;
  final void Function(MarcarResponse) onCompleted;

  const _RegistroSheet({
    required this.tipo,
    required this.position,
    required this.addressLine1,
    required this.addressLine2,
    required this.service,
    required this.onCompleted,
  });

  @override
  State<_RegistroSheet> createState() => _RegistroSheetState();
}

class _RegistroSheetState extends State<_RegistroSheet> {
  XFile? _selfie;
  bool _isLoading = false;
  String? _errorMsg;

  Future<void> _openCamera({String? hintMessage}) async {
    final photo = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenCameraPage(hintMessage: hintMessage),
      ),
    );
    if (photo != null && mounted) {
      setState(() { _selfie = photo; _errorMsg = null; });
    }
  }

  void _retake() => setState(() { _selfie = null; _errorMsg = null; });

  static bool _esFaceImageError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('rostro') ||
        lower.contains('cara') ||
        lower.contains('iluminac') ||
        lower.contains('selfie') ||
        lower.contains('detectó') ||
        lower.contains('detecto') ||
        lower.contains('detectado') ||
        lower.contains('imagen') ||
        lower.contains('face') ||
        lower.contains('foto');
  }

  Future<void> _submit() async {
    if (_selfie == null) {
      setState(() => _errorMsg = 'Por favor toma una selfie para continuar');
      return;
    }
    setState(() { _isLoading = true; _errorMsg = null; });
    try {
      final result = await widget.service.marcar(
        selfieFile: File(_selfie!.path),
        tipo: widget.tipo,
        latitud:    widget.position?.latitude,
        longitud:   widget.position?.longitude,
        precisionM: widget.position?.accuracy,
        altitud:    widget.position?.altitude,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onCompleted(result);
      }
    } catch (e) {
      if (!mounted) return;
      final errMsg = e.toString().replaceAll('Exception: ', '');
      if (_esFaceImageError(errMsg)) {
        // Error de imagen/rostro: volver a la cámara mostrando el motivo como guía
        setState(() { _isLoading = false; _selfie = null; _errorMsg = null; });
        _openCamera(hintMessage: errMsg);
      } else {
        setState(() { _isLoading = false; _errorMsg = errMsg; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final surface   = Theme.of(context).colorScheme.surface;
    const green     = Color(0xFF8FD11B);
    final now       = DateTime.now();
    final isEntrada = widget.tipo == 'ENTRADA';
    final tipoColor = isEntrada ? green : Colors.orange;
    String pad(int n) => n.toString().padLeft(2, '0');

    return Container(
      decoration: BoxDecoration(color: surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: tipoColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(isEntrada ? Icons.login : Icons.logout, color: tipoColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Registrar ${widget.tipo}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                          '${pad(now.day)}/${pad(now.month)}/${now.year}  ·  ${pad(now.hour)}:${pad(now.minute)}',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (widget.position != null ? green : Colors.orange).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (widget.position != null ? green : Colors.orange).withValues(alpha: 0.25)),
                ),
                child: widget.position != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.location_on, color: Color(0xFF8FD11B), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.addressLine1 != null)
                                      Text(widget.addressLine1!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    if (widget.addressLine2 != null)
                                      Text(widget.addressLine2!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                    if (widget.addressLine1 == null)
                                      Text(
                                        '${widget.position!.latitude.toStringAsFixed(5)}, ${widget.position!.longitude.toStringAsFixed(5)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                                child: Text(
                                  '±${widget.position!.accuracy.toStringAsFixed(0)}m',
                                  style: const TextStyle(color: Color(0xFF8FD11B), fontSize: 11, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          if (widget.addressLine1 != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${widget.position!.latitude.toStringAsFixed(5)}, ${widget.position!.longitude.toStringAsFixed(5)}',
                              style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
                            ),
                          ],
                        ],
                      )
                    : const Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Text('Sin ubicación GPS — se registrará sin coordenadas',
                              style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ],
                      ),
              ),
              const SizedBox(height: 20),

              const Text('Verificación Facial', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 10),

              if (_selfie == null)
                GestureDetector(
                  onTap: _isLoading ? null : _openCamera,
                  child: Container(
                    width: double.infinity, height: 160,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isDark ? Colors.grey.shade700 : Colors.grey.shade300),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo_outlined, size: 46, color: Colors.grey.shade400),
                        const SizedBox(height: 10),
                        Text('Tomar selfie', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Toca para abrir la cámara', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(File(_selfie!.path), width: double.infinity, height: 220, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 10, right: 10,
                      child: GestureDetector(
                        onTap: _isLoading ? null : _retake,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(20)),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh, color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text('Retomar', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_isLoading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16)),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8FD11B))),
                              SizedBox(height: 12),
                              Text('Verificando identidad...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              SizedBox(height: 4),
                              Text('Comparando con foto biométrica del servidor', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Container(
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
              ],

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity, height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: green.withValues(alpha: 0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                            SizedBox(width: 12),
                            Text('Verificando...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.fingerprint, size: 22),
                            SizedBox(width: 10),
                            Text('Verificar y Registrar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

