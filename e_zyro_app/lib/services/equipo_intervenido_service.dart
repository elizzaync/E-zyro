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
  }) async {
    try {
      final params = <String>[];
      if (clienteId != null) params.add('cliente_id=$clienteId');
      if (proyectoId != null) params.add('proyecto_id=$proyectoId');
      if (estado != null) params.add('estado=$estado');
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
