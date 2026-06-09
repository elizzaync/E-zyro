import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/personal_models.dart';
import '../pdf_theme.dart';

/// **Historial de Personal** — ficha consolidada de un empleado.
///
/// Documento dinámico con el membrete común [PdfTheme]: datos del colaborador,
/// contratos, resumen de asistencia, solicitudes, EPP entregado y evaluaciones.
class HistorialPersonalBuilder {
  HistorialPersonalBuilder._();

  static const _titulo = 'HISTORIAL DE PERSONAL';

  static Future<Uint8List> build({required HistorialPersonal h}) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();
    final emp = h.empleado;
    final emit = DateFormat('d MMMM y', 'es_ES').format(DateTime.now());

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: PdfTheme.pageMargin,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (ctx) => PdfTheme.header(ctx, titulo: _titulo, bold: bold, regular: regular),
        footer: (ctx) => PdfTheme.footer(ctx, regular: regular),
        build: (ctx) => [
          pw.Text(emp.nombre ?? emp.id,
              style: pw.TextStyle(fontSize: 12, color: PdfTheme.ink, font: bold)),
          pw.SizedBox(height: 2),
          pw.Text('Emitido: $emit',
              style: pw.TextStyle(fontSize: 8, color: PdfTheme.muted, font: regular)),

          PdfTheme.section('Datos del colaborador', bold: bold),
          _fichaDatos(emp, bold: bold, regular: regular),

          PdfTheme.section('Contratos', bold: bold),
          if (h.contratos.isEmpty)
            _vacio('Sin contratos registrados.', regular)
          else
            _tablaContratos(h.contratos, bold: bold, regular: regular),

          PdfTheme.section('Resumen de asistencia', bold: bold),
          _resumenAsistencia(h.asistencia, bold: bold, regular: regular),

          PdfTheme.section('Solicitudes (permisos / vacaciones)', bold: bold),
          if (h.solicitudes.isEmpty)
            _vacio('Sin solicitudes registradas.', regular)
          else
            _tablaSolicitudes(h.solicitudes, bold: bold, regular: regular),

          PdfTheme.section('EPP entregado', bold: bold),
          if (h.epp.isEmpty)
            _vacio('Sin entregas de EPP.', regular)
          else
            _tablaEpp(h.epp, bold: bold, regular: regular),

          PdfTheme.section('Evaluaciones de desempeño', bold: bold),
          _resumenEval(h.evaluaciones, bold: bold, regular: regular),
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _vacio(String t, pw.Font regular) => pw.Text(t,
      style: pw.TextStyle(fontSize: 9, color: PdfTheme.muted, font: regular));

  static pw.Widget _fichaDatos(Empleado e, {required pw.Font bold, required pw.Font regular}) {
    final filas = <(String, String)>[
      ('Código', e.codigo ?? '—'),
      ('Cargo', e.cargo ?? '—'),
      ('Área', e.area ?? '—'),
      ('Tipo', e.tipo ?? '—'),
      ('Ingreso', _fmt(e.fechaIngreso)),
      ('Fin contrato', _fmt(e.fechaFinContrato)),
      ('Estado', e.activo ? 'Activo' : 'Inactivo'),
    ];
    return pw.Wrap(
      spacing: 24, runSpacing: 6,
      children: [
        for (final (k, v) in filas)
          pw.SizedBox(
            width: 150,
            child: pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(text: '$k: ',
                    style: pw.TextStyle(fontSize: 8.5, color: PdfTheme.muted, font: bold)),
                pw.TextSpan(text: v,
                    style: pw.TextStyle(fontSize: 8.5, color: PdfTheme.ink, font: regular)),
              ]),
            ),
          ),
      ],
    );
  }

  static pw.Widget _tablaContratos(List<ContratoItem> cs, {required pw.Font bold, required pw.Font regular}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg), children: [
          PdfTheme.th('Tipo', bold), PdfTheme.th('Inicio', bold),
          PdfTheme.th('Fin', bold), PdfTheme.th('Estado', bold),
        ]),
        for (final c in cs)
          pw.TableRow(children: [
            PdfTheme.td(c.tipo, regular),
            PdfTheme.td(_fmt(c.fechaInicio), regular),
            PdfTheme.td(_fmt(c.fechaFin), regular),
            PdfTheme.td(c.estado ?? '—', regular),
          ]),
      ],
    );
  }

  static pw.Widget _resumenAsistencia(AsistenciaResumen a, {required pw.Font bold, required pw.Font regular}) {
    pw.Widget chip(String k, int v) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfTheme.hdrBg, borderRadius: pw.BorderRadius.circular(4)),
          child: pw.RichText(text: pw.TextSpan(children: [
            pw.TextSpan(text: '$v  ',
                style: pw.TextStyle(fontSize: 11, color: PdfTheme.ink, font: bold)),
            pw.TextSpan(text: k,
                style: pw.TextStyle(fontSize: 8, color: PdfTheme.muted, font: regular)),
          ])),
        );
    return pw.Row(children: [
      chip('Total', a.total), pw.SizedBox(width: 8),
      chip('Validados', a.validados), pw.SizedBox(width: 8),
      chip('Pendientes', a.pendientes), pw.SizedBox(width: 8),
      chip('Rechazados', a.rechazados),
    ]);
  }

  static pw.Widget _tablaSolicitudes(List<SolicitudItem> ss, {required pw.Font bold, required pw.Font regular}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg), children: [
          PdfTheme.th('Tipo', bold), PdfTheme.th('Desde', bold),
          PdfTheme.th('Hasta', bold), PdfTheme.th('Estado', bold),
        ]),
        for (final s in ss)
          pw.TableRow(children: [
            PdfTheme.td(s.tipo, regular),
            PdfTheme.td(_fmt(s.fechaInicio), regular),
            PdfTheme.td(_fmt(s.fechaFin), regular),
            PdfTheme.td(s.estado ?? '—', regular),
          ]),
      ],
    );
  }

  static pw.Widget _tablaEpp(List<EppEntregaItem> es, {required pw.Font bold, required pw.Font regular}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      children: [
        pw.TableRow(decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg), children: [
          PdfTheme.th('Fecha', bold), PdfTheme.th('Ítems', bold), PdfTheme.th('Estado', bold),
        ]),
        for (final e in es)
          pw.TableRow(children: [
            PdfTheme.td(_fmt(e.fecha), regular),
            PdfTheme.td('${e.items}', regular),
            PdfTheme.td(e.estado ?? '—', regular),
          ]),
      ],
    );
  }

  static pw.Widget _resumenEval(EvaluacionResumen e, {required pw.Font bold, required pw.Font regular}) {
    final prom = e.promedioGeneral == null ? '—' : '${e.promedioGeneral!.toStringAsFixed(2)} / 10';
    return pw.Row(children: [
      pw.Text('Evaluaciones: ',
          style: pw.TextStyle(fontSize: 9, color: PdfTheme.muted, font: bold)),
      pw.Text('${e.total}   ',
          style: pw.TextStyle(fontSize: 9, color: PdfTheme.ink, font: regular)),
      pw.Text('Promedio: ',
          style: pw.TextStyle(fontSize: 9, color: PdfTheme.muted, font: bold)),
      pw.Text('$prom   ',
          style: pw.TextStyle(fontSize: 9, color: PdfTheme.accent, font: bold)),
      pw.Text('Último periodo: ',
          style: pw.TextStyle(fontSize: 9, color: PdfTheme.muted, font: bold)),
      pw.Text(e.ultimoPeriodo ?? '—',
          style: pw.TextStyle(fontSize: 9, color: PdfTheme.ink, font: regular)),
    ]);
  }

  static String _fmt(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '—' : DateFormat('dd/MM/yyyy').format(d);
  }
}
