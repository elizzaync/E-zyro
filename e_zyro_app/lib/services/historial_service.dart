import 'dart:convert';
import '../core/api_client.dart';
import '../models/historial_models.dart';

// HU-19: Historial de equipos y descarga de informes
class HistorialService {
  final ApiClient _client;
  HistorialService(this._client);

  // GET /operaciones/equipos/{equipo_id}/historial
  Future<List<MantenimientoHistorial>> getHistorialEquipo(
      String equipoId) async {
    try {
      final r = await _client.get('/operaciones/equipos/$equipoId/historial');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        final bodyMap = body is Map ? body : null;
        final list = body is List
            ? body
            : bodyMap?['data'] as List? ??
                bodyMap?['historial'] as List? ??
                [];
        return list
            .map((e) =>
                MantenimientoHistorial.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/mantenimientos/{mantenimiento_id}/informe-pdf
  // Returns the PDF URL or null
  Future<String?> getInformePdfUrl(String mantenimientoId) async {
    try {
      final r = await _client
          .get('/operaciones/mantenimientos/$mantenimientoId/informe-pdf');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['url'] as String? ??
            body['pdf_url'] as String? ??
            body['informe_pdf_url'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // GET /operaciones/mantenimientos/{mantenimiento_id}/evidencias-zip
  // Returns the ZIP URL or null
  Future<String?> getEvidenciasZipUrl(String mantenimientoId) async {
    try {
      final r = await _client
          .get('/operaciones/mantenimientos/$mantenimientoId/evidencias-zip');
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        return body['url'] as String? ??
            body['zip_url'] as String? ??
            body['evidencias_zip_url'] as String?;
      }
    } catch (_) {}
    return null;
  }

  // GET /operaciones/mis-proyectos/historial — HU-45
  Future<List<ProyectoHistorial>> getMisProyectosHistorial() async {
    try {
      final r = await _client.get('/operaciones/mis-proyectos/historial');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => ProyectoHistorial.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
