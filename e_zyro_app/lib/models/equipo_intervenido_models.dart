import 'proyecto_models.dart' show ProcedimientoDetalle;

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
  // Plan de mantenimiento
  final String? ultimoMantenimiento;   // yyyy-MM-dd
  final String? proximoMantenimiento;  // yyyy-MM-dd
  final int? frecuenciaMeses;
  // Nombres resueltos del backend
  final String? proyectoNombre;
  final String? clienteNombre;
  final String? ubicacionNombre;
  final String? zonaNombre;
  final String? areaNombre;
  final String? tipoEquipoNombre;
  // Procedimientos designados del servicio vinculado (solo viene en el detalle).
  final List<ProcedimientoDetalle> procedimientos;

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
    this.ultimoMantenimiento,
    this.proximoMantenimiento,
    this.frecuenciaMeses,
    this.proyectoNombre,
    this.clienteNombre,
    this.ubicacionNombre,
    this.zonaNombre,
    this.areaNombre,
    this.tipoEquipoNombre,
    this.procedimientos = const [],
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
        ultimoMantenimiento: j['ultimo_mantenimiento']?.toString(),
        proximoMantenimiento: j['proximo_mantenimiento']?.toString(),
        frecuenciaMeses: (j['frecuencia_meses'] as num?)?.toInt(),
        proyectoNombre: j['proyecto_nombre']?.toString(),
        clienteNombre: j['cliente_nombre']?.toString(),
        ubicacionNombre: j['ubicacion_nombre']?.toString(),
        zonaNombre: j['zona_nombre']?.toString(),
        areaNombre: j['area_nombre']?.toString(),
        tipoEquipoNombre: j['tipo_equipo_nombre']?.toString(),
        procedimientos: (j['procedimientos'] as List? ?? [])
            .map((p) => ProcedimientoDetalle.fromJson(p as Map<String, dynamic>))
            .toList(),
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

  /// Fecha del próximo mantenimiento como DateTime (null si no hay plan).
  DateTime? get proximoMantDate =>
      proximoMantenimiento == null ? null : DateTime.tryParse(proximoMantenimiento!);

  /// Fecha del último mantenimiento como DateTime.
  DateTime? get ultimoMantDate =>
      ultimoMantenimiento == null ? null : DateTime.tryParse(ultimoMantenimiento!);

  /// Días que faltan para el próximo mantenimiento (negativo si está vencido).
  int? get diasParaMantenimiento {
    final p = proximoMantDate;
    if (p == null) return null;
    final hoy = DateTime.now();
    return DateTime(p.year, p.month, p.day)
        .difference(DateTime(hoy.year, hoy.month, hoy.day))
        .inDays;
  }
}

/// Evento del historial de mantenimientos de un equipo intervenido.
class MantenimientoEquipo {
  final String id;
  final String equipoIntervenidoId;
  final String fecha; // yyyy-MM-dd
  final String tipo;  // preventivo | correctivo | inspeccion | otro
  final String? descripcion;
  final String? realizadoPor;
  final String? proximoCalculado;
  final String createdAt;

  const MantenimientoEquipo({
    required this.id,
    required this.equipoIntervenidoId,
    required this.fecha,
    required this.tipo,
    this.descripcion,
    this.realizadoPor,
    this.proximoCalculado,
    required this.createdAt,
  });

  factory MantenimientoEquipo.fromJson(Map<String, dynamic> j) => MantenimientoEquipo(
        id: j['id']?.toString() ?? '',
        equipoIntervenidoId: j['equipo_intervenido_id']?.toString() ?? '',
        fecha: j['fecha']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? 'preventivo',
        descripcion: j['descripcion']?.toString(),
        realizadoPor: j['realizado_por']?.toString(),
        proximoCalculado: j['proximo_calculado']?.toString(),
        createdAt: j['created_at']?.toString() ?? '',
      );

  DateTime? get fechaDate => DateTime.tryParse(fecha);
}
