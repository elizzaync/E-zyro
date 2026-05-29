import 'dart:typed_data';
import 'dart:ui';

import '../pdf_overlay.dart';

/// Builder del PDF de **Solicitud de Permiso** (trámites).
///
/// Modelo de formato fijo: superpone los datos sobre la plantilla oficial
/// `assets/plantillas/plantilla_permiso.pdf` (migrado desde el antiguo
/// `templates/permiso_pdf_template.dart`, mismas coordenadas → salida idéntica).
class PermisoBuilder {
  PermisoBuilder._();

  static const String _plantilla = 'assets/plantillas/plantilla_permiso.pdf';

  static Future<Uint8List> build(
    Map<String, dynamic> data,
    Uint8List? firmaBytes,
  ) async {
    final pdf = PdfOverlay(_plantilla);
    await pdf.cargar();

    // ── COORDENADAS CALIBRABLES ──────────────────────────────────────────────
    // Origen (0,0) arriba-izquierda. A4 = 595 x 842. Conversión desde la web
    // (origen abajo-izq): Y_sync = 842 - Y_web - TamañoFuente.
    final coords = <String, Offset>{
      'fecha':         const Offset(105, 842 - 746 - 10),
      'area':          const Offset(255, 842 - 746 - 10),
      'puesto':        const Offset(445, 842 - 746 - 10),
      'nombre':        const Offset(185, 842 - 716 - 11),
      'horaInicio':    const Offset(300, 842 - 603 - 10),
      'horaFin':       const Offset(460, 842 - 603 - 10),
      'totalDias':     const Offset(330, 842 - 579 - 10),
      'periodoInicio': const Offset(290, 842 - 554 - 10),
      'periodoFin':    const Offset(420, 842 - 554 - 10),
      'motivo':        const Offset(60, 842 - 515 - 9),
    };

    final tipoCoords = <int, Offset>{
      1:  const Offset(191, 842 - 690 - 12),
      2:  const Offset(363, 842 - 690 - 12),
      3:  const Offset(533, 842 - 690 - 12),
      4:  const Offset(191, 842 - 672 - 12),
      5:  const Offset(363, 842 - 672 - 12),
      6:  const Offset(533, 842 - 672 - 12),
      7:  const Offset(191, 842 - 654 - 12),
      8:  const Offset(363, 842 - 654 - 12),
      9:  const Offset(533, 842 - 654 - 12),
      10: const Offset(191, 842 - 636 - 12),
    };

    // ── Fila: Fecha | Área | Puesto ──
    pdf.texto(data['f_inicio'] ?? '', coords['fecha']!);
    pdf.texto((data['area'] ?? 'TIC').toUpperCase(), coords['area']!);
    pdf.texto((data['puesto'] ?? 'Programador').toUpperCase(), coords['puesto']!);

    // ── Nombre del colaborador ──
    pdf.texto((data['nombre'] ?? '').toUpperCase(), coords['nombre']!,
        font: PdfOverlay.fuenteBold);

    // ── Checkbox: tipo de permiso ──
    final int tipo = data['tipo'] ?? 1;
    if (tipoCoords.containsKey(tipo)) {
      pdf.check(tipoCoords[tipo]!);
    }

    // ── Horario ──
    pdf.texto(data['hora_inicio'] ?? '', coords['horaInicio']!);
    pdf.texto(data['hora_fin'] ?? '', coords['horaFin']!);

    // ── Período: Total Días / Fecha Inicio / Fecha Fin ──
    if (data['total_dias'] != null) {
      pdf.texto(data['total_dias'].toString(), coords['totalDias']!);
    }
    pdf.texto(data['f_inicio'] ?? '', coords['periodoInicio']!);
    pdf.texto(data['f_fin'] ?? '', coords['periodoFin']!);

    // ── Sustento / Motivo (recortado) ──
    String motivo = data['sustento'] ?? '';
    if (motivo.length > 120) motivo = motivo.substring(0, 120);
    pdf.texto(motivo, coords['motivo']!, font: PdfOverlay.fuenteSmall);

    // ── Firma (coordenadas web x:80 y:339 w:110 h:50 → Y = 842-339-50 = 453) ──
    pdf.imagen(firmaBytes, const Rect.fromLTWH(80, 453, 110, 50));

    return pdf.guardar();
  }
}
