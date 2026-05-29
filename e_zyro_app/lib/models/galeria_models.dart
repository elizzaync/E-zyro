/// DTO de un recurso de la Galería Global (espejo de `RecursoOut` del backend).
class RecursoCloudinary {
  final String id;
  final String secureUrl;
  final String publicId;
  final String recursoTipo; // imagen | pdf | raw | video
  final String entidadTipo;
  final String? entidadId;
  final String? descripcion;
  final String? formato;
  final int? bytes;
  final String? createdAt;

  const RecursoCloudinary({
    required this.id,
    required this.secureUrl,
    required this.publicId,
    required this.recursoTipo,
    required this.entidadTipo,
    this.entidadId,
    this.descripcion,
    this.formato,
    this.bytes,
    this.createdAt,
  });

  bool get esImagen => recursoTipo == 'imagen';

  factory RecursoCloudinary.fromJson(Map<String, dynamic> j) => RecursoCloudinary(
        id: j['id']?.toString() ?? '',
        secureUrl: j['secure_url']?.toString() ?? '',
        publicId: j['public_id']?.toString() ?? '',
        recursoTipo: j['recurso_tipo']?.toString() ?? 'imagen',
        entidadTipo: j['entidad_tipo']?.toString() ?? '',
        entidadId: j['entidad_id']?.toString(),
        descripcion: j['descripcion']?.toString(),
        formato: j['formato']?.toString(),
        bytes: j['bytes'] is int ? j['bytes'] as int : int.tryParse('${j['bytes']}'),
        createdAt: j['created_at']?.toString(),
      );
}
