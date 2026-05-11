class ProyectoServicio {
  final String id;
  final String empresa;
  final String tipoServicio;
  final String ubicacion;
  final String estado;
  final String? supervisor;
  final String? fechaInicio;
  final String? fechaFin;
  final String? telefono;
  final bool urgente;

  const ProyectoServicio({
    required this.id,
    required this.empresa,
    required this.tipoServicio,
    required this.ubicacion,
    required this.estado,
    this.supervisor,
    this.fechaInicio,
    this.fechaFin,
    this.telefono,
    this.urgente = false,
  });

  factory ProyectoServicio.fromJson(Map<String, dynamic> j) => ProyectoServicio(
        id: j['id'] as String? ?? '',
        empresa: j['empresa'] as String? ?? '',
        tipoServicio: j['tipo_servicio'] as String? ?? '',
        ubicacion: j['ubicacion'] as String? ?? '',
        estado: _normalizeEstado(j['estado'] as String? ?? ''),
        supervisor: j['supervisor'] as String?,
        fechaInicio: j['fecha_inicio'] as String?,
        fechaFin: j['fecha_fin'] as String?,
        telefono: j['telefono'] as String?,
        urgente: j['urgente'] as bool? ?? false,
      );

  static String _normalizeEstado(String raw) => switch (raw.toLowerCase()) {
        'activo' => 'Activo',
        'completado' => 'Completado',
        _ => 'Pendiente',
      };
}
