import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../pdf/pdf_preview_screen.dart';
import 'abrir_enlace.dart';

/// Descarga un PDF remoto (p. ej. de Cloudinary) y lo muestra en el visor
/// in-app [PdfPreviewScreen] (con imprimir/compartir). Si la descarga falla,
/// cae al navegador externo ([abrirEnlace]) como respaldo.
///
/// Resuelve el problema de abrir un `.pdf` y ver solo la URL: en móvil el link
/// crudo de Cloudinary no siempre renderiza, así que lo descargamos y lo
/// pintamos nosotros.
Future<void> abrirPdfRemoto(
  BuildContext context,
  String? url, {
  String titulo = 'Documento',
  String? nombreArchivo,
}) async {
  if (url == null || url.isEmpty) return;

  Uint8List? bytes;
  try {
    final r = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
      bytes = r.bodyBytes;
    }
  } catch (_) {}

  if (bytes != null && context.mounted) {
    await PdfPreviewScreen.abrir(
      context,
      bytes: bytes,
      nombreArchivo: nombreArchivo ?? 'documento.pdf',
      titulo: titulo,
    );
    return;
  }
  // Respaldo: abrir en el navegador / visor externo.
  await abrirEnlace(url);
}
