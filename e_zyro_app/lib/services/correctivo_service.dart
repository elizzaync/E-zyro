import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/correctivo_models.dart';

/// Cliente de Correctivos + Observaciones (`/correctivos`).
class CorrectivoService {
  final ApiClient _client;
  CorrectivoService(this._client);

  Future<ApiResult<List<Correctivo>>> listar({String? servicioId, String? estado}) async {
    try {
      final params = <String, String>{
        if (servicioId != null && servicioId.isNotEmpty) 'servicio_id': servicioId,
        if (estado != null && estado.isNotEmpty) 'estado': estado,
      };
      final qs = Uri(queryParameters: params).query;
      final r = await _client.get('/correctivos${qs.isEmpty ? '' : '?$qs'}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => Correctivo.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Correctivo>> crear({required String servicioId, String? alcance}) async {
    try {
      final r = await _client.post('/correctivos', {
        'servicio_id': servicioId,
        if (alcance != null && alcance.isNotEmpty) 'alcance': alcance,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(Correctivo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<Correctivo>> transicionar(String id, String nuevoEstado) async {
    try {
      final r = await _client.post('/correctivos/$id/transicion', {'nuevo_estado': nuevoEstado});
      if (r.statusCode == 200) {
        return ApiResult.ok(Correctivo.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Genera el informe PDF del correctivo; devuelve la URL.
  Future<ApiResult<String>> generarInforme(String id) async {
    try {
      final r = await _client.post('/correctivos/$id/generar-informe', {},
          timeout: const Duration(seconds: 90));
      if (r.statusCode == 200) {
        final url = (jsonDecode(r.body) as Map)['informe_url']?.toString() ?? '';
        return ApiResult.ok(url);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<List<Observacion>>> observaciones(String servicioId) async {
    try {
      final r = await _client.get('/correctivos/servicios/$servicioId/observaciones');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => Observacion.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
