import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/itse_models.dart';

/// Cliente de Inspección ITSE (`/itse`).
class ItseService {
  final ApiClient _client;
  ItseService(this._client);

  Future<ApiResult<List<InspeccionItse>>> listar({String? estado, String? modo}) async {
    try {
      final params = <String, String>{
        if (estado != null && estado.isNotEmpty) 'estado': estado,
        if (modo != null && modo.isNotEmpty) 'modo': modo,
      };
      final qs = Uri(queryParameters: params).query;
      final r = await _client.get('/itse${qs.isEmpty ? '' : '?$qs'}');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => InspeccionItse.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<InspeccionItse>> crear({
    required String modo,
    String? clienteId,
    String? ubicacionId,
    String? zonaId,
    String? observaciones,
  }) async {
    try {
      final r = await _client.post('/itse', {
        'modo': modo,
        'cliente_id': ?clienteId,
        'ubicacion_id': ?ubicacionId,
        'zona_id': ?zonaId,
        if (observaciones != null && observaciones.isNotEmpty) 'observaciones': observaciones,
      });
      if (r.statusCode == 201 || r.statusCode == 200) {
        return ApiResult.ok(InspeccionItse.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Genera el informe PDF de la inspección; devuelve la URL.
  Future<ApiResult<String>> generarInforme(String id) async {
    try {
      final r = await _client.post('/itse/$id/informe', {}, timeout: const Duration(seconds: 90));
      if (r.statusCode == 200) {
        final url = (jsonDecode(r.body) as Map)['pdf_url']?.toString() ?? '';
        return ApiResult.ok(url);
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<InspeccionItse>> finalizar(String id) async {
    try {
      final r = await _client.post('/itse/$id/finalizar', {});
      if (r.statusCode == 200) {
        return ApiResult.ok(InspeccionItse.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
