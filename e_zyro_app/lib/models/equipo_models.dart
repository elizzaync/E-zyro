/// DTO de Equipo / Herramienta propia de E-System (tabla `equipo`).
class EquipoItem {
  final String id;
  final String nombre;
  final String codigo;
  final String clase;       // 'equipo' | 'herramienta'
  final String? tipo;
  final String? marca;
  final String? modelo;
  final String? numeroSerie;
  final int cantidad;
  final String estado;      // operativo | en_mantenimiento | fuera_de_servicio | baja
  final bool requiereMantenimiento;
  final String frecuenciaMantenimiento;
  final String? proximaFechaMantenimiento;
  final String? fechaAdquisicion;
  final String? ubicacion;
  // Jerarquía geográfica (FK)
  final String? ubicacionId;
  final String? zonaId;
  final String? areaId;
  final String? fichaTecnica;

  const EquipoItem({
    required this.id,
    required this.nombre,
    required this.codigo,
    required this.clase,
    this.tipo,
    this.marca,
    this.modelo,
    this.numeroSerie,
    required this.cantidad,
    required this.estado,
    required this.requiereMantenimiento,
    required this.frecuenciaMantenimiento,
    this.proximaFechaMantenimiento,
    this.fechaAdquisicion,
    this.ubicacion,
    this.ubicacionId,
    this.zonaId,
    this.areaId,
    this.fichaTecnica,
  });

  factory EquipoItem.fromJson(Map<String, dynamic> j) => EquipoItem(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        codigo: j['codigo']?.toString() ?? '',
        clase: j['clase']?.toString() ?? 'equipo',
        tipo: j['tipo']?.toString(),
        marca: j['marca']?.toString(),
        modelo: j['modelo']?.toString(),
        numeroSerie: j['numeroSerie']?.toString(),
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 1,
        estado: j['estado']?.toString() ?? 'operativo',
        requiereMantenimiento: j['requiereMantenimiento'] as bool? ?? false,
        frecuenciaMantenimiento: j['frecuenciaMantenimiento']?.toString() ?? 'ninguno',
        proximaFechaMantenimiento: j['proximaFechaMantenimiento']?.toString(),
        fechaAdquisicion: j['fechaAdquisicion']?.toString(),
        ubicacion: j['ubicacion']?.toString(),
        ubicacionId: j['ubicacionId']?.toString(),
        zonaId: j['zonaId']?.toString(),
        areaId: j['areaId']?.toString(),
        fichaTecnica: j['fichaTecnica']?.toString(),
      );

  bool get esHerramienta => clase == 'herramienta';
}

class EquiposListResponse {
  final List<EquipoItem> items;
  final int total;
  final int page;
  final int pageSize;

  const EquiposListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory EquiposListResponse.fromJson(Map<String, dynamic> j) => EquiposListResponse(
        items: (j['items'] as List? ?? [])
            .map((e) => EquipoItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        pageSize: (j['pageSize'] as num?)?.toInt() ?? 30,
      );
}
