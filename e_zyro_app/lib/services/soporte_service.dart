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

  /// TI se asigna el ticket (lo "toma" para atenderlo).
  Future<ApiResult<TicketSoporte>> tomar(String id) async {
    try {
      final r = await _client.post('/soporte/$id/tomar', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(
            TicketSoporte.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Timeline de actividades del ticket (comentarios, avances, soluciones…).
  Future<List<TicketActividad>> getActividades(String id) async {
    try {
      final r = await _client.get('/soporte/$id/actividades');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List? ?? [];
        return list
            .map((e) => TicketActividad.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Crea una actividad (comentario / avance / solución), con imagen opcional
  /// en base64. Marcar [esSolucion] versiona automáticamente la solución.
  Future<ApiResult<TicketActividad>> crearActividad(
    String id, {
    required String tipo,
    String? texto,
    bool esSolucion = false,
    String? adjuntoBase64,
  }) async {
    try {
      final r = await _client.post('/soporte/$id/actividades', {
        'tipo': tipo,
        'texto': texto,
        'es_solucion': esSolucion,
        'adjunto_base64': adjuntoBase64,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(
            TicketActividad.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
