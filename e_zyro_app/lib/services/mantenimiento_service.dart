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
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return null;
  }

  // POST /operaciones/sync/mantenimientos (lote, multipart)
  // Devuelve el set de ids locales que el servidor confirmo (ok=true), para
  // que el caller desencole solo esos y reintente el resto.
  Future<Set<String>> syncMantenimientos(List<EvidenciaPendiente> evs) async {
    if (evs.isEmpty) return {};
    try {
      final metadatos = jsonEncode(evs
          .map((ev) => {
                'id': ev.id,
                'paso_id': ev.pasoId,
                'tipo': ev.tipo.apiValue,
                if (ev.lat != null) 'lat': ev.lat,
                if (ev.lng != null) 'lng': ev.lng,
                'taken_at': ev.createdAt.toIso8601String(),
              })
          .toList());
      final r = await _client.postMultipartMany(
        '/operaciones/sync/mantenimientos',
        {'metadatos': metadatos},
        'fotos',
        evs.map((ev) => ev.filePath).toList(),
      );
      if (r.statusCode != 200 && r.statusCode != 201) return {};
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final resultados = (body['resultados'] as List? ?? []);
      return resultados
          .where((x) => x['ok'] == true)
          .map((x) => x['id'] as String)
          .toSet();
    } catch (_) {
      return {};
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

  // Equipos Intervenidos (Fase A): PATCH /operaciones/equipos/{id}/mantenimiento
  // Solo Admin / Jefe de Operaciones. Devuelve el equipo actualizado o null.
  Future<EquipoItem?> editarConfigMantenimiento(
    String equipoId, {
    bool? requiereMantenimiento,
    String? frecuencia,
    String? proximaFecha, // ISO yyyy-mm-dd
  }) async {
    try {
      final r = await _client.patch(
        '/operaciones/equipos/$equipoId/mantenimiento',
        {
          'requiere_mantenimiento': ?requiereMantenimiento,
          'frecuencia_mantenimiento': ?frecuencia,
          'proxima_fecha_mantenimiento': ?proximaFecha,
        },
      );
      if (r.statusCode == 200) {
        return EquipoItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }
}
