class RegistroAsistencia {
  final String id;
  final DateTime timestamp;
  final String tipo; // ENTRADA | SALIDA | ENTRADA_ALMUERZO | SALIDA_ALMUERZO
  final String status; // APROBADO | RECHAZADO
  final String estado; // validado | pendiente | rechazado | justificado
  final double score; // 0.0 – 100.0
  final double? latitud;
  final double? longitud;
  final double? precisionM;
  final String? motivo;
  final String? resultadoIa; // aprobado | revision_manual | rechazado
  final String? fotoUrl;

  const RegistroAsistencia({
    required this.id,
    required this.timestamp,
    required this.tipo,
    required this.status,
    this.estado = 'pendiente',
    required this.score,
    this.latitud,
    this.longitud,
    this.precisionM,
    this.motivo,
    this.resultadoIa,
    this.fotoUrl,
  });

  factory RegistroAsistencia.fromJson(Map<String, dynamic> json) {
    final fechaStr =
        json['fecha_hora'] as String? ?? json['timestamp'] as String? ?? '';
    return RegistroAsistencia(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.tryParse(fechaStr) ?? DateTime.now(),
      tipo: ((json['tipo'] as String?) ?? '').toUpperCase(),
      status: json['status'] as String? ?? 'RECHAZADO',
      estado: json['estado'] as String? ?? 'pendiente',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
      precisionM: (json['precision_m'] as num?)?.toDouble(),
      motivo: json['motivo'] as String?,
      resultadoIa: json['resultado_ia'] as String?,
      fotoUrl: json['foto_url'] as String?,
    );
  }
}

class MarcarResponse {
  final String registroId;
  final String status; // APROBADO | RECHAZADO
  final double score;
  final String motivo;
  final DateTime timestamp;
  final bool gpsGuardado;
  final String? fotoUrl;
  final String resultadoIa; // aprobado | revision_manual | rechazado

  const MarcarResponse({
    required this.registroId,
    required this.status,
    required this.score,
    required this.motivo,
    required this.timestamp,
    required this.gpsGuardado,
    this.fotoUrl,
    required this.resultadoIa,
  });

  factory MarcarResponse.fromJson(Map<String, dynamic> json) {
    return MarcarResponse(
      registroId: json['registro_id'] as String? ?? '',
      status: json['status'] as String? ?? 'RECHAZADO',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      motivo: json['motivo'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      gpsGuardado: json['gps_guardado'] as bool? ?? false,
      fotoUrl: json['foto_url'] as String?,
      resultadoIa: json['resultado_ia'] as String? ?? 'rechazado',
    );
  }
}

/// Un día dentro del resumen semanal (GET /asistencia/mi-resumen-semanal).
class DiaResumen {
  final String fecha; // ISO yyyy-MM-dd
  final String label; // L M M J V S D
  final bool esHoy;
  final int? minutosTrabajados;
  final String? entradaHora;
  final String? salidaHora;
  final bool llegoTarde;
  final bool esExcepcion;

  const DiaResumen({
    required this.fecha,
    required this.label,
    this.esHoy = false,
    this.minutosTrabajados,
    this.entradaHora,
    this.salidaHora,
    this.llegoTarde = false,
    this.esExcepcion = false,
  });

  factory DiaResumen.fromJson(Map<String, dynamic> j) => DiaResumen(
        fecha: j['fecha'] as String? ?? '',
        label: j['label'] as String? ?? '',
        esHoy: j['es_hoy'] as bool? ?? false,
        minutosTrabajados: (j['minutos_trabajados'] as num?)?.toInt(),
        entradaHora: j['entrada_hora'] as String?,
        salidaHora: j['salida_hora'] as String?,
        llegoTarde: j['llego_tarde'] as bool? ?? false,
        esExcepcion: j['es_excepcion'] as bool? ?? false,
      );

