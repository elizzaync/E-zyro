import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart' show rootBundle;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class PermisoPdfTemplate {
  static Future<Uint8List> generate(
    Map<String, dynamic> data,
    Uint8List? firmaBytes,
  ) async {
    // 1. Cargar la plantilla PDF desde los assets
    final ByteData templateBytes = await rootBundle.load('assets/plantilla_permiso.pdf');
    final PdfDocument document = PdfDocument(inputBytes: templateBytes.buffer.asUint8List());

    // 2. Obtener la primera página
    final PdfPage page = document.pages[0];

    // Fuentes
    final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final PdfFont fontBold = PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold);
    final PdfFont fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final PdfFont fontCheck = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);

    // ── COORDENADAS CALIBRABLES ──────────────────────────────────────────────
    // En syncfusion_flutter_pdf, el origen (0,0) es Arriba-Izquierda.
    // pdf-lib usa Abajo-Izquierda (A4 = 595 x 842).
    // Fórmula de conversión aproximada: Y_sync = 842 - Y_pdflib - TamañoFuente
    
    // Coordenadas convertidas desde la web
    final Map<String, Offset> coords = {
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

    final Map<int, Offset> tipoCoords = {
      1:  const Offset(191, 842 - 690 - 12), // (1) Permiso personal
      2:  const Offset(363, 842 - 690 - 12), // (2) Comisión de Trabajo
      3:  const Offset(533, 842 - 690 - 12), // (3) Cita Essalud / Clínica
      4:  const Offset(191, 842 - 672 - 12), // (4) Permanencia Capacitación
      5:  const Offset(363, 842 - 672 - 12), // (5) Permanencia Extra
      6:  const Offset(533, 842 - 672 - 12), // (6) Recuperación
      7:  const Offset(191, 842 - 654 - 12), // (7) Vacaciones
      8:  const Offset(363, 842 - 654 - 12), // (8) Día(s) Libre(s)
      9:  const Offset(533, 842 - 654 - 12), // (9) Transferencia
      10: const Offset(191, 842 - 636 - 12), // (10) Otros
    };

    // Función auxiliar para estampar texto
    void texto(String text, Offset pos, PdfFont f) {
      if (text.isNotEmpty) {
        page.graphics.drawString(
          text,
          f,
          brush: PdfSolidBrush(PdfColor(0, 0, 0)),
          bounds: Rect.fromLTWH(pos.dx, pos.dy, 500, 50),
        );
      }
    }

    // ── Fila: Fecha | Área | Puesto ──────────────────────────────
    texto(data['f_inicio'] ?? '', coords['fecha']!, font);
    texto((data['area'] ?? 'TIC').toUpperCase(), coords['area']!, font);
    texto((data['puesto'] ?? 'Programador').toUpperCase(), coords['puesto']!, font);

    // ── Nombre del colaborador ────────────────────────────────────
    texto((data['nombre'] ?? '').toUpperCase(), coords['nombre']!, fontBold);

    // ── Checkbox: tipo de permiso ─────────────────────────────────
    final int tipo = data['tipo'] ?? 1;
    if (tipoCoords.containsKey(tipo)) {
      texto('X', tipoCoords[tipo]!, fontCheck);
    }

    // ── Horario ───────────────────────────────────────────────────
    texto(data['hora_inicio'] ?? '', coords['horaInicio']!, font);
    texto(data['hora_fin'] ?? '', coords['horaFin']!, font);

    // ── Período: Total Días / Fecha Inicio / Fecha Fin ────────────
    if (data['total_dias'] != null) {
      texto(data['total_dias'].toString(), coords['totalDias']!, font);
    }
    texto(data['f_inicio'] ?? '', coords['periodoInicio']!, font);
    texto(data['f_fin'] ?? '', coords['periodoFin']!, font);

    // ── Sustento / Motivo ─────────────────────────────────────────
    String motivo = data['sustento'] ?? '';
    if (motivo.length > 120) {
      motivo = motivo.substring(0, 120);
    }
    texto(motivo, coords['motivo']!, fontSmall);

    // ── Imagen de firma ───────────────────────────────────────────
    if (firmaBytes != null) {
      try {
        final PdfBitmap image = PdfBitmap(firmaBytes);
        // Coordenadas web: x: 80, y: 339, width: 110, height: 50
        // Conversión a syncfusion: Y = 842 - 339 - 50 = 453
        page.graphics.drawImage(
          image,
          const Rect.fromLTWH(80, 453, 110, 50),
        );
      } catch (e) {
        // Ignorar si la imagen no se puede cargar
      }
    }

    // 3. Guardar el documento modificado
    final List<int> bytes = document.saveSync();
    document.dispose();

    return Uint8List.fromList(bytes);
  }
}
