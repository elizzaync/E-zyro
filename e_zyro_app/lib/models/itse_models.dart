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

class InspeccionTablero {
  final String id;
  final String nombre;
  final String? ambiente;
  final String? descripcion;
  const InspeccionTablero({required this.id, required this.nombre, this.ambiente, this.descripcion});

  factory InspeccionTablero.fromJson(Map<String, dynamic> j) => InspeccionTablero(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        ambiente: j['ambiente']?.toString(),
        descripcion: j['descripcion']?.toString(),
      );
}

class InspeccionItem {
  final String id;
  final String? tableroId;
  final String descripcion;
  final String resultado; // conforme | observado | no_conforme
  final String? observacion;
  const InspeccionItem({
    required this.id,
    this.tableroId,
    required this.descripcion,
    required this.resultado,
    this.observacion,
  });

  factory InspeccionItem.fromJson(Map<String, dynamic> j) => InspeccionItem(
        id: j['id']?.toString() ?? '',
        tableroId: j['tablero_id']?.toString(),
        descripcion: j['descripcion']?.toString() ?? '',
        resultado: j['resultado']?.toString() ?? 'conforme',
        observacion: j['observacion']?.toString(),
      );
}
