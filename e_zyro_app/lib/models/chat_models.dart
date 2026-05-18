enum TipoMensaje { mensaje, sistema }

class MensajeChat {
  final String? id;
  final TipoMensaje tipo;
  final String autor;
  final String? remitenteId;
  final String? fotoUrl;
  final String texto;
  final DateTime fecha;
  final String? destinatarioId;

  const MensajeChat({
    this.id,
    required this.tipo,
    required this.autor,
    this.remitenteId,
    this.fotoUrl,
    required this.texto,
    required this.fecha,
    this.destinatarioId,
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

    final rawFoto = (j['foto_url'] ??
            j['remitente_foto_url'] ??
            j['foto_remitente'] ??
            j['avatar_url']) as String?;

    return MensajeChat(
      id: j['id'] as String?,
      tipo: tipo,
      // Backend envía 'nombre_remitente' o 'remitente_nombre'; fallback a 'autor'/'nombre'
      autor: (j['nombre_remitente'] ??
              j['remitente_nombre'] ??
              j['autor'] ??
              j['nombre'] ??
              'Usuario') as String,
      remitenteId: j['remitente_id'] as String?,
      fotoUrl: (rawFoto != null && rawFoto.isNotEmpty) ? rawFoto : null,
      // Backend envía 'contenido'; fallback a 'texto'/'message'
      texto: (j['contenido'] ?? j['texto'] ?? j['message'] ?? '') as String,
      fecha: fecha,
      destinatarioId: j['destinatario_id'] as String?,
    );
  }

  factory MensajeChat.sistema(String texto) => MensajeChat(
        tipo: TipoMensaje.sistema,
        autor: 'Sistema',
        texto: texto,
        fecha: DateTime.now(),
      );
}
