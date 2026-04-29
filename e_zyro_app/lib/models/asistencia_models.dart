class RegistroAsistencia {
  final String id;
  final DateTime timestamp;
  final String tipo; // ENTRADA | SALIDA
  final String status; // APROBADO | RECHAZADO | ERROR
  final double score;
  final double? latitud;
  final double? longitud;
  final String? motivo;

  const RegistroAsistencia({
    required this.id,
    required this.timestamp,
    required this.tipo,
    required this.status,
    required this.score,
    this.latitud,
    this.longitud,
    this.motivo,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'tipo': tipo,
    'status': status,
    'score': score,
    'latitud': latitud,
    'longitud': longitud,
    'motivo': motivo,
  };

  factory RegistroAsistencia.fromJson(Map<String, dynamic> json) {
    return RegistroAsistencia(
      id: json['id'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
      tipo: json['tipo'] as String? ?? '',
      status: json['status'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      latitud: (json['latitud'] as num?)?.toDouble(),
      longitud: (json['longitud'] as num?)?.toDouble(),
      motivo: json['motivo'] as String?,
    );
  }
}

class VerificacionResponse {
  final String status; // APROBADO | RECHAZADO | ERROR
  final double score;
  final String motivo;
  final String timestamp;

  const VerificacionResponse({
    required this.status,
    required this.score,
    required this.motivo,
    required this.timestamp,
  });

  factory VerificacionResponse.fromJson(Map<String, dynamic> json) {
    return VerificacionResponse(
      status: json['status'] as String? ?? 'ERROR',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      motivo: json['motivo'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
    );
  }
}
