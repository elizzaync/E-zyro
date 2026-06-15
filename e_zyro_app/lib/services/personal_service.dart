import 'dart:convert';
import '../core/api_client.dart';
import '../utils/json_async.dart';
import '../core/api_result.dart';
import '../models/personal_models.dart';

/// Cliente del módulo Personal/RR.HH. (`/personal`).
class PersonalService {
  final ApiClient _client;
  PersonalService(this._client);

  /// Lista empleados de la empresa (opcional búsqueda y filtro de activos).
  Future<ApiResult<List<Empleado>>> listar({String? q, bool soloActivos = true}) async {
    try {
      final params = <String>['solo_activos=$soloActivos'];
      if (q != null && q.trim().isNotEmpty) params.add('q=${Uri.encodeQueryComponent(q.trim())}');
      final r = await _client.get('/personal?${params.join('&')}');
      if (r.statusCode == 200) {
        final list = (await decodeJson(r.body)) as List;
        return ApiResult.ok(list.map((e) => Empleado.fromJson(e as Map<String, dynamic>)).toList());
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }

  /// Historial laboral consolidado de un empleado.
  Future<ApiResult<HistorialPersonal>> historial(String empleadoId) async {
    try {
      final r = await _client.get('/personal/$empleadoId/historial');
      if (r.statusCode == 200) {
        return ApiResult.ok(HistorialPersonal.fromJson(jsonDecode(r.body) as Map<String, dynamic>));
      }
      return ApiResult.fail(ApiError.fromResponse(r));
    } catch (_) {
      return const ApiResult.fail(ApiError(ApiErrorKind.network));
    }
  }
}
