import 'dart:convert';

import '../core/api_client.dart';

/// Asistente IA de Logística — REST puro sobre el proxy del backend
/// (POST /chatbot/chat). Sin WebSocket: cada pregunta es un request y el
/// historial por usuario vive en el servidor del chatbot.
class ChatbotService {
  final ApiClient _client;
  ChatbotService(this._client);

  /// Envía [message] y devuelve la respuesta del asistente (markdown).
  /// [pantalla] es la pantalla de origen, viaja como contexto.
  /// Lanza [Exception] con mensaje legible si el asistente no responde.
  Future<String> preguntar(String message, {String? pantalla}) async {
    // El backend espera hasta 60 s al chatbot: el timeout local debe ser mayor
    // que ese, no el default de 30 s del ApiClient.
    final r = await _client.post(
      '/chatbot/chat',
      {'message': message, 'pantalla': ?pantalla},
      timeout: const Duration(seconds: 70),
    );
    _client.checkResponse(r, fallback: 'No se pudo contactar al asistente');
    final answer =
        (jsonDecode(r.body) as Map<String, dynamic>)['answer'];
    return answer?.toString() ?? '';
  }
}
