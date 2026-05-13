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

class EstadoHoy {
  final bool tieneEntrada;
  final bool tieneSalida;
  final bool tieneFotoBase;
  final String? entradaHora; // "HH:MM"
  final String? salidaHora; // "HH:MM"
  final bool jornadaCompleta;

  const EstadoHoy({
    required this.tieneEntrada,
    required this.tieneSalida,
    required this.tieneFotoBase,
    this.entradaHora,
    this.salidaHora,
    required this.jornadaCompleta,
  });

  factory EstadoHoy.fromJson(Map<String, dynamic> json) {
    return EstadoHoy(
      tieneEntrada: json['tiene_entrada'] as bool? ?? false,
      tieneSalida: json['tiene_salida'] as bool? ?? false,
      tieneFotoBase: json['tiene_foto_base'] as bool? ?? false,
      entradaHora: json['entrada_hora'] as String?,
      salidaHora: json['salida_hora'] as String?,
      jornadaCompleta: json['jornada_completa'] as bool? ?? false,
    );
  }

  factory EstadoHoy.empty() => const EstadoHoy(
    tieneEntrada: false,
    tieneSalida: false,
    tieneFotoBase: false,
    jornadaCompleta: false,
  );

  String? get tipoProximo {
    if (!tieneEntrada) return 'ENTRADA';
    if (!tieneSalida) return 'SALIDA';
    return null;
  }
}
