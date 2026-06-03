// DTOs del módulo de Planos (Drive híbrido): Carpeta, Plano, VersionPlano.

class Carpeta {
  final String id;
  final String nombre;
  final String? padreId;
  final String? proyectoId;
  final int subCarpetas;
  final int planos;
  const Carpeta({
    required this.id,
    required this.nombre,
    this.padreId,
    this.proyectoId,
    this.subCarpetas = 0,
    this.planos = 0,
  });
  factory Carpeta.fromJson(Map<String, dynamic> j) => Carpeta(
        id: j['id'].toString(),
        nombre: (j['nombre'] ?? '').toString(),
        padreId: j['padre_id']?.toString(),
        proyectoId: j['proyecto_id']?.toString(),
        subCarpetas: (j['sub_carpetas'] as num?)?.toInt() ?? 0,
        planos: (j['planos'] as num?)?.toInt() ?? 0,
      );

  int get totalElementos => subCarpetas + planos;
}

class VersionPlano {
  final String id;
  final String version;
  final String url;
  final String? formato;
  final int? bytes;
  final String? fecha;
  final bool esActiva;
  const VersionPlano({
    required this.id,
    required this.version,
    required this.url,
    this.formato,
    this.bytes,
    this.fecha,
    this.esActiva = false,
  });
  factory VersionPlano.fromJson(Map<String, dynamic> j) => VersionPlano(
        id: j['id'].toString(),
        version: (j['version'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        formato: j['formato']?.toString(),
        bytes: (j['bytes'] as num?)?.toInt(),
        fecha: j['fecha']?.toString(),
        esActiva: j['es_activa'] == true,
      );
}

class PlanoItem {
  final String id;
  final String nombre;
  final String? disciplina;
  final String? descripcion;
  final String? carpetaId;
  final String? proyectoId;
  final String? url;
  final String? formato;
  final int? bytes;
  final String? versionActiva;
  final int numVersiones;
  final List<VersionPlano> versiones;
  const PlanoItem({
    required this.id,
    required this.nombre,
    this.disciplina,
    this.descripcion,
    this.carpetaId,
    this.proyectoId,
    this.url,
    this.formato,
    this.bytes,
    this.versionActiva,
    this.numVersiones = 0,
    this.versiones = const [],
  });
  factory PlanoItem.fromJson(Map<String, dynamic> j) => PlanoItem(
        id: j['id'].toString(),
        nombre: (j['nombre'] ?? '').toString(),
        disciplina: j['disciplina']?.toString(),
        descripcion: j['descripcion']?.toString(),
        carpetaId: j['carpeta_id']?.toString(),
        proyectoId: j['proyecto_id']?.toString(),
        url: j['url']?.toString(),
        formato: j['formato']?.toString(),
        bytes: (j['bytes'] as num?)?.toInt(),
        versionActiva: j['version_activa']?.toString(),
        numVersiones: (j['num_versiones'] as num?)?.toInt() ?? 0,
        versiones: (j['versiones'] as List? ?? [])
            .map((e) => VersionPlano.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String get tamanoLegible => _fmtBytes(bytes);
}

String _fmtBytes(int? b) {
  if (b == null || b <= 0) return '';
  const u = ['B', 'KB', 'MB', 'GB'];
  double v = b.toDouble();
  int i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 && i > 0 ? 1 : 0)} ${u[i]}';
}
