import 'dart:convert';

/// Tipos de acción de operaciones que pueden encolarse offline.
class TipoAccion {
  static const toggleProc = 'toggle_proc';
  static const firmarReq = 'firmar_req';
  static const notaAdd = 'nota_add';
  static const notaUpdate = 'nota_update';
  static const notaDelete = 'nota_delete';
}

/// Una acción de operaciones pendiente de enviar al servidor (cola offline).
/// `payload` guarda los argumentos necesarios para reproducir la llamada.
class AccionPendiente {
  final String uuid;
  final String tipo;
  final Map<String, dynamic> payload;
  final String? servicioId;
  final int retryCount;

  const AccionPendiente({
    required this.uuid,
    required this.tipo,
    required this.payload,
    this.servicioId,
    this.retryCount = 0,
  });

  Map<String, dynamic> toMap() => {
        'uuid': uuid,
        'tipo': tipo,
        'payload': jsonEncode(payload),
        'servicio_id': servicioId,
        'estado_sync': 0,
        'retry_count': retryCount,
        'created_at': DateTime.now().toIso8601String(),
      };

  factory AccionPendiente.fromMap(Map<String, dynamic> m) => AccionPendiente(
        uuid: m['uuid'] as String,
        tipo: m['tipo'] as String,
        payload: (jsonDecode(m['payload'] as String) as Map)
            .cast<String, dynamic>(),
        servicioId: m['servicio_id'] as String?,
        retryCount: (m['retry_count'] as int?) ?? 0,
      );
}
