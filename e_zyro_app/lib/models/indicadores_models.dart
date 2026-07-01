// DTOs de Indicadores de desempeño (Punto 3.4).

class IndicadorEmpleado {
  final String empleadoId;
  final String? empleadoNombre;
  final String? cargo;
  final int evaluacionesTotal;
  final double? promedioEvaluaciones;
  final int asistenciaTotal;
  final int asistenciaValidados;
  final double? puntualidadPct;
  final double vacacionesDisponible;
  final int vacacionesGozado;
  final double? scoreGlobal;
  /// Promedio de evaluación (1-10) por periodo, últimos periodos con
  /// evaluaciones completadas, orden cronológico ascendente. <2 elementos =
  /// sin historial suficiente para graficar tendencia.
  final List<double> tendencia;

  const IndicadorEmpleado({
    required this.empleadoId,
    this.empleadoNombre,
    this.cargo,
    this.evaluacionesTotal = 0,
    this.promedioEvaluaciones,
    this.asistenciaTotal = 0,
    this.asistenciaValidados = 0,
    this.puntualidadPct,
    this.vacacionesDisponible = 0,
    this.vacacionesGozado = 0,
    this.scoreGlobal,
    this.tendencia = const [],
  });

  factory IndicadorEmpleado.fromJson(Map<String, dynamic> j) => IndicadorEmpleado(
        empleadoId: j['empleado_id']?.toString() ?? '',
        empleadoNombre: j['empleado_nombre']?.toString(),
        cargo: j['cargo']?.toString(),
        evaluacionesTotal: (j['evaluaciones_total'] as num?)?.toInt() ?? 0,
        promedioEvaluaciones: (j['promedio_evaluaciones'] as num?)?.toDouble(),
        asistenciaTotal: (j['asistencia_total'] as num?)?.toInt() ?? 0,
        asistenciaValidados: (j['asistencia_validados'] as num?)?.toInt() ?? 0,
        puntualidadPct: (j['puntualidad_pct'] as num?)?.toDouble(),
        vacacionesDisponible: (j['vacaciones_disponible'] as num?)?.toDouble() ?? 0,
        vacacionesGozado: (j['vacaciones_gozado'] as num?)?.toInt() ?? 0,
        scoreGlobal: (j['score_global'] as num?)?.toDouble(),
        tendencia: ((j['tendencia'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList(),
      );
}

class ResumenDesempeno {
  final int empleados;
  final double? promedioEvaluaciones;
  final double? puntualidadPromedio;
  final double? calificacionCliente;
  final List<IndicadorEmpleado> top;

  const ResumenDesempeno({
    this.empleados = 0,
    this.promedioEvaluaciones,
    this.puntualidadPromedio,
    this.calificacionCliente,
    this.top = const [],
  });

  factory ResumenDesempeno.fromJson(Map<String, dynamic> j) => ResumenDesempeno(
        empleados: (j['empleados'] as num?)?.toInt() ?? 0,
        promedioEvaluaciones: (j['promedio_evaluaciones'] as num?)?.toDouble(),
        puntualidadPromedio: (j['puntualidad_promedio'] as num?)?.toDouble(),
        calificacionCliente: (j['calificacion_cliente'] as num?)?.toDouble(),
        top: ((j['top'] as List?) ?? [])
            .map((e) => IndicadorEmpleado.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
