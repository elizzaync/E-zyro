import 'dart:convert';
import '../core/api_client.dart';
import '../core/api_result.dart';
import '../models/indicadores_models.dart';

/// Cliente de Indicadores de desempeño (`/indicadores`).
class IndicadoresService {
  final ApiClient _client;
  IndicadoresService(this._client);

  Future<ApiResult<List<IndicadorEmpleado>>> desempeno() async {
    try {
      final r = await _client.get('/indicadores/desempeno');
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return ApiResult.ok(list.map((e) => IndicadorEmpleado.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  Future<ApiResult<ResumenDesempeno>> resumen() async {
    try {
      final r = await _client.get('/indicadores/resumen');
      if (r.statusCode == 200) {
        return ApiResult.ok(ResumenDesempeno.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
