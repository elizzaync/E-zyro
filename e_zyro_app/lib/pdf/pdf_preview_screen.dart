import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

///
/// Reemplaza las pantallas de preview que vivían embebidas en `pantalla_tramites`
/// (`VistaPreviaPdfScreen`) e `informe_servicio_pdf` (`InformeServicioPreviewScreen`).
///
/// - Siempre permite imprimir y compartir (vía `printing`).
/// - Si se pasa [onConfirm], muestra un botón de acción (p. ej. "Confirmar y
///   Enviar" para subir la solicitud de permiso al backend).
class PdfPreviewScreen extends StatelessWidget {
  final Uint8List bytes;
  final String nombreArchivo;
  final String titulo;

  /// Acción opcional (botón inferior). Si es null, solo se previsualiza.
  final VoidCallback? onConfirm;
  final String confirmLabel;
  final IconData confirmIcon;

  const PdfPreviewScreen({
    super.key,
    required this.bytes,
    required this.nombreArchivo,
    this.titulo = 'Vista Previa',
    this.onConfirm,
    this.confirmLabel = 'Confirmar y Enviar',
    this.confirmIcon = Icons.cloud_upload,
  });

  /// Atajo: abre el visor en una ruta nueva.
  static Future<void> abrir(
    BuildContext context, {
    required Uint8List bytes,
    required String nombreArchivo,
    String titulo = 'Vista Previa',
    VoidCallback? onConfirm,
    String confirmLabel = 'Confirmar y Enviar',
    IconData confirmIcon = Icons.cloud_upload,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          bytes: bytes,
          nombreArchivo: nombreArchivo,
          titulo: titulo,
          onConfirm: onConfirm,
          confirmLabel: confirmLabel,
          confirmIcon: confirmIcon,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: Text(titulo, style: const TextStyle(fontSize: 16)),
      ),
      body: PdfPreview(
        build: (format) => bytes,
        allowPrinting: true,
        allowSharing: true,
        canChangeOrientation: false,
        canChangePageFormat: false,
        pdfFileName: nombreArchivo,
        loadingWidget: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Color(0xFF8FD11B)),
          ),
        ),
      ),
      floatingActionButton: onConfirm == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: const Color(0xFF8FD11B),
              onPressed: onConfirm,
              icon: Icon(confirmIcon, color: Colors.black),
              label: Text(
                confirmLabel,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
    );
  }
}
