enum EstadoSync { pendiente, enviando, enviado, fallido }

class RegistroAsistenciaLocal {
  final String uuid;
  final DateTime timestampDispositivo; // siempre UTC
  final double latitud;
  final double longitud;
  final String tipoMarcacion; // entrada | salida | entrada_almuerzo | salida_almuerzo
  final String? evidenciaPath;
  final EstadoSync estadoSync;
  final int retryCount;
  final DateTime? lastAttemptAt;
  /// Fuente del timestamp: ntp_monotonic | ntp_device | device_only | sospechoso
  final String fuenteTiempo;

  const RegistroAsistenciaLocal({
    required this.uuid,
    required this.timestampDispositivo,
    required this.latitud,
    required this.longitud,
    required this.tipoMarcacion,
    this.evidenciaPath,
    this.estadoSync = EstadoSync.pendiente,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.fuenteTiempo = 'device_only',
  });

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'timestamp_disp': timestampDispositivo.toUtc().toIso8601String(),
    'latitud': latitud,
    'longitud': longitud,
    'tipo_marcacion': tipoMarcacion,
    'evidencia_path': evidenciaPath,
    'estado_sync': estadoSync.index,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
    'fuente_tiempo': fuenteTiempo,
  };

  factory RegistroAsistenciaLocal.fromMap(Map<String, dynamic> m) =>
      RegistroAsistenciaLocal(
        uuid: m['uuid'] as String,
        timestampDispositivo: DateTime.parse(m['timestamp_disp'] as String),
        latitud: (m['latitud'] as num).toDouble(),
        longitud: (m['longitud'] as num).toDouble(),
        tipoMarcacion: m['tipo_marcacion'] as String,
        evidenciaPath: m['evidencia_path'] as String?,
        estadoSync: EstadoSync.values[m['estado_sync'] as int],
        retryCount: m['retry_count'] as int? ?? 0,
        lastAttemptAt: m['last_attempt_at'] != null
            ? DateTime.tryParse(m['last_attempt_at'] as String)
            : null,
        fuenteTiempo: m['fuente_tiempo'] as String? ?? 'device_only',
      );

  Map<String, dynamic> toApiPayload() => {
    'uuid_cliente': uuid,
    'timestamp': timestampDispositivo.toUtc().toIso8601String(),
    'latitud': latitud,
    'longitud': longitud,
    'tipo': tipoMarcacion,
    'fuente_tiempo': fuenteTiempo,
  };
}
