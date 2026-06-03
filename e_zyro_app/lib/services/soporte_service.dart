import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/soporte_models.dart';

/// Tickets de soporte interno para el equipo de TI (/soporte).
class SoporteService {
  final ApiClient _client;
  SoporteService(this._client);

  /// Lista tickets. alcance: 'mios' (propios) | 'todos' (solo TI/admin).
  Future<List<TicketSoporte>> getTickets({
    String estado = '',
    String alcance = 'mios',
  }) async {
    try {
      final params = <String, String>{'alcance': alcance};
      if (estado.isNotEmpty) params['estado'] = estado;
      final query =
          params.entries.map((e) => '${e.key}=${e.value}').join('&');
      final r = await _client.get('/soporte?$query');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => TicketSoporte.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Crea un nuevo ticket de soporte.
  Future<ApiResult<TicketSoporte>> crearTicket({
    required String titulo,
    required String descripcion,
    required String categoria,
    required String prioridad,
    String? pantalla,
    String? dispositivo,
  }) async {
    try {
      final r = await _client.post('/soporte', {
        'titulo': titulo,
        'descripcion': descripcion,
        'categoria': categoria,
        'prioridad': prioridad,
        'pantalla': pantalla,
        'dispositivo': dispositivo,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(
            TicketSoporte.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Gestión por TI: cambiar estado y/o responder.
  Future<ApiResult<TicketSoporte>> gestionar(
    String id, {
    String? estado,
    String? respuestaTi,
  }) async {
    try {
      final r = await _client.patch('/soporte/$id', {
        'estado': estado,
        'respuesta_ti': respuestaTi,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(
            TicketSoporte.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
