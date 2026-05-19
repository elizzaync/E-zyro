import 'dart:convert';
import '../core/api_client.dart';
import '../models/comunicado_models.dart';

class ComunicadoService {
  final ApiClient _client;
  ComunicadoService(this._client);

  Future<List<Comunicado>> getComunicados() async {
    try {
      final r = await _client.get('/comunicados');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final list = data is List
            ? data
            : (data as Map)['comunicados'] as List? ?? [];
        return list
            .map((e) => Comunicado.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> marcarLeido(String id) async {
    try {
      await _client.post('/comunicados/$id/leer', {});
    } catch (_) {}
  }

  // HU-13: Canal de difusión por proyecto
  // GET /comunicados/proyecto/{proyecto_id}
  Future<List<ComunicadoProyecto>> getComunicadosProyecto(
      String proyectoId) async {
    try {
      final r = await _client.get('/comunicados/proyecto/$proyectoId');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final list = data is List
            ? data
            : (data as Map)['comunicados'] as List? ?? [];
        return list
            .map((e) =>
                ComunicadoProyecto.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // PUT /comunicados/{id}/marcar-leido
  Future<void> marcarLeidoProyecto(String id) async {
    try {
      await _client.put('/comunicados/$id/marcar-leido', {});
    } catch (_) {}
  }
}
