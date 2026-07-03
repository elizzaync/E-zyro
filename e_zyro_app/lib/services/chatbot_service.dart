import 'dart:convert';

import '../core/api_client.dart';

/// Acción estructurada que el asistente pide ejecutar en la app. El LLM tiene
/// una tool `abrir_pantalla` que NO ejecuta nada en el servidor: viaja como
/// dato junto a la respuesta y es la app quien decide si sabe ejecutarla.
class AccionChat {
  final String tipo; // hoy solo 'navegar'
  final String pantalla; // clave del catálogo de pantallas del backend
  final String? parametro;
  const AccionChat(
      {required this.tipo, required this.pantalla, this.parametro});

  factory AccionChat.fromJson(Map<String, dynamic> j) => AccionChat(
        tipo: j['tipo']?.toString() ?? '',
        pantalla: j['pantalla']?.toString() ?? '',
        parametro: j['parametro']?.toString(),
      );
}

class ChatbotRespuesta {
  final String answer;
  final List<AccionChat> acciones;
  const ChatbotRespuesta({required this.answer, this.acciones = const []});
}

/// Asistente E-zyro — REST puro sobre el proxy del backend (POST
/// /chatbot/chat). Sin WebSocket: cada pregunta es un request y el historial
/// por usuario vive en el servidor del chatbot.
class ChatbotService {
  final ApiClient _client;
  ChatbotService(this._client);

  /// Envía [message] y devuelve la respuesta del asistente (markdown) con sus
  /// acciones estructuradas. [pantalla] es la pantalla de origen (contexto).
  /// Lanza [Exception] con mensaje legible si el asistente no responde.
  Future<ChatbotRespuesta> preguntar(String message,
      {String? pantalla}) async {
    // El backend espera hasta 60 s al chatbot: el timeout local debe ser mayor
    // que ese, no el default de 30 s del ApiClient.
    final r = await _client.post(
      '/chatbot/chat',
      {'message': message, 'pantalla': ?pantalla},
      timeout: const Duration(seconds: 70),
    );
    _client.checkResponse(r, fallback: 'No se pudo contactar al asistente');
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final acciones = (body['acciones'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AccionChat.fromJson)
        .toList();
    return ChatbotRespuesta(
      answer: body['answer']?.toString() ?? '',
      acciones: acciones,
    );
  }
}
