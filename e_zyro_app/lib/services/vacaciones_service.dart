import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/vacaciones_models.dart';

/// Cliente de Vacaciones por ley (`/vacaciones`).
class VacacionesService {
  final ApiClient _client;
  VacacionesService(this._client);

  Future<ApiResult<ConfigVacaciones>> obtenerConfig() async {
    try {
      final r = await _client.get('/vacaciones/config');
      if (r.statusCode == 200) {
        return ApiResult.ok(ConfigVacaciones.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<ConfigVacaciones>> guardarConfig({
    required String regimen, int? diasPorAnio, int? topeAcumulacion,
  }) async {
    try {
      final r = await _client.put('/vacaciones/config', {
        'regimen': regimen,
        'dias_por_anio': ?diasPorAnio,
        'tope_acumulacion': ?topeAcumulacion,
      });
      if (r.statusCode == 200) {
        return ApiResult.ok(ConfigVacaciones.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<SaldoVacaciones>>> listarSaldos() async {
    try {
      final r = await _client.get('/vacaciones/saldos');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => SaldoVacaciones.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Saldo de vacaciones del empleado del token (autoservicio).
  Future<ApiResult<SaldoVacaciones>> miSaldo() async {
    try {
      final r = await _client.get('/vacaciones/mi-saldo');
      if (r.statusCode == 200) {
        return ApiResult.ok(SaldoVacaciones.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Solicitudes propias del empleado del token (autoservicio).
  Future<ApiResult<List<SolicitudVacaciones>>> misSolicitudes() async {
    try {
      final r = await _client.get('/vacaciones/mis-solicitudes');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => SolicitudVacaciones.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<SolicitudVacaciones>>> listarSolicitudes({String? empleadoId, String? estado}) async {
    try {
      final params = <String>[];
      if (empleadoId != null) params.add('empleado_id=$empleadoId');
      if (estado != null) params.add('estado=$estado');
      final qs = params.isEmpty ? '' : '?${params.join('&')}';
      final r = await _client.get('/vacaciones/solicitudes$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => SolicitudVacaciones.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<SolicitudVacaciones>> crearSolicitud({
    String? empleadoId,
    required String fechaInicio,
    required String fechaFin,
    String? motivo,
  }) async {
    try {
      final r = await _client.post('/vacaciones/solicitudes', {
        'empleado_id': ?empleadoId,
        'fecha_inicio': fechaInicio,
        'fecha_fin': fechaFin,
        'motivo': ?motivo,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(SolicitudVacaciones.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<SolicitudVacaciones>> resolver(String id, {required bool aprobar}) async {
    try {
      final accion = aprobar ? 'aprobar' : 'rechazar';
      final r = await _client.post('/vacaciones/solicitudes/$id/$accion', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(SolicitudVacaciones.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Fija el saldo inicial de vacaciones de un empleado (para migración).
  /// [diasDisponibles] = días disponibles reales que el empleado tiene ahora.
  Future<ApiResult<void>> setSaldoInicial({
    required String empleadoId,
    required double diasDisponibles,
    String? notas,
  }) async {
    try {
      final r = await _client.put('/vacaciones/saldo-inicial/$empleadoId', {
        'dias_disponibles': diasDisponibles,
        'notas': ?notas,
      });
      if (r.statusCode == 200) return const ApiResult.ok(null);
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
