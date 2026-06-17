// Modelos del Drive de empresa — endpoints `/drive`.

class DriveCarpeta {
  final String id;
  final String nombre;
  final String ambito;
  final String? padreId;
  final int subCarpetas;
  final int archivos;

  const DriveCarpeta({
    required this.id,
    required this.nombre,
    required this.ambito,
    required this.padreId,
    required this.subCarpetas,
    required this.archivos,
  });

  factory DriveCarpeta.fromJson(Map<String, dynamic> j) => DriveCarpeta(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        ambito: j['ambito']?.toString() ?? 'compartido',
        padreId: j['padre_id']?.toString(),
        subCarpetas: (j['sub_carpetas'] as num?)?.toInt() ?? 0,
        archivos: (j['archivos'] as num?)?.toInt() ?? 0,
      );
}

class DriveArchivo {
  final String id;
  final String nombre;
  final String? descripcion;
  final String ambito;
  final String? carpetaId;
  final String url;
  final String recursoTipo; // imagen | pdf | raw
  final String? formato;
  final int? bytes;
  final String? subidoPorId;
  final bool esMio;

  const DriveArchivo({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.ambito,
    required this.carpetaId,
    required this.url,
    required this.recursoTipo,
    required this.formato,
    required this.bytes,
    required this.subidoPorId,
    required this.esMio,
  });

  factory DriveArchivo.fromJson(Map<String, dynamic> j) => DriveArchivo(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        descripcion: j['descripcion']?.toString(),
        ambito: j['ambito']?.toString() ?? 'compartido',
        carpetaId: j['carpeta_id']?.toString(),
        url: j['url']?.toString() ?? '',
        recursoTipo: j['recurso_tipo']?.toString() ?? 'raw',
        formato: j['formato']?.toString(),
        bytes: (j['bytes'] as num?)?.toInt(),
        subidoPorId: j['subido_por_id']?.toString(),
        esMio: j['es_mio'] == true,
      );

  String get tamanoLegible {
    final b = bytes;
    if (b == null) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
