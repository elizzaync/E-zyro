import 'dart:convert';
import '../core/api_client.dart';
import '../models/mantenimiento_models.dart';

class MantenimientoService {
  final ApiClient _client;
  MantenimientoService(this._client);

  // GET /operaciones/proyecto/{proyecto_id}/equipos
  Future<List<EquipoItem>> getEquiposProyecto(String proyectoId) async {
    try {
      final r = await _client.get('/operaciones/proyecto/$proyectoId/equipos');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => EquipoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /operaciones/equipo/{equipo_id}/checklist
  Future<ChecklistEquipo?> getChecklist(String equipoId) async {
    try {
      final r = await _client.get('/operaciones/equipo/$equipoId/checklist');
      if (r.statusCode == 200) {
        return ChecklistEquipo.fromJson(
            jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  // POST /operaciones/paso/{paso_id}/evidencia  (multipart)
  Future<bool> uploadEvidencia(
    String pasoId,
    FotoTipo tipo,
    String filePath, {
    double? lat,
    double? lng,
    String? takenAt,
  }) async {
    try {
      final fields = <String, String>{
        'tipo': tipo.apiValue,
        if (lat != null) 'lat': lat.toStringAsFixed(7),
        if (lng != null) 'lng': lng.toStringAsFixed(7),
        if (takenAt != null) 'taken_at': takenAt,
      };
      final r = await _client.postMultipart(
        '/operaciones/paso/$pasoId/evidencia',
        fields,
        'foto',
        filePath,
      );
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // PATCH /operaciones/equipo/{equipo_id}/mantenimiento
  Future<bool> patchMantenimiento(String equipoId, String status) async {
    try {
      final r = await _client.patch(
        '/operaciones/equipo/$equipoId/mantenimiento',
        {'status': status},
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // HU-18: POST /operaciones/mantenimientos/{equipo_id}/finalizar — genera informe PDF
  Future<bool> finalizarMantenimiento(String equipoId) async {
    try {
      final r = await _client.post(
        '/operaciones/mantenimientos/$equipoId/finalizar',
        {},
      );
      return r.statusCode == 200 || r.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
