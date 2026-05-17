import 'dart:convert';
import '../core/api_client.dart';
import '../models/requerimiento_models.dart';

class RequerimientoService {
  final ApiClient _client;
  RequerimientoService(this._client);

  Future<List<CatalogoItem>> getCatalogo(String q) async {
    try {
      final path = q.trim().isEmpty
          ? '/requerimientos/catalogo'
          : '/requerimientos/catalogo?q=${Uri.encodeComponent(q.trim())}';
      final r = await _client.get(path);
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => CatalogoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<MiSolicitud>> getMisSolicitudes() async {
    try {
      final r = await _client.get('/requerimientos/mis-solicitudes');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => MiSolicitud.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> crearSolicitud({
    required String proyectoId,
    required List<Map<String, dynamic>> items,
    String? observacion,
  }) async {
    try {
      final body = <String, dynamic>{
        'proyecto_id': proyectoId,
        'items': items,
        if (observacion != null && observacion.isNotEmpty)
          'observacion': observacion,
      };
      final r = await _client.post('/requerimientos/crear', body);
      return r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
