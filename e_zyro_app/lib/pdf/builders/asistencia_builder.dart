import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/asistencia_models.dart';
import '../pdf_theme.dart';

/// Reporte de **Asistencia por usuario**.
///
/// Documento dinámico (la tabla crece con los registros) generado por código
/// con el membrete común [PdfTheme]. Cuando el usuario entregue una plantilla
/// oficial de 1 hoja, se puede migrar a overlay (`PdfOverlay`).
class AsistenciaBuilder {
  AsistenciaBuilder._();

  static const _titulo = 'REPORTE DE ASISTENCIA';

  static Future<Uint8List> build({
    required String usuario,
    required List<RegistroAsistencia> registros,
  }) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();
    final fFecha = DateFormat('dd/MM/yyyy');
    final fHora = DateFormat('HH:mm');

    final ordenados = [...registros]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
          pw.Text('Colaborador: $usuario',
              style: pw.TextStyle(fontSize: 10, color: PdfTheme.ink, font: bold)),
          pw.SizedBox(height: 2),
          pw.Text('Emitido: $emit   ·   Registros: ${ordenados.length}',
              style: pw.TextStyle(
                  fontSize: 8, color: PdfTheme.muted, font: regular)),
          PdfTheme.section('Detalle de Marcaciones', bold: bold),
          if (ordenados.isEmpty)
            pw.Text('Sin registros de asistencia en el periodo.',
                style: pw.TextStyle(
                    fontSize: 9, color: PdfTheme.muted, font: regular))
          else
            _tabla(ordenados, fFecha, fHora, bold: bold, regular: regular),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _tabla(
    List<RegistroAsistencia> regs,
    DateFormat fFecha,
    DateFormat fHora, {
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(70),
        1: pw.FixedColumnWidth(46),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(1.4),
        4: pw.FixedColumnWidth(44),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg),
          children: [
            PdfTheme.th('Fecha', bold),
            PdfTheme.th('Hora', bold),
            PdfTheme.th('Tipo', bold),
            PdfTheme.th('Estado', bold),
            PdfTheme.th('Score', bold),
          ],
        ),
        for (final r in regs)
          pw.TableRow(children: [
            PdfTheme.td(fFecha.format(r.timestamp), regular),
            PdfTheme.td(fHora.format(r.timestamp), regular),
            PdfTheme.td(_tipoLabel(r.tipo), regular, color: PdfTheme.ink),
            PdfTheme.td(
              r.estado.isEmpty
                  ? '—'
                  : '${r.estado[0].toUpperCase()}${r.estado.substring(1)}',
              bold,
              color: r.estado == 'validado' ? PdfTheme.accent : PdfTheme.muted,
              size: 7.5,
            ),
            PdfTheme.td('${r.score.round()}', regular, size: 7.5),
          ]),
      ],
    );
  }

  static String _tipoLabel(String t) => switch (t) {
        'ENTRADA' => 'Entrada',
        'SALIDA' => 'Salida',
        'ENTRADA_ALMUERZO' => 'Entrada almuerzo',
        'SALIDA_ALMUERZO' => 'Salida almuerzo',
        _ => t,
      };
}
