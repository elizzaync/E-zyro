import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Modelo/estilo corporativo común para los PDF generados por código
/// (`package:pdf`). Centraliza la paleta, fuentes, membrete (encabezado/pie) y
/// helpers de tabla para que TODOS los reportes dinámicos (informe de servicio,
/// salidas de logística, asistencia, gantt…) compartan la misma identidad
/// visual de E-System TIC.
///
/// Para documentos de **formato fijo** que se rellenan sobre una plantilla
/// pre-diseñada, ver `pdf_overlay.dart`.
class PdfTheme {
  PdfTheme._();

  // ── Paleta E-System ────────────────────────────────────────────────────────
  static const PdfColor ink    = PdfColor.fromInt(0xFF171F2E);
  static const PdfColor muted  = PdfColor.fromInt(0xFF667690);
  static const PdfColor rule   = PdfColor.fromInt(0xFFE2E6ED);
  static const PdfColor hdrBg  = PdfColor.fromInt(0xFFF5F7F8);
  static const PdfColor accent = PdfColor.fromInt(0xFF8FD11B);

  /// Fuentes con tildes (Noto Sans) para todos los documentos.
  static Future<(pw.Font regular, pw.Font bold)> fonts() async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    return (regular, bold);
  }

  static const pw.EdgeInsets pageMargin =
      pw.EdgeInsets.fromLTRB(44, 36, 44, 60);

  /// Encabezado corporativo. En la primera página muestra el título completo;
  /// en las siguientes, una versión compacta con "— CONT.".
  static pw.Widget header(
    pw.Context ctx, {
    required String titulo,
    required pw.Font bold,
    required pw.Font regular,
    String subtitulo = 'E-System TIC  ·  Gestión de Operaciones de Campo',
  }) {
    final isFirst = ctx.pageNumber == 1;
    if (isFirst) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(titulo,
              style: pw.TextStyle(fontSize: 14, font: bold, color: ink)),
          pw.SizedBox(height: 3),
          pw.Text(subtitulo,
              style: pw.TextStyle(fontSize: 8.5, font: regular, color: muted)),
          pw.SizedBox(height: 4),
          pw.Container(height: 1.5, color: accent),
          pw.SizedBox(height: 14),
        ],
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('$titulo — CONT.',
            style: pw.TextStyle(fontSize: 8.5, font: bold, color: ink)),
        pw.SizedBox(height: 3),
        pw.Container(height: 0.5, color: rule),
        pw.SizedBox(height: 10),
      ],
    );
  }

  /// Pie corporativo con paginación.
  static pw.Widget footer(
    pw.Context ctx, {
    required pw.Font regular,
    String leyenda =
        'E-System TIC Perú S.A.C. — Documento Técnico Confidencial · Sujeto a Control de Gestión',
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 0.5, color: rule),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(leyenda,
                style: pw.TextStyle(fontSize: 7, color: muted, font: regular)),
            pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
                style: pw.TextStyle(fontSize: 7, color: muted, font: regular)),
          ],
        ),
      ],
    );
  }

  /// Título de sección con regla inferior (estilo del informe de servicio).
  static pw.Widget section(String title,
      {required pw.Font bold}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(title.toUpperCase(),
              style: pw.TextStyle(fontSize: 7.5, color: muted, font: bold)),
          pw.SizedBox(height: 4),
          pw.Container(height: 0.5, color: rule),
          pw.SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Celda de encabezado de tabla.
  static pw.Widget th(String text, pw.Font font) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 7.5, color: muted, font: font)),
      );

  /// Celda de cuerpo de tabla.
  static pw.Widget td(String text, pw.Font font,
          {PdfColor color = ink, double size = 8}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: size, color: color, font: font)),
      );
}
