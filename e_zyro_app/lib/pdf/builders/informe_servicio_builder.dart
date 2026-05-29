import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/proyecto_models.dart';
import '../pdf_theme.dart';

/// Builder del **Informe / Pre-Informe Técnico de Conformidad de Servicio**.
///
/// Documento dinámico (secciones y tablas que crecen) → se genera por código
/// con `package:pdf`, usando el membrete corporativo común de [PdfTheme].
/// Migrado desde `templates/informe_servicio_pdf.dart` (misma maquetación).
class InformeServicioBuilder {
  InformeServicioBuilder._();

  static const _titulo = 'INFORME TÉCNICO DE CONFORMIDAD DE SERVICIO';

  static Future<Uint8List> build({
    required ServicioDetalle detalle,
    required String tecnicoNombre,
  }) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();

    // Pre-cargar imágenes de evidencias (en paralelo).
    final imageBytes = <String, Uint8List>{};
    final urls = <String>{};
    for (final p in detalle.procedimientos) {
      for (final e in p.evidencias) {
        if (e.urlCloudinary.isNotEmpty) urls.add(e.urlCloudinary);
      }
    }
    await Future.wait(urls.map((url) async {
      try {
        final r = await http.get(Uri.parse(url));
        if (r.statusCode == 200) imageBytes[url] = r.bodyBytes;
      } catch (_) {/* ignore — se mostrará placeholder */}
    }));

    final emitDate = DateFormat('d MMMM y', 'es_ES').format(DateTime.now());
    final otLabel = detalle.id.length >= 8
        ? 'OT-${detalle.id.substring(0, 8).toUpperCase()}'
        : 'OT-${detalle.id.toUpperCase()}';

