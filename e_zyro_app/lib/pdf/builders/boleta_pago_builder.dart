import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/finanzas_models.dart';
import '../pdf_theme.dart';

/// **Boleta de Pago** — desglose legal completo de un empleado para un
/// período de planilla, en paridad de contenido con el voucher que genera
/// la web (`construirVoucherHtml()`): header con datos fiscales, datos del
/// trabajador, ingresos/descuentos lado a lado con totales, resumen de
/// liquidación, provisiones del empleador y pie de página. A4 apaisado.
class BoletaPagoBuilder {
  BoletaPagoBuilder._();

  static Future<Uint8List> build({
    required PlanillaPreviewEmpleado e,
    required EmpresaInfo empresa,
    required String labelPeriodo,
    required String regimenEmpresa,
  }) async {
    final doc = pw.Document();
    final (regular, bold) = await PdfTheme.fonts();
    final fmt = NumberFormat.currency(locale: 'es_PE', symbol: 'S/ ');
    final fechaEmisionFmt = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final fechaIngresoFmt = e.fechaIngreso != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.tryParse(e.fechaIngreso!) ?? DateTime.now())
        : '—';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: PdfTheme.pageMargin,
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        header: (ctx) => ctx.pageNumber == 1
            ? _header(bold: bold, regular: regular, empresa: empresa, labelPeriodo: labelPeriodo,
                regimenEmpresa: regimenEmpresa, fechaEmisionFmt: fechaEmisionFmt)
            : pw.SizedBox(),
        footer: (ctx) => _footer(regular: regular, empresa: empresa, fechaEmisionFmt: fechaEmisionFmt),
        build: (ctx) => [
          _datosTrabajador(e, bold: bold, regular: regular, fechaIngresoFmt: fechaIngresoFmt),
          pw.SizedBox(height: 4),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Expanded(child: _bloqueIngresos(e, fmt, bold: bold, regular: regular)),
            pw.SizedBox(width: 14),
            pw.Expanded(child: _bloqueDescuentos(e, fmt, bold: bold, regular: regular)),
          ]),
          _resumenLiquidacion(e, fmt, bold: bold, regular: regular),
          PdfTheme.section('Provisiones y Aportes del Empleador', bold: bold),
          _bloqueProvisiones(e, fmt, regimenEmpresa, bold: bold, regular: regular),
        ],
      ),
    );
    return doc.save();
  }

  // ── Header / Footer ─────────────────────────────────────────────────────

  static pw.Widget _header({
    required pw.Font bold, required pw.Font regular, required EmpresaInfo empresa,
    required String labelPeriodo, required String regimenEmpresa, required String fechaEmisionFmt,
  }) {
    return pw.Column(children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(empresa.razonSocial.toUpperCase(),
                  style: pw.TextStyle(fontSize: 13, font: bold, color: PdfTheme.ink)),
              pw.SizedBox(height: 2),
              pw.Text('RUC: ${empresa.ruc} | Régimen ${_regimenLabel(regimenEmpresa)}',
                  style: pw.TextStyle(fontSize: 8, font: regular, color: PdfTheme.muted)),
              if (empresa.direccion.isNotEmpty)
                pw.Text('Domicilio Fiscal: ${empresa.direccion}',
                    style: pw.TextStyle(fontSize: 8, font: regular, color: PdfTheme.muted)),
              if (empresa.telefono.isNotEmpty)
                pw.Text('Teléfono: ${empresa.telefono}',
                    style: pw.TextStyle(fontSize: 8, font: regular, color: PdfTheme.muted)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('BOLETA DE PAGO',
                style: pw.TextStyle(fontSize: 13, font: bold, color: PdfTheme.ink)),
            pw.SizedBox(height: 2),
            pw.Text('Período Laboral: $labelPeriodo | Fecha de Emisión: $fechaEmisionFmt',
                style: pw.TextStyle(fontSize: 8, font: regular, color: PdfTheme.muted)),
          ]),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(height: 1.5, color: PdfTheme.accent),
      pw.SizedBox(height: 10),
    ]);
  }

  static pw.Widget _footer({
    required pw.Font regular, required EmpresaInfo empresa, required String fechaEmisionFmt,
  }) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(height: 0.5, color: PdfTheme.rule),
      pw.SizedBox(height: 4),
      pw.Text('Documento emitido por ${empresa.razonSocial.toUpperCase()}',
          style: pw.TextStyle(fontSize: 7, color: PdfTheme.muted, font: regular)),
      pw.Text(
          'Generado a través del Sistema de Gestión Empresarial E-ZYRO · Emitido el $fechaEmisionFmt.',
          style: pw.TextStyle(fontSize: 7, color: PdfTheme.muted, font: regular)),
    ]);
  }

  // ── Datos del trabajador ────────────────────────────────────────────────

  static pw.Widget _datosTrabajador(
    PlanillaPreviewEmpleado e, {
    required pw.Font bold, required pw.Font regular, required String fechaIngresoFmt,
  }) {
    pw.Widget celda(String texto) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(texto, style: pw.TextStyle(fontSize: 8, font: regular, color: PdfTheme.ink)),
        );
    return pw.Table(
      border: pw.TableBorder.all(color: PdfTheme.rule, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2.5),
        2: pw.FlexColumnWidth(2.5), 3: pw.FlexColumnWidth(2.5),
      },
      children: [
        pw.TableRow(children: [
          celda('Apellidos y Nombres: ${e.nombreCompleto ?? "—"}'),
          celda('${(e.tipoDocumento ?? "DNI").toUpperCase()}: ${e.numeroDocumento ?? "—"}'),
          celda('Fecha de Ingreso: $fechaIngresoFmt'),
          celda('Régimen Laboral: ${_modalidadLabel(e.tipoContrato)}'),
        ]),
        pw.TableRow(children: [
          celda('Cargo u Ocupación: ${e.cargo ?? "—"}'),
          celda('Área / Centro de Costo: ${e.area ?? "—"}'),
          celda('CUSPP: ${e.cuspp ?? "—"}'),
          celda('Días / Horas Laboradas: ${e.diasLaborados}d · ${e.horasReales.toStringAsFixed(1)}h'),
        ]),
      ],
    );
  }

  // ── Ingresos ─────────────────────────────────────────────────────────────

  static pw.Widget _bloqueIngresos(
    PlanillaPreviewEmpleado e, NumberFormat fmt, {required pw.Font bold, required pw.Font regular}) {
    final filas = <(String, String, String)>[
      ('Remuneración Básica', 'Jornada ordinaria pactada', fmt.format(e.sueldoPeriodo)),
    ];
    if (e.pagoHorasExtra > 0) {
      final h = e.horasExtraPagables;
      final String detalle;
      if (!e.esDependiente) {
        detalle = 'Tarifa simple — ${h.toStringAsFixed(1)}h (sin recargo, Ley N.° 28518)';
      } else if (h <= 2) {
        detalle = 'Recargo 25% — ${h.toStringAsFixed(1)}h';
      } else {
        detalle = '2h al 25% + ${(h - 2).toStringAsFixed(1)}h al 35%';
      }
      filas.add(('Trabajo en Sobretiempo (${h.toStringAsFixed(1)}h)', detalle,
          '+${fmt.format(e.pagoHorasExtra)}'));
    }
    if (e.pagoDomingo > 0) {
      filas.add((
        'Trabajo en Día de Descanso (Domingo, ${e.horasDomingo.toStringAsFixed(1)}h)',
        e.esDependiente
            ? 'Sobretasa 100% — D.Leg. N.° 713 Art. 3'
            : 'Tarifa simple (Ley N.° 28518)',
        '+${fmt.format(e.pagoDomingo)}',
      ));
    }
    if (e.pagoFeriado > 0) {
      filas.add((
        'Trabajo en Día Feriado (${e.horasFeriado.toStringAsFixed(1)}h)',
        e.esDependiente
            ? 'Sobretasa 100% — D.Leg. N.° 713 Art. 8/9'
            : 'Tarifa simple (Ley N.° 28518)',
        '+${fmt.format(e.pagoFeriado)}',
      ));
    }
    if (e.asignacionFamiliar > 0) {
      filas.add(('Asignación Familiar', '10% de la R.M.V. — D.S. N.° 035-90-TR',
          '+${fmt.format(e.asignacionFamiliar)}'));
    }

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      PdfTheme.section('Ingresos', bold: bold),
      _tabla(bold: bold, regular: regular, filas: filas),
      if (e.horasExtraSinTramite > 0)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
              '⚠ Trámite de Permanencia Extra pendiente — '
              '${e.horasExtraSinTramite.toStringAsFixed(1)}h pagada(s) sin solicitud '
              'aprobada, regularizar en Trámites y Permisos',
              style: pw.TextStyle(fontSize: 7, font: regular, color: PdfTheme.muted)),
        ),
      _filaTotal('TOTAL REMUNERACIÓN BRUTA', fmt.format(e.totalIngresos), bold: bold),
    ]);
  }

  // ── Descuentos ───────────────────────────────────────────────────────────

  static pw.Widget _bloqueDescuentos(
    PlanillaPreviewEmpleado e, NumberFormat fmt, {required pw.Font bold, required pw.Font regular}) {
    final filas = <(String, String, String)>[];

    filas.add(e.descuentoFaltas > 0
        ? ('Inasistencias', '${e.diasFaltantes}d + ${e.minutosTardanza}min tardanza',
            '−${fmt.format(e.descuentoFaltas)}')
        : ('Inasistencias', 'Sin faltas ni tardanzas', '—'));

    if (e.descuentoPension > 0 && e.esAfp) {
      final afp = _afpLabel(e.entidadAfp);
      filas.add(('Aporte Obligatorio al Fondo de Pensiones',
          'Cuenta Individual de Capitalización · $afp', '−${fmt.format(e.afpAporteObligatorio)}'));
      filas.add(('Prima de Seguro de Invalidez y Sobrevivencia',
          'Cobertura previsional SPP', '−${fmt.format(e.afpPrimaSeguro)}'));
      filas.add(('Comisión de Administración (AFP)',
          '$afp — comisión ${(e.comisionAfpPct * 100).toStringAsFixed(2)}%',
          '−${fmt.format(e.afpComision)}'));
    } else if (e.descuentoPension > 0) {
      filas.add(('Aporte al Sistema Nacional de Pensiones (ONP)', 'D.L. N.° 19990',
          '−${fmt.format(e.descuentoPension)}'));
    } else {
      filas.add(('Pensión', e.motivoPension, '—'));
    }

    filas.add(e.renta5ta > 0
        ? ('Retención de Impuesto a la Renta de 5ta Categoría',
            'Retención mensualizada (SUNAT)', '−${fmt.format(e.renta5ta)}')
        : ('Retención de Impuesto a la Renta de 5ta Categoría',
            'Proyección anual no supera el mínimo no imponible (7 UIT)', '—'));

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      PdfTheme.section('Descuentos y Retenciones', bold: bold),
      _tabla(bold: bold, regular: regular, filas: filas),
      _filaTotal('TOTAL DESCUENTOS', '−${fmt.format(e.totalDescuentosLegales)}', bold: bold),
    ]);
  }

  // ── Resumen de liquidación ──────────────────────────────────────────────

  static pw.Widget _resumenLiquidacion(
    PlanillaPreviewEmpleado e, NumberFormat fmt, {required pw.Font bold, required pw.Font regular}) {
    pw.Widget fila(String label, String monto, {bool destacado = false}) => pw.Container(
          padding: pw.EdgeInsets.symmetric(horizontal: 12, vertical: destacado ? 8 : 5),
          decoration: destacado
              ? pw.BoxDecoration(color: const PdfColor.fromInt(0xFFE7F4E9),
                  borderRadius: pw.BorderRadius.circular(6))
              : null,
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(label,
                style: pw.TextStyle(fontSize: destacado ? 10 : 8.5, font: bold, color: PdfTheme.ink)),
            pw.Text(monto,
                style: pw.TextStyle(fontSize: destacado ? 14 : 9, font: bold,
                    color: destacado ? const PdfColor.fromInt(0xFF3E9A4E) : PdfTheme.ink)),
          ]),
        );
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Column(children: [
        fila('Total Remuneración Bruta', fmt.format(e.totalIngresos)),
        pw.SizedBox(height: 3),
        fila('(−) Total Descuentos y Retenciones', '−${fmt.format(e.totalDescuentosLegales)}'),
        pw.SizedBox(height: 6),
        fila('Total Neto a Recibir', fmt.format(e.netoAPagar), destacado: true),
      ]),
    );
  }

  // ── Provisiones del empleador ───────────────────────────────────────────

  static pw.Widget _bloqueProvisiones(
    PlanillaPreviewEmpleado e, NumberFormat fmt, String regimenEmpresa,
    {required pw.Font bold, required pw.Font regular}) {
    return _tabla(bold: bold, regular: regular, filas: [
      ('Aporte a EsSalud (Carga del Empleador)',
          'Ley N.° 26790 — no se descuenta al trabajador', fmt.format(e.aporteEssalud)),
      ('Compensación por Tiempo de Servicios (CTS)', e.motivoCts(regimenEmpresa),
          e.provisionCts > 0 ? fmt.format(e.provisionCts) : '—'),
      ('Gratificación Legal (Ley N.° 27735)', e.motivoGratificacion(regimenEmpresa),
          e.provisionGratificacion > 0 ? fmt.format(e.provisionGratificacion) : '—'),
      ('Provisión de Vacaciones', e.motivoVacaciones,
          e.provisionVacaciones > 0 ? fmt.format(e.provisionVacaciones) : '—'),
    ]);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _regimenLabel(String r) => switch (r) {
        'micro' => 'Microempresa',
        'pequena' => 'Pequeña Empresa',
        _ => 'Régimen General',
      };

  static String _modalidadLabel(String t) => switch (t) {
        'contrato' => 'Contrato',
        'practicante' => 'Practicante',
        _ => 'Planilla',
      };

  static String _afpLabel(String? key) => switch (key) {
        'prima' => 'AFP Prima',
        'profuturo' => 'Profuturo AFP',
        'habitat' => 'AFP Habitat',
        _ => 'AFP Integra',
      };

  static pw.Widget _filaTotal(String label, String monto, {required pw.Font bold}) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfTheme.rule, width: 0.8)),
        ),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8.5, font: bold, color: PdfTheme.ink)),
          pw.Text(monto, style: pw.TextStyle(fontSize: 9, font: bold, color: PdfTheme.ink)),
        ]),
      );

  static pw.Widget _tabla({
    required pw.Font bold, required pw.Font regular,
    required List<(String, String, String)> filas,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(2),
      },
      children: [
        for (final (label, detalle, monto) in filas)
          pw.TableRow(children: [
            PdfTheme.td(label, bold, size: 8),
            PdfTheme.td(detalle, regular, size: 7, color: PdfTheme.muted),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              child: pw.Text(monto,
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(fontSize: 8, font: bold,
                      color: monto.startsWith('−')
                          ? const PdfColor.fromInt(0xFFCC5A2E) : PdfTheme.ink)),
            ),
          ]),
      ],
    );
  }
}
