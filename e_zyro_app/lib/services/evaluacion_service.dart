import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/evaluacion_models.dart';

/// Cliente de Evaluaciones de desempeño (`/evaluaciones`).
class EvaluacionService {
  final ApiClient _client;
  EvaluacionService(this._client);

  // ── Criterios ───────────────────────────────────────────────────────────
  Future<ApiResult<List<CriterioEvaluacion>>> listarCriterios({String? tipo}) async {
    try {
      final qs = tipo != null ? '?tipo=$tipo' : '';
      final r = await _client.get('/evaluaciones/criterios$qs');
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
    String tipo = 'rrhh',
  }) async {
    try {
      final r = await _client.post('/evaluaciones/criterios', {
        'nombre': nombre,
        'descripcion': ?descripcion,
        'peso': peso,
        'tipo': tipo,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(CriterioEvaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarCriterio(String id) async {
    try {
      final r = await _client.delete('/evaluaciones/criterios/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok(null);
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  // ── Plantillas ────────────────────────────────────────────────────────────
  Future<ApiResult<List<PlantillaEvaluacion>>> listarPlantillas({String? tipo}) async {
    try {
      final qs = tipo != null ? '?tipo=$tipo' : '';
      final r = await _client.get('/evaluaciones/plantillas$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => PlantillaEvaluacion.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<PlantillaEvaluacion>> obtenerPlantilla(String id) async {
    try {
      final r = await _client.get('/evaluaciones/plantillas/$id');
      if (r.statusCode == 200) {
        return ApiResult.ok(PlantillaEvaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<PlantillaEvaluacion>> crearPlantilla({
    required String nombre,
    String? descripcion,
    required String tipo,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final r = await _client.post('/evaluaciones/plantillas', {
        'nombre': nombre,
        'descripcion': ?descripcion,
        'tipo': tipo,
        'items': items,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(PlantillaEvaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<PlantillaEvaluacion>> editarPlantilla({
    required String id,
    required String nombre,
    String? descripcion,
    required String tipo,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final r = await _client.put('/evaluaciones/plantillas/$id', {
        'nombre': nombre,
        'descripcion': ?descripcion,
        'tipo': tipo,
        'items': items,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(PlantillaEvaluacion.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminarPlantilla(String id) async {
    try {
      final r = await _client.delete('/evaluaciones/plantillas/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok(null);
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<Evaluacion>>> asignarPlantilla({
    required String plantillaId,
    required List<String> empleadoIds,
    required String periodo,
    String? fecha,
  }) async {
    try {
      final r = await _client.post('/evaluaciones/plantillas/$plantillaId/asignar', {
        'empleado_ids': empleadoIds,
        'periodo': periodo,
        'fecha': ?fecha,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => Evaluacion.fromJson(e as Map<String, dynamic>)).toList());
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

  /// Evaluaciones asignadas al empleado del token (autoservicio, incluye asignadas+completadas).
  Future<ApiResult<List<Evaluacion>>> mias() async {
    try {
      final r = await _client.get('/evaluaciones/mias');
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
    String tipo = 'rrhh',
    String? fecha,
    required List<DetalleEvaluacion> detalles,
  }) async {
    try {
      final r = await _client.post('/evaluaciones', {
        'empleado_id': empleadoId,
        'periodo': periodo,
        'tipo': tipo,
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

  /// El empleado completa su propia evaluación asignada (estado asignada → completada).
  Future<ApiResult<Evaluacion>> completarPropia({
    required String evaluacionId,
    required List<DetalleEvaluacion> detalles,
    String? notasEvaluador,
  }) async {
    try {
      final r = await _client.post('/evaluaciones/$evaluacionId/completar-propia', {
        'detalles': detalles.map((d) => d.toJson()).toList(),
        'notas_evaluador': ?notasEvaluador,
      });
      if (r.statusCode == 200) {
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
