import 'dart:convert';
import '../core/api_client.dart';
import '../models/proyecto_models.dart';

class ProyectoService {
  final ApiClient _client;
  ProyectoService(this._client);

  // GET /operaciones/proyectos
  Future<ProyectosConKpis?> getProyectos() async {
    try {
      final r = await _client.get('/operaciones/proyectos');
      if (r.statusCode == 200) {
        return ProyectosConKpis.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // GET /operaciones/proyecto/{proyecto_id}/servicios
  Future<List<ServicioItem>> getServiciosProyecto(String proyectoId) async {
    try {
      final r = await _client.get('/operaciones/proyecto/$proyectoId/servicios');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => ServicioItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/servicio/{servicio_id}
  Future<ServicioDetalle?> getDetalleServicio(String servicioId) async {
    try {
      final r = await _client.get('/operaciones/servicio/$servicioId');
      if (r.statusCode == 200) {
        return ServicioDetalle.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // Legacy: usado por el dashboard
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
