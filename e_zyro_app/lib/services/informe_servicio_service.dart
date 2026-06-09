import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/informe_servicio_models.dart';

/// Cliente de informes de servicio (`/servicios/{id}/...`).
class InformeServicioService {
  final ApiClient _client;
  InformeServicioService(this._client);

  Future<ApiResult<List<InformeServicio>>> listar(String servicioId) async {
    try {
      final r = await _client.get('/servicios/$servicioId/informes');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(
            list.map((e) => InformeServicio.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Listado global de informes de la empresa (todos los servicios), con
  /// filtros opcionales por proyecto, servicio y tipo (`pre`|`final`).
  Future<ApiResult<List<InformeServicio>>> listarTodos({
    String? proyectoId,
    String? servicioId,
    String? tipo,
    int limit = 200,
  }) async {
    try {
      final params = <String>['limit=$limit'];
      if (proyectoId != null && proyectoId.isNotEmpty) {
        params.add('proyecto_id=${Uri.encodeQueryComponent(proyectoId)}');
      }
      if (servicioId != null && servicioId.isNotEmpty) {
        params.add('servicio_id=${Uri.encodeQueryComponent(servicioId)}');
      }
      if (tipo != null && tipo.isNotEmpty) {
        params.add('tipo=${Uri.encodeQueryComponent(tipo)}');
      }
      final r = await _client.get('/servicios/informes-todos?${params.join('&')}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(
            list.map((e) => InformeServicio.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<InformeServicio>> generarPre(String servicioId) =>
      _generar('/servicios/$servicioId/pre-informe');

  Future<ApiResult<InformeServicio>> generarFinal(String servicioId) =>
      _generar('/servicios/$servicioId/informe-final');

  Future<ApiResult<InformeServicio>> _generar(String path) async {
    try {
      final r = await _client.post(path, {}, timeout: const Duration(seconds: 90));
      if (r.statusCode == 200 || r.statusCode == 201) {
        return ApiResult.ok(InformeServicio.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
