import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/requerimiento_models.dart';
import '../pdf_theme.dart';

/// Reporte de **Salidas de almacén / equipos de logística** (EPP, herramientas,
/// equipos). Toma los movimientos de stock y lista los de tipo `salida`.
///
/// Documento dinámico (tabla de N filas) generado por código con el membrete
/// común [PdfTheme].
class SalidasBuilder {
  SalidasBuilder._();

  static const _titulo = 'REPORTE DE SALIDAS DE ALMACÉN';

  static Future<Uint8List> build({
    required List<MovimientoStock> movimientos,
  }) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();
    final emit = DateFormat('d MMMM y', 'es_ES').format(DateTime.now());

    // Solo salidas, más recientes primero (fecha es String ISO/legible → orden
    // lexical inverso como aproximación estable).
    final salidas = movimientos.where((m) => m.tipo == 'salida').toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));

    final totalUnidades =
        salidas.fold<int>(0, (acc, m) => acc + m.cantidad);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: PdfTheme.pageMargin,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (ctx) =>
            PdfTheme.header(ctx, titulo: _titulo, bold: bold, regular: regular),
        footer: (ctx) => PdfTheme.footer(ctx, regular: regular),
        build: (ctx) => [
          pw.Text('Emitido: $emit',
              style: pw.TextStyle(
                  fontSize: 8, color: PdfTheme.muted, font: regular)),
          pw.SizedBox(height: 2),
          pw.Text(
              'Salidas: ${salidas.length}   ·   Unidades totales: $totalUnidades',
              style:
                  pw.TextStyle(fontSize: 9, color: PdfTheme.ink, font: bold)),
          PdfTheme.section('Detalle de Salidas', bold: bold),
          if (salidas.isEmpty)
            pw.Text('No hay salidas registradas.',
                style: pw.TextStyle(
                    fontSize: 9, color: PdfTheme.muted, font: regular))
          else
            _tabla(salidas, bold: bold, regular: regular),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _tabla(List<MovimientoStock> items,
      {required pw.Font bold, required pw.Font regular}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(64),
        1: pw.FlexColumnWidth(2.4),
        2: pw.FixedColumnWidth(34),
        3: pw.FixedColumnWidth(44),
        4: pw.FlexColumnWidth(1.6),
        5: pw.FlexColumnWidth(1.6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg),
          children: [
            PdfTheme.th('Fecha', bold),
            PdfTheme.th('Material / Equipo', bold),
            PdfTheme.th('Cant.', bold),
            PdfTheme.th('Unidad', bold),
            PdfTheme.th('Almacén', bold),
            PdfTheme.th('Responsable', bold),
          ],
        ),
        for (final m in items)
          pw.TableRow(children: [
            PdfTheme.td(m.fecha, regular, size: 7.5),
            PdfTheme.td(m.materialNombre, regular, color: PdfTheme.ink),
            PdfTheme.td('${m.cantidad}', bold),
            PdfTheme.td(m.unidad, regular, color: PdfTheme.muted, size: 7.5),
            PdfTheme.td(m.almacenNombre ?? '—', regular, size: 7.5),
            PdfTheme.td(m.responsableNombre ?? '—', regular, size: 7.5),
          ]),
      ],
    );
  }
}
