// Modal de captura de firma.
part of '../pantalla_tramites.dart';

// ─────────────────────────────────────────────
//  Modal de firma (Bottom Sheet)
// ─────────────────────────────────────────────

class _ModalFirma extends StatefulWidget {
  final Uint8List? firmaExistente;
  const _ModalFirma({this.firmaExistente});

  @override
  State<_ModalFirma> createState() => _ModalFirmaState();
}

class _ModalFirmaState extends State<_ModalFirma> {
  late final SignatureController _controller;
  bool _lienzo = true;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penColor: Colors.black,
      penStrokeWidth: 3.0,
      exportBackgroundColor: Colors.transparent,
    );
    if (widget.firmaExistente != null) _lienzo = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _seleccionarDeGaleria() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      Navigator.of(context).pop(await image.readAsBytes());
    }
  }

  Future<void> _confirmar() async {
    if (_lienzo) {
      if (_controller.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dibuja tu firma primero'),
            backgroundColor: _C.danger,
          ),
        );
        return;
      }
      final bytes = await _controller.toPngBytes();
      if (bytes != null && mounted) Navigator.of(context).pop(bytes);
    } else {
      Navigator.of(context).pop(widget.firmaExistente);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _C(context);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 20),
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.draw_outlined, color: _C.green, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Firma Digital',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Tabs Dibujar / Guardada
            if (widget.firmaExistente != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _tabBtn(
                      c,
                      'Dibujar nueva',
                      _lienzo ? null : () => setState(() => _lienzo = true),
                    ),
                    const SizedBox(width: 10),
                    _tabBtn(
                      c,
                      'Usar guardada',
                      !_lienzo ? null : () => setState(() => _lienzo = false),
                    ),
                  ],
                ),
              ),

            if (widget.firmaExistente != null) const SizedBox(height: 12),

            // Canvas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border, width: 2),
                    ),
                    height: 200,
                    child: _lienzo
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Signature(
                              controller: _controller,
                              backgroundColor: Colors.white,
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: widget.firmaExistente != null
                                ? Image.memory(
                                    widget.firmaExistente!,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                  )
                                : Center(
                                    child: Text(
                                      'Sin firma guardada',
                                      style: TextStyle(color: c.textMuted),
                                    ),
                                  ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  if (_lienzo)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _controller.clear(),
                          icon: Icon(
                            Icons.refresh,
                            size: 15,
                            color: c.textMuted,
                          ),
                          label: Text(
                            'Limpiar',
                            style: TextStyle(color: c.textMuted, fontSize: 13),
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(height: 32),
                ],
              ),
            ),

            if (_lienzo)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Firma en el recuadro blanco con tu dedo',
                  style: TextStyle(color: c.textMuted, fontSize: 12),
                ),
              ),

            // Botones
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: c.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: Text(
                            'Cancelar',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _confirmar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.green,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                          child: const Text(
                            'Confirmar Firma',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _seleccionarDeGaleria,
                      icon: Icon(
                        Icons.photo_library_outlined,
                        size: 18,
                        color: c.textPrimary,
                      ),
                      label: Text(
                        'Subir imagen desde la Galería',
                        style: TextStyle(color: c.textPrimary),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(_C c, String label, VoidCallback? onTap) {
    final active = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _C.green : c.inputBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? _C.green : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : c.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
