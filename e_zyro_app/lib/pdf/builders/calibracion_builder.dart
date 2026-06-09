import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/calibracion_models.dart';
import '../pdf_theme.dart';

/// Reporte de **Historial de Calibraciones** de un equipo.
///
/// Documento dinámico (la tabla crece con los eventos) generado por código con
/// el membrete común [PdfTheme]. Una fila por calibración realizada, con su
/// próxima fecha, responsable, n° de certificado y resultado.
class CalibracionBuilder {
  CalibracionBuilder._();

  static const _titulo = 'HISTORIAL DE CALIBRACIONES';

  static Future<Uint8List> build({
    required String equipoNombre,
    required List<CalibracionEvento> eventos,
  }) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();

    final ordenados = [...eventos]..sort((a, b) =>
        (b.fechaRealizada ?? '').compareTo(a.fechaRealizada ?? ''));
    final emit = DateFormat('d MMMM y', 'es_ES').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: PdfTheme.pageMargin,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (ctx) =>
            PdfTheme.header(ctx, titulo: _titulo, bold: bold, regular: regular),
        footer: (ctx) => PdfTheme.footer(ctx, regular: regular),
        build: (ctx) => [
          pw.Text('Equipo: $equipoNombre',
              style: pw.TextStyle(fontSize: 10, color: PdfTheme.ink, font: bold)),
          pw.SizedBox(height: 2),
          pw.Text('Emitido: $emit   ·   Calibraciones: ${ordenados.length}',
              style: pw.TextStyle(fontSize: 8, color: PdfTheme.muted, font: regular)),
          PdfTheme.section('Detalle de Calibraciones', bold: bold),
          if (ordenados.isEmpty)
            pw.Text('Sin calibraciones registradas.',
                style: pw.TextStyle(fontSize: 9, color: PdfTheme.muted, font: regular))
          else
            _tabla(ordenados, bold: bold, regular: regular),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _tabla(
    List<CalibracionEvento> evs, {
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(58),  // realizada
        1: pw.FixedColumnWidth(58),  // próxima
        2: pw.FlexColumnWidth(1.6),  // realizada por
        3: pw.FlexColumnWidth(1.6),  // laboratorio
        4: pw.FlexColumnWidth(1.2),  // n° cert
        5: pw.FixedColumnWidth(54),  // resultado
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg),
          children: [
            PdfTheme.th('Realizada', bold),
            PdfTheme.th('Próxima', bold),
            PdfTheme.th('Realizada por', bold),
            PdfTheme.th('Laboratorio', bold),
            PdfTheme.th('N° Cert.', bold),
            PdfTheme.th('Resultado', bold),
          ],
        ),
        for (final e in evs)
          pw.TableRow(children: [
            PdfTheme.td(_fmt(e.fechaRealizada), regular),
            PdfTheme.td(_fmt(e.fechaProxima), regular, color: PdfTheme.muted),
            PdfTheme.td(e.realizadaPor ?? '—', regular),
            PdfTheme.td(e.empresaResponsable ?? '—', regular),
            PdfTheme.td(e.numeroCertificado ?? '—', regular, size: 7.5),
            PdfTheme.td(
              _resultadoLabel(e.resultado),
              bold,
              color: e.resultado == 'conforme' ? PdfTheme.accent : PdfTheme.muted,
              size: 7.5,
            ),
          ]),
      ],
    );
  }

  static String _fmt(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);
  }

  static String _resultadoLabel(String? r) => switch (r) {
        'conforme' => 'Conforme',
        'observado' => 'Observado',
        _ => '—',
      };
}
