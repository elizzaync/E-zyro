import 'registro_asistencia_local.dart' show EstadoSync;

/// Evidencia de un procedimiento de servicio capturada en el dispositivo,
/// pendiente de subir al servidor (offline-first). Espeja el patrón de
/// [RegistroAsistenciaLocal].
class EvidenciaPendiente {
  final String uuid;
  final String procedimientoId;
  final String? servicioId;
  final String etapa; // antes | durante | despues
  final String? descripcion;
  final String fotoPath;
  final EstadoSync estadoSync;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final DateTime createdAt;

  const EvidenciaPendiente({
    required this.uuid,
    required this.procedimientoId,
    this.servicioId,
    required this.etapa,
    this.descripcion,
    required this.fotoPath,
    this.estadoSync = EstadoSync.pendiente,
    this.retryCount = 0,
    this.lastAttemptAt,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'procedimiento_id': procedimientoId,
    'servicio_id': servicioId,
    'etapa': etapa,
    'descripcion': descripcion,
    'foto_path': fotoPath,
    'estado_sync': estadoSync.index,
    'retry_count': retryCount,
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
  };

  factory EvidenciaPendiente.fromMap(Map<String, dynamic> m) =>
      EvidenciaPendiente(
        uuid: m['uuid'] as String,
        procedimientoId: m['procedimiento_id'] as String,
        servicioId: m['servicio_id'] as String?,
        etapa: m['etapa'] as String,
        descripcion: m['descripcion'] as String?,
        fotoPath: m['foto_path'] as String,
        estadoSync: EstadoSync.values[m['estado_sync'] as int],
        retryCount: m['retry_count'] as int? ?? 0,
        lastAttemptAt: m['last_attempt_at'] != null
            ? DateTime.tryParse(m['last_attempt_at'] as String)
            : null,
        createdAt:
            DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Resultado de intentar encolar/enviar una evidencia. Distingue un envío
/// exitoso, una cola por falta de conexión real (reintentable) y un
/// rechazo PERMANENTE del servidor (4xx — reintentar es inútil, hay que
/// avisarle al usuario el motivo real en vez del genérico "sin conexión").
class EvidenciaEnvioResultado {
  final bool enviada;
  final String? errorPermanente;
  const EvidenciaEnvioResultado({required this.enviada, this.errorPermanente});
}
