// DTOs de Vacaciones por ley (Punto 3.3).

class ConfigVacaciones {
  final String regimen; // general|remype|otro
  final int diasPorAnio;
  final int topeAcumulacion;

  const ConfigVacaciones({
    required this.regimen,
    required this.diasPorAnio,
    required this.topeAcumulacion,
  });

  factory ConfigVacaciones.fromJson(Map<String, dynamic> j) => ConfigVacaciones(
        regimen: j['regimen']?.toString() ?? 'general',
        diasPorAnio: (j['dias_por_anio'] as num?)?.toInt() ?? 30,
        topeAcumulacion: (j['tope_acumulacion'] as num?)?.toInt() ?? 30,
      );
}

class SaldoVacaciones {
  final String empleadoId;
  final String? empleadoNombre;
  final String? fechaIngreso;
  final int mesesServicio;
  final int anosServicio;
  final int diasPorAnio;
  final double devengado;
  final int ajusteDias;
  final int gozado;
  final double disponible;
  final int topeAcumulacion;

  const SaldoVacaciones({
    required this.empleadoId,
    this.empleadoNombre,
    this.fechaIngreso,
    this.mesesServicio = 0,
    this.anosServicio = 0,
    this.diasPorAnio = 0,
    this.devengado = 0,
    this.ajusteDias = 0,
    this.gozado = 0,
    this.disponible = 0,
    this.topeAcumulacion = 0,
  });

  factory SaldoVacaciones.fromJson(Map<String, dynamic> j) => SaldoVacaciones(
        empleadoId: j['empleado_id']?.toString() ?? '',
        empleadoNombre: j['empleado_nombre']?.toString(),
        fechaIngreso: j['fecha_ingreso']?.toString(),
        mesesServicio: (j['meses_servicio'] as num?)?.toInt() ?? 0,
        anosServicio: (j['anos_servicio'] as num?)?.toInt() ?? 0,
        diasPorAnio: (j['dias_por_anio'] as num?)?.toInt() ?? 0,
        devengado: (j['devengado'] as num?)?.toDouble() ?? 0,
        ajusteDias: (j['ajuste_dias'] as num?)?.toInt() ?? 0,
        gozado: (j['gozado'] as num?)?.toInt() ?? 0,
        disponible: (j['disponible'] as num?)?.toDouble() ?? 0,
        topeAcumulacion: (j['tope_acumulacion'] as num?)?.toInt() ?? 0,
      );
}

class SolicitudVacaciones {
  final String id;
  final String empleadoId;
  final String? empleadoNombre;
  final String? fechaInicio;
  final String? fechaFin;
  final int dias;
  final String estado; // pendiente|aprobada|rechazada|cancelada
  final String? motivo;
  final String? fechaResolucion;

  const SolicitudVacaciones({
    required this.id,
    required this.empleadoId,
    this.empleadoNombre,
    this.fechaInicio,
    this.fechaFin,
    this.dias = 0,
    this.estado = 'pendiente',
    this.motivo,
    this.fechaResolucion,
  });

  factory SolicitudVacaciones.fromJson(Map<String, dynamic> j) => SolicitudVacaciones(
        id: j['id']?.toString() ?? '',
        empleadoId: j['empleado_id']?.toString() ?? '',
        empleadoNombre: j['empleado_nombre']?.toString(),
        fechaInicio: j['fecha_inicio']?.toString(),
        fechaFin: j['fecha_fin']?.toString(),
        dias: (j['dias'] as num?)?.toInt() ?? 0,
        estado: j['estado']?.toString() ?? 'pendiente',
        motivo: j['motivo']?.toString(),
        fechaResolucion: j['fecha_resolucion']?.toString(),
      );
}
