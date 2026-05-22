import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proyecto_models.dart';

/// Pantalla de previsualización del Pre-Informe de Conformidad de Servicio.
///
/// Genera el PDF on-demand (replica del web `operaciones-detalle.component.ts`
/// método `abrirModalPreInforme()`):
///  1. Cabecera "INFORME TÉCNICO DE CONFORMIDAD DE SERVICIO".
///  2. Bloque de metadatos (OT, cliente, ubicación, fechas, técnico).
///  3. Progreso de ejecución %.
///  4. Sección 1 — Descripción del problema técnico.
///  5. Sección 2 — Tabla de procedimientos con estado y # de evidencias.
///  6. Sección 3 — Liquidación de materiales (asignados + extra aprobados).
///  7. Sección 4 — Registro fotográfico (descarga imágenes Cloudinary).
class InformeServicioPreviewScreen extends StatefulWidget {
  final ServicioDetalle detalle;
  const InformeServicioPreviewScreen({super.key, required this.detalle});

  @override
  State<InformeServicioPreviewScreen> createState() =>
      _InformeServicioPreviewScreenState();
}

class _InformeServicioPreviewScreenState
    extends State<InformeServicioPreviewScreen> {
  String _tecnicoNombre = 'Técnico';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _tecnicoNombre = prefs.getString('user_name') ??
          prefs.getString('user_nombre') ??
          'Técnico';
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pre-Informe de Conformidad',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Color(0xFF8FD11B)),
              ),
            )
          : PdfPreview(
              build: (format) => _buildPdf(
                detalle: widget.detalle,
                tecnicoNombre: _tecnicoNombre,
              ),
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: true,
              allowSharing: true,
              pdfFileName:
                  'pre-informe-${widget.detalle.cliente.replaceAll(' ', '-')}-${DateTime.now().millisecondsSinceEpoch}.pdf',
              loadingWidget: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Color(0xFF8FD11B)),
                ),
              ),
            ),
    );
  }
}

// ─── Generación del PDF ──────────────────────────────────────────────────────

const _ink = PdfColor.fromInt(0xFF171F2E);
const _muted = PdfColor.fromInt(0xFF667690);
const _rule = PdfColor.fromInt(0xFFE2E6ED);
const _hdrBg = PdfColor.fromInt(0xFFF5F7F8);
const _accent = PdfColor.fromInt(0xFF8FD11B);

Future<Uint8List> _buildPdf({
  required ServicioDetalle detalle,
  required String tecnicoNombre,
}) async {
  final doc = pw.Document();
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();

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

  final emitDate =
      DateFormat('d MMMM y', 'es_ES').format(DateTime.now());
  final otLabel = detalle.id.length >= 8
      ? 'OT-${detalle.id.substring(0, 8).toUpperCase()}'
      : 'OT-${detalle.id.toUpperCase()}';

  // Filtrar materiales solicitados que ya fueron aprobados/entregados (extra).
  final matsExtra = detalle.materialesSolicitados
      .where((m) =>
          m.estadoReq == 'aprobado' || m.estadoReq == 'entregado')
      .toList();

  final procConEv =
      detalle.procedimientos.where((p) => p.evidencias.isNotEmpty).toList();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(44, 36, 44, 60),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (ctx) => _buildHeader(ctx, bold: bold, regular: regular),
      footer: (ctx) => _buildFooter(ctx, regular: regular),
      build: (ctx) {
        return [
          // Metadatos en 2 columnas
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
                  fontSize: 7.5, color: _muted, font: regular)),
          pw.SizedBox(height: 2),
          pw.Text(tecnicoNombre,
              style: pw.TextStyle(
                  fontSize: 9, color: _ink, font: bold)),
          pw.SizedBox(height: 10),
          pw.Divider(color: _rule, thickness: 0.5, height: 0.5),
          pw.SizedBox(height: 10),
          pw.Text(
            'Progreso de Ejecución: ${detalle.progreso.round()}%'
            '${detalle.progreso >= 100 ? '  —  COMPLETADO' : ''}',
            style: pw.TextStyle(
              fontSize: 9,
              font: bold,
              color: detalle.progreso >= 100 ? _accent : _ink,
            ),
          ),

          // Sección 1: descripción
          _section('1. Descripción del Problema Técnico',
              bold: bold, regular: regular),
          pw.Text(
            detalle.descripcion.isEmpty ? 'Sin descripción.' : detalle.descripcion,
            style: pw.TextStyle(fontSize: 9, color: _ink, font: regular),
          ),
          pw.SizedBox(height: 6),

          // Sección 2: procedimientos
          _section('2. Procedimientos y Estado de Ejecución',
              bold: bold, regular: regular),
          _procTable(detalle.procedimientos, bold: bold, regular: regular),
          pw.SizedBox(height: 10),

          // Sección 3: materiales
          if (detalle.materialesAsignados.isNotEmpty ||
              matsExtra.isNotEmpty) ...[
            _section('3. Liquidación de Materiales Utilizados',
                bold: bold, regular: regular),
            if (detalle.materialesAsignados.isNotEmpty) ...[
              pw.Text('Materiales Asignados Originalmente',
                  style: pw.TextStyle(
                      fontSize: 9, color: _ink, font: bold)),
              pw.SizedBox(height: 4),
              _matTable(detalle.materialesAsignados,
                  bold: bold, regular: regular),
              pw.SizedBox(height: 8),
            ],
            if (matsExtra.isNotEmpty) ...[
              pw.Text(
                  'Materiales Extra Aprobados  (Solicitudes / Compra Externa)',
                  style: pw.TextStyle(
                      fontSize: 9, color: _ink, font: bold)),
              pw.SizedBox(height: 4),
              _matTable(matsExtra, bold: bold, regular: regular),
              pw.SizedBox(height: 8),
            ],
          ],

          // Sección 4: evidencias fotográficas
          if (procConEv.isNotEmpty) ...[
            _section('4. Registro Fotográfico de Evidencias',
                bold: bold, regular: regular),
            ..._evidenciasBlocks(procConEv, imageBytes,
                bold: bold, regular: regular),
          ],
        ];
      },
    ),
  );

  return doc.save();
}

