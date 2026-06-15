/// Documento del repositorio de cumplimiento / SST (homologación, ATS, PETAR…).
class DocumentoSst {
  final String id;
  final String tipo; // homologacion | ats | petar | otro
  final String titulo;
  final String? clienteId;
  final String? clienteNombre;
  final String? entidadEmisora;
  final String? codigo;
  final String? fechaEmision;
  final String? fechaVencimiento;
  final String estado; // vigente | por_vencer | vencida | sin_fecha
  final int? diasParaVencer;
  final String? archivoUrl;
  final String? nombreArchivo;
  final String? formato;
  final String? observaciones;
  final String? createdAt;

  const DocumentoSst({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.estado,
    this.clienteId,
    this.clienteNombre,
    this.entidadEmisora,
    this.codigo,
    this.fechaEmision,
    this.fechaVencimiento,
    this.diasParaVencer,
    this.archivoUrl,
    this.nombreArchivo,
    this.formato,
    this.observaciones,
    this.createdAt,
  });

  factory DocumentoSst.fromJson(Map<String, dynamic> j) => DocumentoSst(
        id: (j['id'] ?? '').toString(),
        tipo: (j['tipo'] ?? 'otro').toString(),
        titulo: (j['titulo'] ?? '').toString(),
        estado: (j['estado'] ?? 'sin_fecha').toString(),
        clienteId: j['cliente_id']?.toString(),
        clienteNombre: j['cliente_nombre']?.toString(),
        entidadEmisora: j['entidad_emisora']?.toString(),
        codigo: j['codigo']?.toString(),
        fechaEmision: j['fecha_emision']?.toString(),
        fechaVencimiento: j['fecha_vencimiento']?.toString(),
        diasParaVencer: j['dias_para_vencer'] is int
            ? j['dias_para_vencer'] as int
            : int.tryParse('${j['dias_para_vencer']}'),
        archivoUrl: j['archivo_url']?.toString(),
        nombreArchivo: j['nombre_archivo']?.toString(),
        formato: j['formato']?.toString(),
        observaciones: j['observaciones']?.toString(),
        createdAt: j['created_at']?.toString(),
      );

  bool get tieneArchivo => (archivoUrl ?? '').isNotEmpty;
}

/// Etiquetas legibles por tipo.
const Map<String, String> kTiposDocumentoSst = {
  'homologacion': 'Homologación',
  'ats': 'ATS',
  'petar': 'PETAR',
  'otro': 'Otro',
};
