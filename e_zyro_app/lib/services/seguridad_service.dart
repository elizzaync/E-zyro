import 'dart:convert';
import '../core/api_client.dart';
import '../models/seguridad_models.dart';

class SeguridadService {
  final ApiClient _client;
  SeguridadService(this._client);

  Future<List<SesionConexion>> getMisSesiones({int limit = 30}) async {
    try {
      final r = await _client.get('/seguridad/mis-sesiones?limit=$limit');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => SesionConexion.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<PersonalItem>> getUsuarios({String? q}) async {
    try {
      final query = (q != null && q.trim().isNotEmpty)
          ? '?q=${Uri.encodeComponent(q.trim())}'
          : '';
      final r = await _client.get('/seguridad/usuarios$query');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => PersonalItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<SesionConexion>> getSesionesDeUsuario(
    String usuarioId, {
    int limit = 50,
  }) async {
    try {
      final r = await _client.get(
        '/seguridad/usuarios/$usuarioId/sesiones?limit=$limit',
      );
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => SesionConexion.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