// ─── Componentes del PDF ─────────────────────────────────────────────────────

pw.Widget _buildHeader(pw.Context ctx,
    {required pw.Font bold, required pw.Font regular}) {
  final isFirst = ctx.pageNumber == 1;
  if (isFirst) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'INFORME TÉCNICO DE CONFORMIDAD DE SERVICIO',
          style: pw.TextStyle(fontSize: 14, font: bold, color: _ink),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'E-System TIC  ·  Gestión de Operaciones de Campo',
          style: pw.TextStyle(fontSize: 8.5, font: regular, color: _muted),
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 1.5, color: _accent),
        pw.SizedBox(height: 14),
      ],
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'INFORME TÉCNICO DE CONFORMIDAD DE SERVICIO — CONT.',
        style: pw.TextStyle(fontSize: 8.5, font: bold, color: _ink),
      ),
      pw.SizedBox(height: 3),
      pw.Container(height: 0.5, color: _rule),
      pw.SizedBox(height: 10),
    ],
  );
}

pw.Widget _buildFooter(pw.Context ctx, {required pw.Font regular}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(height: 0.5, color: _rule),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'E-System TIC Perú S.A.C. — Documento Técnico Confidencial · Sujeto a Control de Gestión',
            style: pw.TextStyle(fontSize: 7, color: _muted, font: regular),
          ),
          pw.Text(
            '${ctx.pageNumber} / ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 7, color: _muted, font: regular),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _metaTable(List<List<String>> rows,
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

pw.Widget _metaCell(String label, String value,
    {required pw.Font bold, required pw.Font regular}) {
  final v = value.length > 38 ? '${value.substring(0, 36)}…' : value;
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style: pw.TextStyle(fontSize: 7.5, color: _muted, font: regular)),
        pw.SizedBox(height: 2),
        pw.Text(v,
            style: pw.TextStyle(fontSize: 9, color: _ink, font: bold)),
      ],
    ),
  );
}

pw.Widget _section(String title,
    {required pw.Font bold, required pw.Font regular}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 12, bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(fontSize: 7.5, color: _muted, font: bold),
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 0.5, color: _rule),
        pw.SizedBox(height: 8),
      ],
    ),
  );
}

