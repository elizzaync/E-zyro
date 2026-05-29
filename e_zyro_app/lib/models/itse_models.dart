/// DTOs de Inspección ITSE (Fase 5).
class InspeccionItse {
  final String id;
  final String? clienteId;
  final String? ubicacionId;
  final String? zonaId;
  final String modo; // tablero | zona
  final String? fecha;
  final String estado; // borrador | en_proceso | finalizada | anulada
  final String? pdfUrl;
  final String? observaciones;

  const InspeccionItse({
    required this.id,
    this.clienteId,
    this.ubicacionId,
    this.zonaId,
    required this.modo,
    this.fecha,
    required this.estado,
    this.pdfUrl,
    this.observaciones,
  });

  factory InspeccionItse.fromJson(Map<String, dynamic> j) => InspeccionItse(
        id: j['id']?.toString() ?? '',
        clienteId: j['cliente_id']?.toString(),
        ubicacionId: j['ubicacion_id']?.toString(),
        zonaId: j['zona_id']?.toString(),
        modo: j['modo']?.toString() ?? 'tablero',
        fecha: j['fecha']?.toString(),
        estado: j['estado']?.toString() ?? 'borrador',
        pdfUrl: j['pdf_url']?.toString(),
        observaciones: j['observaciones']?.toString(),
      );
}
