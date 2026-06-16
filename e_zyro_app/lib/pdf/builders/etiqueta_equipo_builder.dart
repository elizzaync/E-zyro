import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../pdf_theme.dart';

/// Etiqueta imprimible de un equipo (formato tarjeta 85×54 mm) con **QR del
/// código interno** + datos legibles (nombre, código, marca/modelo, serie).
///
/// El QR codifica el `codigo` del equipo (ej. `TI-0001`), que es lo que busca
/// `GET /logistica/articulos/by-codigo/{codigo}` al escanear.
class EtiquetaEquipoBuilder {
  EtiquetaEquipoBuilder._();

  static Future<Uint8List> build({
    required String codigo,
    required String nombre,
    String? marca,
    String? modelo,
    String? numeroSerie,
  }) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();

    final marcaModelo = [marca, modelo]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' · ');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          85 * PdfPageFormat.mm,
          54 * PdfPageFormat.mm,
          marginAll: 5 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (ctx) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: codigo,
              width: 100,
              height: 100,
              drawText: false,
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    nombre,
                    maxLines: 3,
                    overflow: pw.TextOverflow.clip,
                    style: pw.TextStyle(
                        fontSize: 11, font: bold, color: PdfTheme.ink),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    codigo,
                    style: pw.TextStyle(
                        fontSize: 13, font: bold, color: PdfTheme.accent),
                  ),
                  if (marcaModelo.isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(marcaModelo,
                        style: pw.TextStyle(
                            fontSize: 8, font: regular, color: PdfTheme.muted)),
                  ],
                  if (numeroSerie != null && numeroSerie.trim().isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text('S/N: $numeroSerie',
                        style: pw.TextStyle(
                            fontSize: 8, font: regular, color: PdfTheme.muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
