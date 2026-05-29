import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle, ByteData;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Helpers para construir PDFs **superponiendo datos sobre una plantilla
/// pre-diseñada** (el modelo estándar de e-zyro para documentos de formato
/// fijo: permiso, asistencia de 1 hoja, constancias…).
///
/// El usuario entrega la plantilla (PDF) en `assets/plantillas/` y aquí solo se
/// "estampan" los textos/imágenes en coordenadas. En syncfusion el origen
/// (0,0) es la esquina **superior-izquierda**; A4 = 595 x 842 pt.
///
/// Uso:
/// ```dart
/// final pdf = PdfOverlay('assets/plantillas/plantilla_x.pdf');
/// await pdf.cargar();
/// pdf.texto('Juan', const Offset(120, 90));
/// final bytes = pdf.guardar();
/// ```
class PdfOverlay {
  PdfOverlay(this.assetPath);

  /// Ruta del asset de la plantilla (registrado en pubspec).
  final String assetPath;

  late PdfDocument _document;
  PdfPage? _page;

  // Fuentes estándar reutilizables.
  static final PdfFont fuente = PdfStandardFont(PdfFontFamily.helvetica, 10);
  static final PdfFont fuenteBold =
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
  static final PdfFont fuenteSmall = PdfStandardFont(PdfFontFamily.helvetica, 9);
  static final PdfFont fuenteCheck =
      PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);

  /// Carga la plantilla desde assets. Debe llamarse antes de estampar.
  Future<void> cargar() async {
    final ByteData bytes = await rootBundle.load(assetPath);
    _document = PdfDocument(inputBytes: bytes.buffer.asUint8List());
    _page = _document.pages[0];
  }

  PdfPage get page => _page!;

  /// Estampa texto en una posición. No hace nada si [text] está vacío.
  void texto(String text, Offset pos,
      {PdfFont? font, double anchoMax = 500, double altoMax = 50}) {
    if (text.isEmpty) return;
    page.graphics.drawString(
      text,
      font ?? fuente,
      brush: PdfSolidBrush(PdfColor(0, 0, 0)),
      bounds: Rect.fromLTWH(pos.dx, pos.dy, anchoMax, altoMax),
    );
  }

  /// Marca una casilla ("X") en una posición.
  void check(Offset pos) => texto('X', pos, font: fuenteCheck);

  /// Dibuja una imagen (p. ej. la firma) en un rectángulo. Silencioso si falla.
  void imagen(Uint8List? bytes, Rect destino) {
    if (bytes == null) return;
    try {
      page.graphics.drawImage(PdfBitmap(bytes), destino);
    } catch (_) {/* imagen inválida → se omite */}
  }

  /// Serializa el documento y libera recursos.
  Uint8List guardar() {
    final bytes = _document.saveSync();
    _document.dispose();
    return Uint8List.fromList(bytes);
  }
}
