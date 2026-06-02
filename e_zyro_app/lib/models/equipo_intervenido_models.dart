/// DTOs de Equipos Intervenidos — equipos del cliente mantenidos por E-System.
class EquipoIntervenido {
  final String id;
  final String empresaId;
  final String? proyectoId;
  final String? clienteId;
  final String? ubicacionId;
  final String? zonaId;
  final String? areaId;
  final String? areaDescripcion;
  final String nombre;
  final String? codigo;
  final String? tipoEquipoId;
  final String? marca;
  final String? modelo;
  final String? numeroSerie;
  final String estado;
  final String? fechaInstalacion;
  final Map<String, dynamic>? fichaTecnica;
  final String? observaciones;
  final bool activo;
  final String createdAt;
  // Nombres resueltos del backend
  final String? proyectoNombre;
  final String? clienteNombre;
  final String? ubicacionNombre;
  final String? zonaNombre;
  final String? areaNombre;
  final String? tipoEquipoNombre;

  const EquipoIntervenido({
    required this.id,
    required this.empresaId,
    this.proyectoId,
    this.clienteId,
    this.ubicacionId,
    this.zonaId,
    this.areaId,
    this.areaDescripcion,
    required this.nombre,
    this.codigo,
    this.tipoEquipoId,
    this.marca,
    this.modelo,
    this.numeroSerie,
    required this.estado,
    this.fechaInstalacion,
    this.fichaTecnica,
    this.observaciones,
    required this.activo,
    required this.createdAt,
    this.proyectoNombre,
    this.clienteNombre,
    this.ubicacionNombre,
    this.zonaNombre,
    this.areaNombre,
    this.tipoEquipoNombre,
  });

  factory EquipoIntervenido.fromJson(Map<String, dynamic> j) => EquipoIntervenido(
        id: j['id']?.toString() ?? '',
        empresaId: j['empresa_id']?.toString() ?? '',
        proyectoId: j['proyecto_id']?.toString(),
        clienteId: j['cliente_id']?.toString(),
        ubicacionId: j['ubicacion_id']?.toString(),
        zonaId: j['zona_id']?.toString(),
        areaId: j['area_id']?.toString(),
        areaDescripcion: j['area_descripcion']?.toString(),
        nombre: j['nombre']?.toString() ?? '',
        codigo: j['codigo']?.toString(),
        tipoEquipoId: j['tipo_equipo_id']?.toString(),
        marca: j['marca']?.toString(),
        modelo: j['modelo']?.toString(),
        numeroSerie: j['numero_serie']?.toString(),
        estado: j['estado']?.toString() ?? 'operativo',
        fechaInstalacion: j['fecha_instalacion']?.toString(),
        fichaTecnica: j['ficha_tecnica'] is Map
            ? Map<String, dynamic>.from(j['ficha_tecnica'] as Map)
            : null,
        observaciones: j['observaciones']?.toString(),
        activo: j['activo'] as bool? ?? true,
        createdAt: j['created_at']?.toString() ?? '',
        proyectoNombre: j['proyecto_nombre']?.toString(),
        clienteNombre: j['cliente_nombre']?.toString(),
        ubicacionNombre: j['ubicacion_nombre']?.toString(),
        zonaNombre: j['zona_nombre']?.toString(),
        areaNombre: j['area_nombre']?.toString(),
        tipoEquipoNombre: j['tipo_equipo_nombre']?.toString(),
      );

  /// Cadena de ubicación: "Talma › Ayacucho › Almacén A › Área Logística".
  /// Prefiere el área del catálogo (areaNombre); cae al texto legacy si falta.
  String get ubicacionCompleta {
    final area = (areaNombre != null && areaNombre!.isNotEmpty)
        ? areaNombre!
        : (areaDescripcion ?? '');
    final partes = <String>[
      if (clienteNombre != null && clienteNombre!.isNotEmpty) clienteNombre!,
      if (ubicacionNombre != null && ubicacionNombre!.isNotEmpty) ubicacionNombre!,
      if (zonaNombre != null && zonaNombre!.isNotEmpty) zonaNombre!,
      if (area.isNotEmpty) area,
    ];
    return partes.join(' › ');
  }
}
