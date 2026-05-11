import 'dart:convert';
import '../core/api_client.dart';
import '../models/proyecto_models.dart';

class ProyectoService {
  final ApiClient _client;
  ProyectoService(this._client);

  Future<List<ProyectoServicio>> getMisServicios() async {
    try {
      final r = await _client.get('/proyectos/mis-servicios');
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final list = data is Map
            ? (data['servicios'] as List? ?? [])
            : (data as List? ?? []);
        return list
            .map((e) => ProyectoServicio.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