  double get horas => (minutosTrabajados ?? 0) / 60.0;
}

/// Resumen semanal del empleado (pantalla personal). La puntualidad la calcula
/// el backend contra el plan/turno designado (respeta excepciones tipo TI).
class ResumenSemanal {
  final String semanaInicio; // ISO del lunes
  final int metaHoras; // p. ej. 48
  final int minutosTrabajadosSemana;
  final int diasTrabajados;
  final int promedioMinDiario;
  final int? puntualidadPct; // null si no hay días con entrada
  final List<DiaResumen> dias;

  const ResumenSemanal({
    this.semanaInicio = '',
    this.metaHoras = 48,
    this.minutosTrabajadosSemana = 0,
    this.diasTrabajados = 0,
    this.promedioMinDiario = 0,
    this.puntualidadPct,
    this.dias = const [],
  });

  factory ResumenSemanal.fromJson(Map<String, dynamic> j) => ResumenSemanal(
        semanaInicio: j['semana_inicio'] as String? ?? '',
        metaHoras: (j['meta_horas'] as num?)?.toInt() ?? 48,
        minutosTrabajadosSemana:
            (j['minutos_trabajados_semana'] as num?)?.toInt() ?? 0,
        diasTrabajados: (j['dias_trabajados'] as num?)?.toInt() ?? 0,
        promedioMinDiario: (j['promedio_min_diario'] as num?)?.toInt() ?? 0,
        puntualidadPct: (j['puntualidad_pct'] as num?)?.toInt(),
        dias: ((j['dias'] as List?) ?? const [])
            .map((e) => DiaResumen.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  double get horasSemana => minutosTrabajadosSemana / 60.0;
  double get progreso =>
      metaHoras == 0 ? 0 : (horasSemana / metaHoras).clamp(0.0, 1.0);
  int get progresoPct => (progreso * 100).round();

  /// Máximo de horas de la semana (para escalar las barras). Mínimo 8h.
  double get maxHorasDia {
    double m = 8;
    for (final d in dias) {
      if (d.horas > m) m = d.horas;
    }
    return m;
  }
}

class EstadoHoy {
  final bool tieneEntrada;
  final bool tieneSalida;
  final bool tieneFotoBase;
  final String? entradaHora; // "HH:MM"
  final String? salidaHora; // "HH:MM"
  final bool jornadaCompleta;
  // ── Almuerzo (v1 PYME) ──────────────────────────────────────────────────
  final bool tieneInicioAlmuerzo;
  final bool tieneFinAlmuerzo;
  final String? inicioAlmuerzoHora; // "HH:MM"
  final String? finAlmuerzoHora; // "HH:MM"
  final bool enAlmuerzo;
  final int? duracionAlmuerzoMin;
  final String? inicioAlmuerzoIso; // ISO 8601 del inicio (cronómetro / alerta)

  const EstadoHoy({
    required this.tieneEntrada,
    required this.tieneSalida,
    required this.tieneFotoBase,
    this.entradaHora,
    this.salidaHora,
    required this.jornadaCompleta,
    this.tieneInicioAlmuerzo = false,
    this.tieneFinAlmuerzo = false,
    this.inicioAlmuerzoHora,
    this.finAlmuerzoHora,
    this.enAlmuerzo = false,
    this.duracionAlmuerzoMin,
    this.inicioAlmuerzoIso,
  });

  factory EstadoHoy.fromJson(Map<String, dynamic> json) {
    return EstadoHoy(
      tieneEntrada: json['tiene_entrada'] as bool? ?? false,
      tieneSalida: json['tiene_salida'] as bool? ?? false,
      tieneFotoBase: json['tiene_foto_base'] as bool? ?? false,
      entradaHora: json['entrada_hora'] as String?,
      salidaHora: json['salida_hora'] as String?,
      jornadaCompleta: json['jornada_completa'] as bool? ?? false,
      tieneInicioAlmuerzo: json['tiene_inicio_almuerzo'] as bool? ?? false,
      tieneFinAlmuerzo: json['tiene_fin_almuerzo'] as bool? ?? false,
      inicioAlmuerzoHora: json['inicio_almuerzo_hora'] as String?,
      finAlmuerzoHora: json['fin_almuerzo_hora'] as String?,
      enAlmuerzo: json['en_almuerzo'] as bool? ?? false,
      duracionAlmuerzoMin: (json['duracion_almuerzo_min'] as num?)?.toInt(),
      inicioAlmuerzoIso: json['inicio_almuerzo_iso'] as String?,
    );
  }

  factory EstadoHoy.empty() => const EstadoHoy(
    tieneEntrada: false,
    tieneSalida: false,
    tieneFotoBase: false,
    jornadaCompleta: false,
  );

  /// Claves snake_case para round-trip con [EstadoHoy.fromJson] (caché local).
  Map<String, dynamic> toJson() => {
    'tiene_entrada': tieneEntrada,
    'tiene_salida': tieneSalida,
    'tiene_foto_base': tieneFotoBase,
    'entrada_hora': entradaHora,
    'salida_hora': salidaHora,
    'jornada_completa': jornadaCompleta,
    'tiene_inicio_almuerzo': tieneInicioAlmuerzo,
    'tiene_fin_almuerzo': tieneFinAlmuerzo,
    'inicio_almuerzo_hora': inicioAlmuerzoHora,
    'fin_almuerzo_hora': finAlmuerzoHora,
    'en_almuerzo': enAlmuerzo,
    'duracion_almuerzo_min': duracionAlmuerzoMin,
    'inicio_almuerzo_iso': inicioAlmuerzoIso,
  };

  EstadoHoy copyWith({
    bool? tieneEntrada,
    bool? tieneSalida,
    bool? tieneFotoBase,
    String? entradaHora,
    String? salidaHora,
    bool? jornadaCompleta,
    bool? tieneInicioAlmuerzo,
    bool? tieneFinAlmuerzo,
    String? inicioAlmuerzoHora,
    String? finAlmuerzoHora,
    bool? enAlmuerzo,
    int? duracionAlmuerzoMin,
    String? inicioAlmuerzoIso,
  }) => EstadoHoy(
    tieneEntrada: tieneEntrada ?? this.tieneEntrada,
    tieneSalida: tieneSalida ?? this.tieneSalida,
    tieneFotoBase: tieneFotoBase ?? this.tieneFotoBase,
    entradaHora: entradaHora ?? this.entradaHora,
    salidaHora: salidaHora ?? this.salidaHora,
    jornadaCompleta: jornadaCompleta ?? this.jornadaCompleta,
    tieneInicioAlmuerzo: tieneInicioAlmuerzo ?? this.tieneInicioAlmuerzo,
    tieneFinAlmuerzo: tieneFinAlmuerzo ?? this.tieneFinAlmuerzo,
    inicioAlmuerzoHora: inicioAlmuerzoHora ?? this.inicioAlmuerzoHora,
    finAlmuerzoHora: finAlmuerzoHora ?? this.finAlmuerzoHora,
    enAlmuerzo: enAlmuerzo ?? this.enAlmuerzo,
    duracionAlmuerzoMin: duracionAlmuerzoMin ?? this.duracionAlmuerzoMin,
    inicioAlmuerzoIso: inicioAlmuerzoIso ?? this.inicioAlmuerzoIso,
  );

  String? get tipoProximo {
    if (!tieneEntrada) return 'ENTRADA';
    if (!tieneSalida) return 'SALIDA';
    return null;
  }

  /// Estado del almuerzo para la UI del botón dinámico:
  /// 'bloqueado' (sin entrada) · 'disponible' (puede iniciar) ·
  /// 'en_curso' (almorzando) · 'completado' (ya almorzó).
  String get estadoAlmuerzo {
    if (tieneFinAlmuerzo) return 'completado';
    if (tieneInicioAlmuerzo) return 'en_curso';
    if (!tieneEntrada || tieneSalida) return 'bloqueado';
    return 'disponible';
  }
}
