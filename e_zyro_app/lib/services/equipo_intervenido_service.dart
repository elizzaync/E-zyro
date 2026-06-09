import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/equipo_intervenido_models.dart';

class EquipoIntervenidoService {
  final ApiClient _client;
  EquipoIntervenidoService(this._client);

  Future<ApiResult<List<EquipoIntervenido>>> listar({
    String? clienteId,
    String? proyectoId,
    String? estado,
    String? ubicacionId,
    String? zonaId,
    String? areaId,
  }) async {
    try {
      final params = <String>[];
      if (clienteId != null) params.add('cliente_id=$clienteId');
      if (proyectoId != null) params.add('proyecto_id=$proyectoId');
      if (estado != null) params.add('estado=$estado');
      if (ubicacionId != null) params.add('ubicacion_id=$ubicacionId');
      if (zonaId != null) params.add('zona_id=$zonaId');
      if (areaId != null) params.add('area_id=$areaId');
      final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
      final r = await _client.get('/equipos-intervenidos$qs');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => EquipoIntervenido.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoIntervenido>> obtener(String id) async {
    try {
      final r = await _client.get('/equipos-intervenidos/$id');
      if (r.statusCode == 200) {
        return ApiResult.ok(
            EquipoIntervenido.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoIntervenido>> crear(Map<String, dynamic> body) async {
    try {
      final r = await _client.post('/equipos-intervenidos', body);
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(
            EquipoIntervenido.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoIntervenido>> actualizar(
      String id, Map<String, dynamic> body) async {
    try {
      final r = await _client.patch('/equipos-intervenidos/$id', body);
      if (r.statusCode == 200) {
        return ApiResult.ok(
            EquipoIntervenido.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Historial de mantenimientos del equipo (más reciente primero).
  Future<ApiResult<List<MantenimientoEquipo>>> listarMantenimientos(String id) async {
    try {
      final r = await _client.get('/equipos-intervenidos/$id/mantenimientos');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list
            .map((e) => MantenimientoEquipo.fromJson(e as Map<String, dynamic>))
            .toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Registra un mantenimiento ejecutado: el backend guarda el evento y
  /// recalcula ultimo/proximo mantenimiento. Devuelve el equipo actualizado.
  Future<ApiResult<EquipoIntervenido>> registrarMantenimiento(
    String id, {
    String? fecha,          // yyyy-MM-dd (default: hoy)
    String? tipo,           // preventivo | correctivo | inspeccion | otro
    String? descripcion,
    String? realizadoPor,
    int? frecuenciaMeses,
  }) async {
    try {
      final r = await _client.post('/equipos-intervenidos/$id/mantenimiento', {
        'fecha': ?fecha,
        'tipo': ?tipo,
        'descripcion': ?descripcion,
        'realizado_por': ?realizadoPor,
        'frecuencia_meses': ?frecuenciaMeses,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(
            EquipoIntervenido.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminar(String id) async {
    try {
      final r = await _client.delete('/equipos-intervenidos/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