pw.Widget _procTable(List<ProcedimientoDetalle> procs,
    {required pw.Font bold, required pw.Font regular}) {
  if (procs.isEmpty) {
    return pw.Text('Sin procedimientos registrados.',
        style: pw.TextStyle(fontSize: 9, color: _muted, font: regular));
  }
  return pw.Table(
    border: pw.TableBorder.all(color: _rule, width: 0.5),
    columnWidths: const {
      0: pw.FixedColumnWidth(28),
      1: pw.FlexColumnWidth(4),
      2: pw.FixedColumnWidth(78),
      3: pw.FixedColumnWidth(36),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _hdrBg),
        children: [
          _th('N°', bold),
          _th('Procedimiento', bold),
          _th('Estado', bold),
          _th('Evid.', bold),
        ],
      ),
      for (final p in procs)
        pw.TableRow(children: [
          _td('${p.orden}', regular),
          _td(p.nombre, p.estado == 'completado' ? bold : regular,
              color: p.estado == 'completado' ? _ink : _muted),
          _td(
            _procEstadoLabel(p.estado),
            bold,
            color: p.estado == 'completado' ? _accent : _muted,
            size: 7.5,
          ),
          _td(p.evidencias.isNotEmpty ? '${p.evidencias.length}' : '—',
              bold,
              color: p.evidencias.isNotEmpty ? _accent : _muted),
        ]),
    ],
  );
}

String _procEstadoLabel(String e) => switch (e) {
      'completado' => '[ Completado ]',
      'en_proceso' => '[ En Proceso ]',
      'bloqueado' => '[ Bloqueado ]',
      _ => '[ Pendiente ]',
    };

pw.Widget _matTable(List<ItemMaterial> items,
    {required pw.Font bold, required pw.Font regular}) {
  return pw.Table(
    border: pw.TableBorder.all(color: _rule, width: 0.5),
    columnWidths: const {
      0: pw.FixedColumnWidth(50),
      1: pw.FlexColumnWidth(3),
      2: pw.FixedColumnWidth(36),
      3: pw.FixedColumnWidth(58),
      4: pw.FixedColumnWidth(58),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _hdrBg),
        children: [
          _th('Ref.', bold),
          _th('Descripción', bold),
          _th('Cant.', bold),
          _th('Unidad', bold),
          _th('Estado', bold),
        ],
      ),
      for (final m in items)
        pw.TableRow(children: [
          _td(
            m.requerimientoId.isNotEmpty
                ? m.requerimientoId
                    .substring(0, m.requerimientoId.length.clamp(0, 8))
                    .toUpperCase()
                : '—',
            regular,
            size: 7.5,
          ),
          _td(m.nombre, regular, color: _ink),
          _td('${m.cantidad}', bold),
          _td(m.unidad, regular, color: _muted, size: 7.5),
          _td(
            m.estadoReq.isEmpty
                ? '—'
                : '${m.estadoReq[0].toUpperCase()}${m.estadoReq.substring(1)}',
            bold,
            color: m.estadoReq == 'entregado' ? _accent : _muted,
            size: 7.5,
          ),
        ]),
    ],
  );
}

pw.Widget _th(String text, pw.Font font) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: 7.5, color: _muted, font: font)),
    );

pw.Widget _td(String text, pw.Font font,
        {PdfColor color = _ink, double size = 8}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(text,
          style: pw.TextStyle(fontSize: size, color: color, font: font)),
    );

List<pw.Widget> _evidenciasBlocks(
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
          style: pw.TextStyle(fontSize: 9, color: _ink, font: bold),
        ),
      ),
    );
    widgets.add(pw.Container(height: 0.5, color: _rule));
    widgets.add(pw.SizedBox(height: 8));

    // Ordenar evidencias por etapa
    final ordered = <EvidenciaDetalle>[];
    for (final e in orderEtapa) {
      ordered.addAll(proc.evidencias.where((ev) => ev.etapaLower == e));
    }
    // Si alguna no tiene etapa válida, añadirla al final
    ordered.addAll(
        proc.evidencias.where((ev) => !orderEtapa.contains(ev.etapaLower)));

    // Layout: 3 columnas
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
                padding: pw.EdgeInsets.only(right: j < 2 ? 8 : 0, bottom: 12),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(
                      height: 110,
                      decoration: pw.BoxDecoration(
                        color: _hdrBg,
                        border: pw.Border.all(color: _rule, width: 0.5),
                      ),
                      child: bytes != null
                          ? pw.Image(pw.MemoryImage(bytes),
                              fit: pw.BoxFit.contain)
                          : pw.Center(
                              child: pw.Text(
                                'Imagen no disponible',
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    color: _muted,
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
                                fontSize: 7.5, color: _ink, font: bold)),
                        if (ev.fechaCaptura.isNotEmpty)
                          pw.Text(ev.fechaCaptura,
                              style: pw.TextStyle(
                                  fontSize: 7,
                                  color: _muted,
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
