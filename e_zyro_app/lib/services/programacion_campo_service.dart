import 'dart:convert';
import '../core/api_client.dart';
import '../models/programacion_campo_models.dart';

// HU-54: cuadrilla diaria por proyecto.
class ProgramacionCampoService {
  final ApiClient _client;
  ProgramacionCampoService(this._client);

  // POST /programacion-campo — crea/edita la cuadrilla de un dia (upsert).
  Future<ProgramacionCampoItem?> asignarCuadrilla({
    required String proyectoId,
    required String fecha, // ISO yyyy-mm-dd
    required List<String> empleadoIds,
    String tipo = 'servicio',
    String? descripcion,
  }) async {
    try {
      final r = await _client.post('/programacion-campo', {
        'proyecto_id': proyectoId,
        'fecha': fecha,
        'tipo': tipo,
        'descripcion': descripcion,
        'empleado_ids': empleadoIds,
      });
      if (r.statusCode == 200 || r.statusCode == 201) {
        return ProgramacionCampoItem.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    return null;
  }

  // GET /programacion-campo?fecha=&proyecto_id= — para Operaciones.
  Future<List<ProgramacionCampoItem>> listarProgramacion({
    String? fecha,
    String? proyectoId,
  }) async {
    try {
      final params = <String>[
        if (fecha != null) 'fecha=$fecha',
        if (proyectoId != null) 'proyecto_id=$proyectoId',
      ];
      final query = params.isEmpty ? '' : '?${params.join('&')}';
      final r = await _client.get('/programacion-campo$query');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) =>
                ProgramacionCampoItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // GET /programacion-campo/mia — asignaciones del empleado logueado.
  Future<List<MiProgramacionItem>> getMiProgramacion() async {
    try {
      final r = await _client.get('/programacion-campo/mia');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => MiProgramacionItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  // POST /programacion-campo/{id}/confirmar
  Future<bool> confirmar(String programacionEmpleadoId) async {
    try {
      final r = await _client
          .post('/programacion-campo/$programacionEmpleadoId/confirmar', {});
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
