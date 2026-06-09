import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/evaluacion_models.dart';

/// Cliente de Evaluaciones de desempeño (`/evaluaciones`).
class EvaluacionService {
  final ApiClient _client;
  EvaluacionService(this._client);

  // ── Criterios ───────────────────────────────────────────────────────────
  Future<ApiResult<List<CriterioEvaluacion>>> listarCriterios() async {
    try {
      final r = await _client.get('/evaluaciones/criterios');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => CriterioEvaluacion.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<CriterioEvaluacion>> crearCriterio({
    required String nombre, String? descripcion, double peso = 1.0,
  }) async {
    try {
      final r = await _client.post('/evaluaciones/criterios', {
        'nombre': nombre,
        'descripcion': ?descripcion,
        'peso': peso,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(CriterioEvaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Evaluaciones ──────────────────────────────────────────────────────────
  Future<ApiResult<List<Evaluacion>>> listar({String? empleadoId, String? estado}) async {
    try {
      final params = <String>[];
      if (empleadoId != null) params.add('empleado_id=$empleadoId');
      if (estado != null) params.add('estado=$estado');
      final qs = params.isEmpty ? '' : '?${params.join('&')}';
      final r = await _client.get('/evaluaciones$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => Evaluacion.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Evaluacion>> detalle(String id) async {
    try {
      final r = await _client.get('/evaluaciones/$id');
      if (r.statusCode == 200) {
        return ApiResult.ok(Evaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Evaluacion>> crear({
    required String empleadoId,
    required String periodo,
    String? fecha,
    required List<DetalleEvaluacion> detalles,
  }) async {
    try {
      final r = await _client.post('/evaluaciones', {
        'empleado_id': empleadoId,
        'periodo': periodo,
        'fecha': ?fecha,
        'detalles': detalles.map((d) => d.toJson()).toList(),
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(Evaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Cambia el estado: 'enviada' (desde borrador) o 'completada' (desde enviada).
  Future<ApiResult<Evaluacion>> cambiarEstado(String id, String estado) async {
    try {
      final r = await _client.post('/evaluaciones/$id/estado', {'estado': estado});
      if (r.statusCode == 200) {
        return ApiResult.ok(Evaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminar(String id) async {
    try {
      final r = await _client.delete('/evaluaciones/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok(null);
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
