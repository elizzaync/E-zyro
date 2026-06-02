import 'dart:convert';

import '../core/api_client.dart';

/// Un mensaje del historial de la conversación con E-Zybot.
/// La API es stateless: en cada petición se envía el historial completo.
class ChatbotMensaje {
  final String role; // 'user' | 'assistant'
  final String content;
  const ChatbotMensaje(this.role, this.content);

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// Respuesta del asistente para un turno.
class ChatbotRespuesta {
  final String respuesta;
  final List<String> herramientasUsadas;
  const ChatbotRespuesta(this.respuesta, this.herramientasUsadas);
}

/// Cliente del chatbot E-Zybot → `POST /chatbot/mensaje`.
class ChatbotService {
  final ApiClient _api;
  ChatbotService(this._api);

  /// Envía el historial completo y devuelve la respuesta del asistente.
  /// El modelo puede tardar (tool-use sobre la BD), de ahí el timeout amplio.
  Future<ChatbotRespuesta> enviar(List<ChatbotMensaje> historial) async {
    final r = await _api.post(
      '/chatbot/mensaje',
      {'mensajes': historial.map((m) => m.toJson()).toList()},
      timeout: const Duration(seconds: 90),
    );
    _api.checkResponse(r, fallback: 'No se pudo contactar al asistente');

    // bodyBytes + utf8 para conservar tildes y eñes correctamente.
    final data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final tools = (data['herramientas_usadas'] as List? ?? const [])
        .map((h) => (h as Map)['nombre']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();

    return ChatbotRespuesta(
      (data['respuesta'] ?? '') as String,
      tools,
    );
  }
}
