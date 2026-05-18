import 'dart:convert';
import '../core/api_client.dart';
import '../models/dashboard_models.dart';

class NotificacionService {
  final ApiClient _client;
  NotificacionService(this._client);

  Future<List<NotificacionItem>> getAll({bool soloNoLeidas = false}) async {
    final q = soloNoLeidas ? '?solo_no_leidas=true' : '';
    final r = await _client.get('/notificaciones$q');
    if (r.statusCode == 200) {
      final body = jsonDecode(r.body);
      // El backend puede devolver un array directo o un objeto envuelto
      final List raw = body is List
          ? body
          : (body['data'] as List? ??
              body['notificaciones'] as List? ??
              body['items'] as List? ??
              []);
      return raw
          .map((e) => NotificacionItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    if (r.statusCode == 401) throw Exception('Sesión expirada.');
    throw Exception('Error al cargar notificaciones');
  }

  Future<int> getUnreadCount() async {
    try {
      final r = await _client.get('/notificaciones/no-leidas/count');
      if (r.statusCode == 200) {
        return (jsonDecode(r.body)['total'] as int? ?? 0);
      }
    } catch (_) {}
    return 0;
  }

  Future<void> marcarLeida(String id) async {
    await _client.post('/notificaciones/$id/leer', {});
  }

  Future<void> marcarTodasLeidas() async {
    await _client.post('/notificaciones/leer-todo', {});
  }

  Future<void> eliminar(String id) async {
    final r = await _client.delete('/notificaciones/$id');
    if (r.statusCode != 200) throw Exception('No se pudo eliminar la notificación');
  }

  Future<void> eliminarLeidas() async {
    final r = await _client.delete('/notificaciones/eliminar-leidas');
    if (r.statusCode != 200) throw Exception('No se pudo eliminar las notificaciones leídas');
  }
}
