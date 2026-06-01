/// DTOs de Equipos Intervenidos — equipos del cliente mantenidos por E-System.
class EquipoIntervenido {
  final String id;
  final String empresaId;
  final String? proyectoId;
  final String? clienteId;
  final String? ubicacionId;
  final String? zonaId;
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
  final String? tipoEquipoNombre;

  const EquipoIntervenido({
    required this.id,
    required this.empresaId,
    this.proyectoId,
    this.clienteId,
    this.ubicacionId,
    this.zonaId,
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
    this.tipoEquipoNombre,
  });

  factory EquipoIntervenido.fromJson(Map<String, dynamic> j) => EquipoIntervenido(
        id: j['id']?.toString() ?? '',
        empresaId: j['empresa_id']?.toString() ?? '',
        proyectoId: j['proyecto_id']?.toString(),
        clienteId: j['cliente_id']?.toString(),
        ubicacionId: j['ubicacion_id']?.toString(),
        zonaId: j['zona_id']?.toString(),
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
        tipoEquipoNombre: j['tipo_equipo_nombre']?.toString(),
      );

  /// Cadena de ubicación: "Talma › Ayacucho › Almacén A › Área Logística"
  String get ubicacionCompleta {
    final partes = <String>[
      if (clienteNombre != null && clienteNombre!.isNotEmpty) clienteNombre!,
      if (ubicacionNombre != null && ubicacionNombre!.isNotEmpty) ubicacionNombre!,
      if (zonaNombre != null && zonaNombre!.isNotEmpty) zonaNombre!,
      if (areaDescripcion != null && areaDescripcion!.isNotEmpty) areaDescripcion!,
    ];
    return partes.join(' › ');
  }
}
