enum TipoMensaje { mensaje, sistema }

class MensajeChat {
  final String? id;
  final TipoMensaje tipo;
  final String autor;
  final String texto;
  final DateTime fecha;

  const MensajeChat({
    this.id,
    required this.tipo,
    required this.autor,
    required this.texto,
    required this.fecha,
  });

  factory MensajeChat.fromJson(Map<String, dynamic> j) {
    final tipoStr = (j['tipo'] as String? ?? 'mensaje').toLowerCase();
    final tipo =
        tipoStr == 'sistema' ? TipoMensaje.sistema : TipoMensaje.mensaje;

    DateTime fecha;
    try {
      final raw = j['fecha'] as String?;
      fecha = raw != null ? DateTime.parse(raw).toLocal() : DateTime.now();
    } catch (_) {
      fecha = DateTime.now();
    }

    return MensajeChat(
      id: j['id'] as String?,
      tipo: tipo,
      // Accept 'autor' or 'nombre' field names
      autor: (j['autor'] ?? j['nombre'] ?? 'Usuario') as String,
      // Accept 'texto' or 'message' field names
      texto: (j['texto'] ?? j['message'] ?? '') as String,
      fecha: fecha,
    );
  }

  factory MensajeChat.sistema(String texto) => MensajeChat(
        tipo: TipoMensaje.sistema,
        autor: 'Sistema',
        texto: texto,
        fecha: DateTime.now(),
      );
}