    final matsExtra = detalle.materialesSolicitados
        .where((m) => m.estadoReq == 'aprobado' || m.estadoReq == 'entregado')
        .toList();
    final procConEv =
        detalle.procedimientos.where((p) => p.evidencias.isNotEmpty).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: PdfTheme.pageMargin,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (ctx) =>
            PdfTheme.header(ctx, titulo: _titulo, bold: bold, regular: regular),
        footer: (ctx) => PdfTheme.footer(ctx, regular: regular),
        build: (ctx) {
          return [
            _metaTable([
              ['Orden de Trabajo', otLabel, 'Fecha de Emisión', emitDate],
              [
                'Cliente',
                detalle.cliente,
                'Hora Programada',
                detalle.horaStr.isEmpty ? '—' : detalle.horaStr
              ],
              [
                'Tipo de Servicio',
                detalle.tipoServicio,
                'Estado del Servicio',
                detalle.estado.replaceAll('_', ' ')
              ],
              [
                'Ubicación',
                detalle.ubicacion,
                'Fecha del Servicio',
                detalle.fechaStr.isEmpty ? '—' : detalle.fechaStr
              ],
            ], bold: bold, regular: regular),
            pw.SizedBox(height: 6),
            pw.Text('Técnico Responsable del Informe',
                style: pw.TextStyle(
                    fontSize: 7.5, color: PdfTheme.muted, font: regular)),
            pw.SizedBox(height: 2),
            pw.Text(tecnicoNombre,
                style:
                    pw.TextStyle(fontSize: 9, color: PdfTheme.ink, font: bold)),
            pw.SizedBox(height: 10),
            pw.Divider(color: PdfTheme.rule, thickness: 0.5, height: 0.5),
            pw.SizedBox(height: 10),
            pw.Text(
              'Progreso de Ejecución: ${detalle.progreso.round()}%'
              '${detalle.progreso >= 100 ? '  —  COMPLETADO' : ''}',
              style: pw.TextStyle(
                fontSize: 9,
                font: bold,
                color: detalle.progreso >= 100 ? PdfTheme.accent : PdfTheme.ink,
              ),
            ),
            PdfTheme.section('1. Descripción del Problema Técnico', bold: bold),
            pw.Text(
              detalle.descripcion.isEmpty
                  ? 'Sin descripción.'
                  : detalle.descripcion,
              style: pw.TextStyle(
                  fontSize: 9, color: PdfTheme.ink, font: regular),
            ),
            pw.SizedBox(height: 6),
            PdfTheme.section('2. Procedimientos y Estado de Ejecución',
                bold: bold),
            _procTable(detalle.procedimientos, bold: bold, regular: regular),
            pw.SizedBox(height: 10),
            if (detalle.materialesAsignados.isNotEmpty ||
                matsExtra.isNotEmpty) ...[
              PdfTheme.section('3. Liquidación de Materiales Utilizados',
                  bold: bold),
              if (detalle.materialesAsignados.isNotEmpty) ...[
                pw.Text('Materiales Asignados Originalmente',
                    style: pw.TextStyle(
                        fontSize: 9, color: PdfTheme.ink, font: bold)),
                pw.SizedBox(height: 4),
                _matTable(detalle.materialesAsignados,
                    bold: bold, regular: regular),
                pw.SizedBox(height: 8),
              ],
              if (matsExtra.isNotEmpty) ...[
                pw.Text(
                    'Materiales Extra Aprobados  (Solicitudes / Compra Externa)',
                    style: pw.TextStyle(
                        fontSize: 9, color: PdfTheme.ink, font: bold)),
                pw.SizedBox(height: 4),
                _matTable(matsExtra, bold: bold, regular: regular),
                pw.SizedBox(height: 8),
              ],
            ],
            if (procConEv.isNotEmpty) ...[
              PdfTheme.section('4. Registro Fotográfico de Evidencias',
                  bold: bold),
              ..._evidenciasBlocks(procConEv, imageBytes,
                  bold: bold, regular: regular),
            ],
          ];
        },
      ),
    );

    return doc.save();
  }

  // ─── Componentes específicos del informe ───────────────────────────────────

  static pw.Widget _metaTable(List<List<String>> rows,
      {required pw.Font bold, required pw.Font regular}) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1),
        3: pw.FlexColumnWidth(1.4),
      },
      children: rows.map((r) {
        return pw.TableRow(children: [
          _metaCell(r[0], r[1], bold: bold, regular: regular),
          pw.SizedBox(),
          _metaCell(r[2], r[3], bold: bold, regular: regular),
          pw.SizedBox(),
        ]);
      }).toList(),
    );
  }

  static pw.Widget _metaCell(String label, String value,
      {required pw.Font bold, required pw.Font regular}) {
    final v = value.length > 38 ? '${value.substring(0, 36)}…' : value;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 7.5, color: PdfTheme.muted, font: regular)),
          pw.SizedBox(height: 2),
          pw.Text(v,
              style:
                  pw.TextStyle(fontSize: 9, color: PdfTheme.ink, font: bold)),
        ],
      ),
    );
  }

  static pw.Widget _procTable(List<ProcedimientoDetalle> procs,
      {required pw.Font bold, required pw.Font regular}) {
    if (procs.isEmpty) {
      return pw.Text('Sin procedimientos registrados.',
          style: pw.TextStyle(
              fontSize: 9, color: PdfTheme.muted, font: regular));
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(28),
        1: pw.FlexColumnWidth(4),
        2: pw.FixedColumnWidth(78),
        3: pw.FixedColumnWidth(36),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg),
          children: [
            PdfTheme.th('N°', bold),
            PdfTheme.th('Procedimiento', bold),
            PdfTheme.th('Estado', bold),
            PdfTheme.th('Evid.', bold),
          ],
        ),
        for (final p in procs)
          pw.TableRow(children: [
            PdfTheme.td('${p.orden}', regular),
            PdfTheme.td(p.nombre, p.estado == 'completado' ? bold : regular,
                color: p.estado == 'completado' ? PdfTheme.ink : PdfTheme.muted),
            PdfTheme.td(
              _procEstadoLabel(p.estado),
              bold,
              color: p.estado == 'completado' ? PdfTheme.accent : PdfTheme.muted,
              size: 7.5,
            ),
            PdfTheme.td(p.evidencias.isNotEmpty ? '${p.evidencias.length}' : '—',
                bold,
                color:
                    p.evidencias.isNotEmpty ? PdfTheme.accent : PdfTheme.muted),
          ]),
      ],
    );
  }

  static String _procEstadoLabel(String e) => switch (e) {
        'completado' => '[ Completado ]',
        'en_proceso' => '[ En Proceso ]',
        'bloqueado' => '[ Bloqueado ]',
        _ => '[ Pendiente ]',
      };

  static pw.Widget _matTable(List<ItemMaterial> items,
      {required pw.Font bold, required pw.Font regular}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      columnWidths: const {
        0: pw.FixedColumnWidth(50),
        1: pw.FlexColumnWidth(3),
        2: pw.FixedColumnWidth(36),
        3: pw.FixedColumnWidth(58),
        4: pw.FixedColumnWidth(58),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfTheme.hdrBg),
          children: [
            PdfTheme.th('Ref.', bold),
            PdfTheme.th('Descripción', bold),
            PdfTheme.th('Cant.', bold),
            PdfTheme.th('Unidad', bold),
            PdfTheme.th('Estado', bold),
          ],
        ),
        for (final m in items)
          pw.TableRow(children: [
            PdfTheme.td(
              m.requerimientoId.isNotEmpty
                  ? m.requerimientoId
                      .substring(0, m.requerimientoId.length.clamp(0, 8))
                      .toUpperCase()
                  : '—',
              regular,
              size: 7.5,
            ),
            PdfTheme.td(m.nombre, regular, color: PdfTheme.ink),
            PdfTheme.td('${m.cantidad}', bold),
            PdfTheme.td(m.unidad, regular, color: PdfTheme.muted, size: 7.5),
            PdfTheme.td(
              m.estadoReq.isEmpty
                  ? '—'
                  : '${m.estadoReq[0].toUpperCase()}${m.estadoReq.substring(1)}',
              bold,
              color: m.estadoReq == 'entregado' ? PdfTheme.accent : PdfTheme.muted,
              size: 7.5,
            ),
          ]),
      ],
    );
  }

  static List<pw.Widget> _evidenciasBlocks(
    List<ProcedimientoDetalle> procs,
    Map<String, Uint8List> imageBytes, {
    required pw.Font bold,
    required pw.Font regular,
  }) {
    const etLabel = {'antes': 'Antes', 'durante': 'Durante', 'despues': 'Después'};
    const orderEtapa = ['antes', 'durante', 'despues'];

    final widgets = <pw.Widget>[];

    for (final proc in procs) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
          child: pw.Text(
            'Procedimiento ${proc.orden}:  ${proc.nombre}',
            style: pw.TextStyle(fontSize: 9, color: PdfTheme.ink, font: bold),
          ),
        ),
      );
      widgets.add(pw.Container(height: 0.5, color: PdfTheme.rule));
      widgets.add(pw.SizedBox(height: 8));

      final ordered = <EvidenciaDetalle>[];
      for (final e in orderEtapa) {
        ordered.addAll(proc.evidencias.where((ev) => ev.etapaLower == e));
      }
      ordered.addAll(
          proc.evidencias.where((ev) => !orderEtapa.contains(ev.etapaLower)));

      for (var i = 0; i < ordered.length; i += 3) {
        final fila = ordered.skip(i).take(3).toList();
        widgets.add(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: List.generate(3, (j) {
              if (j >= fila.length) {
                return pw.Expanded(child: pw.SizedBox());
              }
              final ev = fila[j];
              final bytes = imageBytes[ev.urlCloudinary];
              final etLabelText =
                  etLabel[ev.etapaLower] ?? ev.etapa.toUpperCase();
              return pw.Expanded(
                child: pw.Padding(
                  padding:
                      pw.EdgeInsets.only(right: j < 2 ? 8 : 0, bottom: 12),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(
                        height: 110,
                        decoration: pw.BoxDecoration(
                          color: PdfTheme.hdrBg,
                          border: pw.Border.all(color: PdfTheme.rule, width: 0.5),
                        ),
                        child: bytes != null
                            ? pw.Image(pw.MemoryImage(bytes),
                                fit: pw.BoxFit.contain)
                            : pw.Center(
                                child: pw.Text(
                                  'Imagen no disponible',
                                  style: pw.TextStyle(
                                      fontSize: 7,
                                      color: PdfTheme.muted,
                                      font: regular),
                                ),
                              ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(etLabelText,
                              style: pw.TextStyle(
                                  fontSize: 7.5, color: PdfTheme.ink, font: bold)),
                          if (ev.fechaCaptura.isNotEmpty)
                            pw.Text(ev.fechaCaptura,
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    color: PdfTheme.muted,
                                    font: regular)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        );
      }
    }

    return widgets;
  }
}
