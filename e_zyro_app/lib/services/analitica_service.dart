import 'dart:convert';
import '../core/api_client.dart';
import '../models/analitica_models.dart';

/// Cliente de dashboards ejecutivos (`/analitica`). Solo lectura.
class AnaliticaService {
  final ApiClient _client;
  AnaliticaService(this._client);

  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final r = await _client.get('/analitica/$path');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map<String, dynamic>) return body;
      }
    } catch (_) {}
    return null;
  }

  Future<DashOperaciones?> operaciones() async {
    final j = await _get('operaciones');
    if (j == null || j['sin_permiso'] == true) return null;
    return DashOperaciones.fromJson(j);
  }

  Future<DashLogistica?> logistica() async {
    final j = await _get('logistica');
    if (j == null || j['sin_permiso'] == true) return null;
    return DashLogistica.fromJson(j);
  }

  Future<DashPersonal?> personal() async {
    final j = await _get('personal');
    if (j == null || j['sin_permiso'] == true) return null;
    return DashPersonal.fromJson(j);
  }

  Future<DashActivos?> activos() async {
    final j = await _get('activos');
    if (j == null || j['sin_permiso'] == true) return null;
    return DashActivos.fromJson(j);
  }
}
