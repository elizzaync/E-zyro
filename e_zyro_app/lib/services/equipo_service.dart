import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/equipo_models.dart';

/// Gestión de Equipos y Herramientas propios de E-System (`/logistica/equipos`).
class EquipoService {
  final ApiClient _client;
  EquipoService(this._client);

  Future<ApiResult<EquiposListResponse>> listar({
    String q = '',
    String clase = 'todas',
    String estado = 'todos',
    int page = 1,
    int pageSize = 100,
  }) async {
    try {
      final params = [
        if (q.isNotEmpty) 'q=${Uri.encodeComponent(q)}',
        'clase=$clase',
        'estado=$estado',
        'page=$page',
        'page_size=$pageSize',
      ].join('&');
      final r = await _client.get('/logistica/equipos?$params');
      if (r.statusCode == 200) {
        return ApiResult.ok(
            EquiposListResponse.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoItem>> crear(Map<String, dynamic> body) async {
    try {
      final r = await _client.post('/logistica/equipos', body);
      if (r.statusCode == 201) {
        return ApiResult.ok(
            EquipoItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<EquipoItem>> actualizar(String id, Map<String, dynamic> body) async {
    try {
      final r = await _client.patch('/logistica/equipos/$id', body);
      if (r.statusCode == 200) {
        return ApiResult.ok(
            EquipoItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<void>> eliminar(String id) async {
    try {
      final r = await _client.delete('/logistica/equipos/$id');
      if (r.statusCode == 204 || r.statusCode == 200) return const ApiResult.ok();
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
