import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

import '../core/app_constants.dart';

const _green = Color(0xFF8FD11B);
const _danger = Color(0xFFD6584F);

/// Hoja de captura de firma reutilizable. Devuelve (vía Navigator.pop) un
/// string con la firma: un data-url base64 (firma dibujada / de galería) o la
/// URL de la firma guardada en la nube. El backend acepta ambos y los persiste.
///
/// Reusa el patrón de `_FirmaRecepcionSheet` (HU-16) pero como widget público
/// para poder invocarse desde cualquier pantalla (p. ej. entrega de préstamos).
class FirmaSheet extends StatefulWidget {
  final String titulo;
  final String? subtitulo;
  final String textoBoton;
  const FirmaSheet({
    super.key,
    this.titulo = 'Firmar',
    this.subtitulo,
    this.textoBoton = 'Confirmar firma',
  });

  /// Abre la hoja y devuelve el string de firma, o null si se cancela.
  static Future<String?> mostrar(
    BuildContext context, {
    String titulo = 'Firmar',
    String? subtitulo,
    String textoBoton = 'Confirmar firma',
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FirmaSheet(
        titulo: titulo,
        subtitulo: subtitulo,
        textoBoton: textoBoton,
      ),
    );
  }

  @override
  State<FirmaSheet> createState() => _FirmaSheetState();
}

class _FirmaSheetState extends State<FirmaSheet> {
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
    if (_usarGuardada && _firmaGuardadaUrl != null) {
      Navigator.pop(context, _firmaGuardadaUrl);
      return;
    }
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
                Expanded(
                  child: Text(widget.titulo,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: muted, size: 20),
                ),
              ],
            ),
            if (widget.subtitulo != null) ...[
              const SizedBox(height: 2),
              Text(widget.subtitulo!,
                  style: TextStyle(color: muted, fontSize: 12)),
            ],
            const SizedBox(height: 14),
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
                    child: Text(widget.textoBoton,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
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
