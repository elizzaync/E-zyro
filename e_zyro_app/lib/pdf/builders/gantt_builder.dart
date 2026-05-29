import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/proyecto_models.dart';
import '../pdf_theme.dart';

/// Cronograma **Gantt** de un proyecto: una barra por servicio sobre una escala
/// de días. Documento dinámico generado por código con el membrete común
/// [PdfTheme] (orientación horizontal para que quepa la línea de tiempo).
class GanttBuilder {
  GanttBuilder._();

  static const _titulo = 'CRONOGRAMA DEL PROYECTO (GANTT)';

  static Future<Uint8List> build({
    required ProyectoItem proyecto,
    required List<ServicioItem> servicios,
  }) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();
    final fFecha = DateFormat('dd/MM');

    DateTime? parse(String? s) => (s == null || s.isEmpty)
        ? null
        : DateTime.tryParse(s);

    // Calcular rango temporal global.
    final inicios = <DateTime>[];
    final fines = <DateTime>[];
    for (final s in servicios) {
      final sd = parse(s.fechaInicio) ?? parse(s.fechaProgramada);
      final ed = parse(s.fechaFin) ?? parse(s.fechaProgramada) ?? sd;
      if (sd != null) inicios.add(sd);
      if (ed != null) fines.add(ed);
    }
    final hayRango = inicios.isNotEmpty && fines.isNotEmpty;
    final minDate = hayRango
        ? inicios.reduce((a, b) => a.isBefore(b) ? a : b)
        : DateTime.now();
    final maxDate = hayRango
        ? fines.reduce((a, b) => a.isAfter(b) ? a : b)
        : DateTime.now().add(const Duration(days: 7));
    final totalDias = maxDate.difference(minDate).inDays.clamp(1, 100000) + 1;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: PdfTheme.pageMargin,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (ctx) =>
            PdfTheme.header(ctx, titulo: _titulo, bold: bold, regular: regular),
        footer: (ctx) => PdfTheme.footer(ctx, regular: regular),
        build: (ctx) => [
          pw.Text(proyecto.nombreProyecto,
              style: pw.TextStyle(fontSize: 11, color: PdfTheme.ink, font: bold)),
          pw.SizedBox(height: 2),
          pw.Text(
            'OT ${proyecto.ordenTrabajo}  ·  Cliente: ${proyecto.cliente}  ·  '
            '${hayRango ? "${fFecha.format(minDate)} – ${fFecha.format(maxDate)}" : "Sin fechas"}',
            style:
                pw.TextStyle(fontSize: 8, color: PdfTheme.muted, font: regular),
          ),
          PdfTheme.section('Servicios', bold: bold),
          if (servicios.isEmpty)
            pw.Text('El proyecto no tiene servicios.',
                style: pw.TextStyle(
                    fontSize: 9, color: PdfTheme.muted, font: regular))
          else
            ...servicios.map((s) => _fila(
                  s,
                  minDate: minDate,
                  totalDias: totalDias,
                  parse: parse,
                  fFecha: fFecha,
                  bold: bold,
                  regular: regular,
                )),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _fila(
    ServicioItem s, {
    required DateTime minDate,
    required int totalDias,
    required DateTime? Function(String?) parse,
    required DateFormat fFecha,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    final sd = parse(s.fechaInicio) ?? parse(s.fechaProgramada);
    final ed = parse(s.fechaFin) ?? parse(s.fechaProgramada) ?? sd;
    final offset = sd == null ? 0 : sd.difference(minDate).inDays;
    final dur = (sd != null && ed != null)
        ? (ed.difference(sd).inDays + 1).clamp(1, totalDias)
        : 1;
    final leftFrac = (offset / totalDias).clamp(0.0, 1.0);
    final widthFrac = (dur / totalDias).clamp(0.02, 1.0);

    final completado = s.estado.toLowerCase().contains('complet');

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // Etiqueta del servicio
          pw.SizedBox(
            width: 150,
            child: pw.Text(
              s.nombre,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(fontSize: 8, color: PdfTheme.ink, font: bold),
            ),
          ),
          // Pista + barra
          pw.Expanded(
            child: pw.Stack(
              children: [
                pw.Container(height: 12, color: PdfTheme.hdrBg),
                pw.LayoutBuilder(builder: (ctx, cons) {
                  final w = cons!.maxWidth;
                  return pw.Padding(
                    padding: pw.EdgeInsets.only(left: w * leftFrac),
                    child: pw.Container(
                      height: 12,
                      width: (w * widthFrac).clamp(3.0, w),
                      decoration: pw.BoxDecoration(
                        color: completado ? PdfTheme.accent : PdfTheme.muted,
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          // Rango de fechas
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              (sd != null && ed != null)
                  ? '${fFecha.format(sd)} – ${fFecha.format(ed)}'
                  : '—',
              style: pw.TextStyle(
                  fontSize: 7, color: PdfTheme.muted, font: regular),
            ),
          ),
        ],
      ),
    );
  }
}
